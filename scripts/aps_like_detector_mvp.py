#!/usr/bin/env python3
"""Publish a low-cost, point-cloud APS-like result with path context.

The fleet v4 detector consumes existing Autoware clustering output rather
than the full point cloud. APS-like geometry is measured with a minimum-area
oriented footprint box so view angle does not inflate base-link-axis extents.
Its default geometry envelope is calculated from the tracked APS vehicle model
instead of an independent set of detector dimensions.
When a current planning trajectory is available, the candidate is projected
onto it to determine whether it is ahead in the same curved path corridor.
At close range, a narrowly bounded path-only rule tolerates the known cluster
width inflation while retaining the strict geometry rule everywhere else.

The detector is observational: it publishes JSON on ``std_msgs/msg/String``
and never publishes a planning or control command. It identifies APS-like
geometry, not a cryptographic vehicle identity.
"""

from __future__ import annotations

import json
import math
import sys
import time
from collections import deque
from pathlib import Path
from typing import Any

import rclpy
import yaml
from autoware_perception_msgs.msg import DetectedObjects
from autoware_planning_msgs.msg import Trajectory
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import (
    DurabilityPolicy,
    HistoryPolicy,
    QoSProfile,
    ReliabilityPolicy,
    qos_profile_sensor_data,
)
from rclpy.time import Time
from std_msgs.msg import String
from tf2_ros import Buffer, TransformListener


APS_MODEL_INFO_RELATIVE_PATH = Path(
    "src/launcher/autoware_launch_APS/vehicle/aps_vehicle_launch/"
    "aps_vehicle_description/config/vehicle_info.param.yaml"
)


def aps_model_geometry_from_vehicle_info(data: dict[str, Any]) -> dict[str, float]:
    """Calculate the APS body envelope from its tracked Autoware model file."""

    params = data["/**"]["ros__parameters"]
    length = (
        float(params["front_overhang"])
        + float(params["wheel_base"])
        + float(params["rear_overhang"])
    )
    width = (
        float(params["left_overhang"])
        + float(params["wheel_tread"])
        + float(params["right_overhang"])
    )
    height = float(params["vehicle_height"])
    if not all(math.isfinite(value) and value > 0.0 for value in (length, width, height)):
        raise ValueError("APS model dimensions must be finite and positive")
    return {
        "length": length,
        "width": width,
        "height": height,
        "footprint_aspect": max(length, width) / min(length, width),
    }


def load_aps_model_geometry(path: Path) -> dict[str, float]:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError("APS model vehicle-info file must contain a mapping")
    return aps_model_geometry_from_vehicle_info(data)


def aps_model_default_limits(model: dict[str, float]) -> dict[str, float]:
    """Derive observed-cluster tolerances as ratios of the APS body model."""

    length = model["length"]
    width = model["width"]
    height = model["height"]
    height_width_ratio = height / width
    return {
        "prefilter_min_height": 0.55 * height,
        "prefilter_max_height": 1.25 * height,
        "min_depth": 0.17 * length,
        "max_depth": 0.68 * length,
        "max_footprint_aspect": 1.20 * model["footprint_aspect"],
        "min_width": 0.74 * width,
        "max_width": 1.27 * width,
        "min_height": 0.84 * height,
        "max_height": 1.02 * height,
        "min_ratio": 0.68 * height_width_ratio,
        "max_ratio": 1.26 * height_width_ratio,
        "path_close_min_depth": 0.47 * length,
        "path_close_max_depth": 0.64 * length,
        "path_close_max_width": 1.64 * width,
        "path_close_min_height": 0.84 * height,
        "path_close_max_height": 0.94 * height,
        "path_close_min_ratio": 0.53 * height_width_ratio,
        "prototype_depth": 0.31 * length,
        "prototype_width": 0.95 * width,
        "prototype_height": 0.88 * height,
    }


def minimum_area_box(points: Any) -> tuple[float, float, float] | None:
    """Return short side, long side, and long-axis angle for a convex polygon."""

    if len(points) < 3:
        return None
    best: tuple[float, float, float, float] | None = None
    for index, point in enumerate(points):
        next_point = points[(index + 1) % len(points)]
        edge_angle = math.atan2(
            next_point.y - point.y, next_point.x - point.x
        )
        cosine = math.cos(edge_angle)
        sine = math.sin(edge_angle)
        rotated_x = [item.x * cosine + item.y * sine for item in points]
        rotated_y = [-item.x * sine + item.y * cosine for item in points]
        extent_x = max(rotated_x) - min(rotated_x)
        extent_y = max(rotated_y) - min(rotated_y)
        if extent_x <= 0.0 or extent_y <= 0.0:
            continue
        short_side = min(extent_x, extent_y)
        long_side = max(extent_x, extent_y)
        long_angle = edge_angle if extent_x >= extent_y else edge_angle + math.pi / 2
        result = (extent_x * extent_y, short_side, long_side, long_angle)
        if best is None or result[0] < best[0]:
            best = result
    if best is None:
        return None
    angle = (best[3] + math.pi) % (2 * math.pi) - math.pi
    return best[1], best[2], angle


def project_point_to_polyline(
    x: float, y: float, points: list[tuple[float, float]]
) -> tuple[float, float] | None:
    """Return arc length and signed lateral offset at the nearest segment."""

    if len(points) < 2:
        return None
    best: tuple[float, float, float] | None = None
    cumulative = 0.0
    for first, second in zip(points, points[1:]):
        delta_x = second[0] - first[0]
        delta_y = second[1] - first[1]
        length_squared = delta_x * delta_x + delta_y * delta_y
        if length_squared <= 1e-9:
            continue
        length = math.sqrt(length_squared)
        fraction = (
            (x - first[0]) * delta_x + (y - first[1]) * delta_y
        ) / length_squared
        fraction = max(0.0, min(1.0, fraction))
        nearest_x = first[0] + fraction * delta_x
        nearest_y = first[1] + fraction * delta_y
        residual_x = x - nearest_x
        residual_y = y - nearest_y
        distance_squared = residual_x * residual_x + residual_y * residual_y
        signed_lateral = (
            delta_x * residual_y - delta_y * residual_x
        ) / length
        result = (
            distance_squared,
            cumulative + fraction * length,
            signed_lateral,
        )
        if best is None or result[0] < best[0]:
            best = result
        cumulative += length
    if best is None:
        return None
    return best[1], best[2]


def transform_xy(x: float, y: float, transform: Any) -> tuple[float, float]:
    """Apply a geometry_msgs Transform to a planar point."""

    rotation = transform.rotation
    yaw = math.atan2(
        2.0 * (rotation.w * rotation.z + rotation.x * rotation.y),
        1.0 - 2.0 * (rotation.y * rotation.y + rotation.z * rotation.z),
    )
    cosine = math.cos(yaw)
    sine = math.sin(yaw)
    return (
        transform.translation.x + cosine * x - sine * y,
        transform.translation.y + sine * x + cosine * y,
    )


def path_close_range_geometry_match(
    candidate: dict[str, Any], limits: dict[str, float]
) -> bool:
    """Accept the measured close APS profile only inside the live path."""

    failed_gates = candidate.get("strict_failed_gates", [])
    return (
        candidate.get("in_path_corridor") is True
        and set(failed_gates) == {"width", "height_width_ratio"}
        and len(failed_gates) == 2
        and limits["path_min_forward"]
        <= candidate["path_forward_m"]
        <= limits["path_close_max_forward"]
        and limits["path_close_min_depth"]
        <= candidate["oriented_short_side_m"]
        <= limits["path_close_max_depth"]
        and limits["max_width"]
        < candidate["oriented_long_side_m"]
        <= limits["path_close_max_width"]
        and limits["path_close_min_height"]
        <= candidate["height_m"]
        <= limits["path_close_max_height"]
        and limits["path_close_min_ratio"]
        <= candidate["height_width_ratio"]
        < limits["min_ratio"]
    )


def strict_geometry_gate_results(
    distance: float,
    short_side: float,
    long_side: float,
    height: float,
    limits: dict[str, float],
) -> dict[str, bool]:
    """Evaluate strict APS geometry, including a human-confuser footprint gate."""

    ratio = height / long_side
    footprint_aspect = long_side / short_side
    return {
        "range": limits["min_range"] <= distance <= limits["max_range"],
        "visible_depth": limits["min_depth"]
        <= short_side
        <= limits["max_depth"],
        "width": limits["min_width"] <= long_side <= limits["max_width"],
        "height": limits["min_height"] <= height <= limits["max_height"],
        "height_width_ratio": limits["min_ratio"]
        <= ratio
        <= limits["max_ratio"],
        "footprint_aspect_ratio": footprint_aspect
        <= limits["max_footprint_aspect"],
    }


class ApsLikeDetector(Node):
    """Apply temporal APS geometry detection and optional path projection."""

    def __init__(self) -> None:
        super().__init__("aps_like_detector_mvp")

        self.declare_parameter(
            "input_topic",
            "/perception/object_recognition/detection/clustering/objects",
        )
        self.declare_parameter(
            "trajectory_topic", "/planning/scenario_planning/trajectory"
        )
        self.declare_parameter(
            "output_topic", "/perception/aps_like_detector/result"
        )
        self.declare_parameter("window_size", 10)
        self.declare_parameter("min_hits", 7)
        self.declare_parameter("min_samples", 5)

        default_model_info_path = (
            Path(__file__).resolve().parents[1] / APS_MODEL_INFO_RELATIVE_PATH
        )
        self.declare_parameter(
            "aps_model_vehicle_info_path", str(default_model_info_path)
        )
        self._model_info_path = Path(
            str(self.get_parameter("aps_model_vehicle_info_path").value)
        ).expanduser()
        try:
            self._model_geometry = load_aps_model_geometry(self._model_info_path)
        except (OSError, KeyError, TypeError, ValueError, yaml.YAMLError) as exc:
            raise RuntimeError(
                f"cannot load APS model geometry from {self._model_info_path}"
            ) from exc
        model_defaults = aps_model_default_limits(self._model_geometry)

        self.declare_parameter("min_range_m", 0.5)
        self.declare_parameter("max_range_m", 8.0)
        self.declare_parameter(
            "prefilter_min_height_m", model_defaults["prefilter_min_height"]
        )
        self.declare_parameter(
            "prefilter_max_height_m", model_defaults["prefilter_max_height"]
        )
        self.declare_parameter("min_visible_depth_m", model_defaults["min_depth"])
        self.declare_parameter("max_visible_depth_m", model_defaults["max_depth"])
        # Near-range occlusion can shrink both APS and human footprints.  Their
        # measured bottom-plane shape remains separable: APS stays close to a
        # compact rectangle while the observed standing-person cluster is more
        # elongated.  Bound that ratio instead of rejecting partial APS depth.
        self.declare_parameter(
            "max_footprint_aspect_ratio",
            model_defaults["max_footprint_aspect"],
        )
        self.declare_parameter("min_width_m", model_defaults["min_width"])
        self.declare_parameter("max_width_m", model_defaults["max_width"])
        self.declare_parameter("min_height_m", model_defaults["min_height"])
        self.declare_parameter("max_height_m", model_defaults["max_height"])
        self.declare_parameter(
            "min_height_width_ratio", model_defaults["min_ratio"]
        )
        self.declare_parameter(
            "max_height_width_ratio", model_defaults["max_ratio"]
        )

        self.declare_parameter("path_min_forward_m", 0.5)
        self.declare_parameter("path_max_forward_m", 8.0)
        self.declare_parameter("path_half_width_m", 1.2)
        self.declare_parameter("trajectory_timeout_sec", 1.0)
        self.declare_parameter("path_close_range_max_forward_m", 2.5)
        self.declare_parameter(
            "path_close_range_min_visible_depth_m",
            model_defaults["path_close_min_depth"],
        )
        self.declare_parameter(
            "path_close_range_max_visible_depth_m",
            model_defaults["path_close_max_depth"],
        )
        self.declare_parameter(
            "path_close_range_max_width_m",
            model_defaults["path_close_max_width"],
        )
        self.declare_parameter(
            "path_close_range_min_height_m",
            model_defaults["path_close_min_height"],
        )
        self.declare_parameter(
            "path_close_range_max_height_m",
            model_defaults["path_close_max_height"],
        )
        self.declare_parameter(
            "path_close_range_min_height_width_ratio",
            model_defaults["path_close_min_ratio"],
        )
        self.declare_parameter("fallback_min_x_m", 0.0)
        self.declare_parameter("fallback_max_abs_y_m", 2.5)

        self.declare_parameter(
            "prototype_visible_depth_m", model_defaults["prototype_depth"]
        )
        self.declare_parameter(
            "prototype_width_m", model_defaults["prototype_width"]
        )
        self.declare_parameter(
            "prototype_height_m", model_defaults["prototype_height"]
        )

        window_size = max(1, int(self.get_parameter("window_size").value))
        self._min_hits = max(1, int(self.get_parameter("min_hits").value))
        self._min_samples = max(1, int(self.get_parameter("min_samples").value))
        self._history: deque[bool] = deque(maxlen=window_size)
        self._last_input_monotonic: float | None = None
        self._last_state: str | None = None

        self._limits = {
            "min_range": float(self.get_parameter("min_range_m").value),
            "max_range": float(self.get_parameter("max_range_m").value),
            "prefilter_min_height": float(
                self.get_parameter("prefilter_min_height_m").value
            ),
            "prefilter_max_height": float(
                self.get_parameter("prefilter_max_height_m").value
            ),
            "min_depth": float(
                self.get_parameter("min_visible_depth_m").value
            ),
            "max_depth": float(
                self.get_parameter("max_visible_depth_m").value
            ),
            "max_footprint_aspect": float(
                self.get_parameter("max_footprint_aspect_ratio").value
            ),
            "min_width": float(self.get_parameter("min_width_m").value),
            "max_width": float(self.get_parameter("max_width_m").value),
            "min_height": float(self.get_parameter("min_height_m").value),
            "max_height": float(self.get_parameter("max_height_m").value),
            "min_ratio": float(
                self.get_parameter("min_height_width_ratio").value
            ),
            "max_ratio": float(
                self.get_parameter("max_height_width_ratio").value
            ),
            "path_min_forward": float(
                self.get_parameter("path_min_forward_m").value
            ),
            "path_max_forward": float(
                self.get_parameter("path_max_forward_m").value
            ),
            "path_half_width": float(
                self.get_parameter("path_half_width_m").value
            ),
            "trajectory_timeout": float(
                self.get_parameter("trajectory_timeout_sec").value
            ),
            "path_close_max_forward": float(
                self.get_parameter("path_close_range_max_forward_m").value
            ),
            "path_close_min_depth": float(
                self.get_parameter(
                    "path_close_range_min_visible_depth_m"
                ).value
            ),
            "path_close_max_depth": float(
                self.get_parameter(
                    "path_close_range_max_visible_depth_m"
                ).value
            ),
            "path_close_max_width": float(
                self.get_parameter("path_close_range_max_width_m").value
            ),
            "path_close_min_height": float(
                self.get_parameter("path_close_range_min_height_m").value
            ),
            "path_close_max_height": float(
                self.get_parameter("path_close_range_max_height_m").value
            ),
            "path_close_min_ratio": float(
                self.get_parameter(
                    "path_close_range_min_height_width_ratio"
                ).value
            ),
            "fallback_min_x": float(
                self.get_parameter("fallback_min_x_m").value
            ),
            "fallback_max_abs_y": float(
                self.get_parameter("fallback_max_abs_y_m").value
            ),
        }
        self._prototype = {
            "depth": float(
                self.get_parameter("prototype_visible_depth_m").value
            ),
            "width": float(self.get_parameter("prototype_width_m").value),
            "height": float(self.get_parameter("prototype_height_m").value),
        }

        self._trajectory_points: list[tuple[float, float]] = []
        self._trajectory_frame = ""
        self._trajectory_received_monotonic: float | None = None
        self._tf_buffer: Buffer | None = None
        self._tf_listener: TransformListener | None = None

        output_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )
        input_topic = str(self.get_parameter("input_topic").value)
        trajectory_topic = str(self.get_parameter("trajectory_topic").value)
        output_topic = str(self.get_parameter("output_topic").value)
        self._publisher = self.create_publisher(String, output_topic, output_qos)
        self._subscription = self.create_subscription(
            DetectedObjects, input_topic, self._on_objects, qos_profile_sensor_data
        )
        self._trajectory_subscription = self.create_subscription(
            Trajectory,
            trajectory_topic,
            self._on_trajectory,
            qos_profile_sensor_data,
        )
        self._stale_timer = self.create_timer(1.0, self._publish_stale_if_needed)

        self.get_logger().info(
            "APS-like MVP v4 listening on "
            f"{input_topic} and {trajectory_topic}; publishing {output_topic}; "
            "model="
            f"{self._model_geometry['length']:.3f}x"
            f"{self._model_geometry['width']:.3f}x"
            f"{self._model_geometry['height']:.3f}m"
        )

    @staticmethod
    def _closeness(value: float, target: float, tolerance: float) -> float:
        return max(0.0, 1.0 - abs(value - target) / tolerance)

    def _on_trajectory(self, msg: Trajectory) -> None:
        self._trajectory_points = [
            (float(point.pose.position.x), float(point.pose.position.y))
            for point in msg.points
        ]
        self._trajectory_frame = msg.header.frame_id
        self._trajectory_received_monotonic = time.monotonic()
        if len(self._trajectory_points) >= 2 and self._tf_buffer is None:
            self._tf_buffer = Buffer(cache_time=Duration(seconds=3.0))
            self._tf_listener = TransformListener(self._tf_buffer, self)

    def _measurement_from_object(self, obj: Any) -> dict[str, Any] | None:
        position = obj.kinematics.pose_with_covariance.pose.position
        footprint = obj.shape.footprint.points
        height = float(obj.shape.dimensions.z)
        distance = math.hypot(float(position.x), float(position.y))
        limits = self._limits

        if not (
            len(footprint) >= 3
            and 0.5 * limits["min_range"] <= distance <= 1.25 * limits["max_range"]
            and limits["prefilter_min_height"]
            <= height
            <= limits["prefilter_max_height"]
        ):
            return None

        oriented_box = minimum_area_box(footprint)
        if oriented_box is None:
            return None
        short_side, long_side, angle = oriented_box
        if long_side <= 0.0:
            return None
        ratio = height / long_side
        gates = strict_geometry_gate_results(
            distance, short_side, long_side, height, limits
        )
        failed_gates = [name for name, passed in gates.items() if not passed]
        score = (
            0.40 * self._closeness(long_side, self._prototype["width"], 0.22)
            + 0.35 * self._closeness(height, self._prototype["height"], 0.35)
            + 0.25
            * self._closeness(short_side, self._prototype["depth"], 0.35)
        )
        return {
            "x_m": float(position.x),
            "y_m": float(position.y),
            "z_m": float(position.z),
            "range_m": distance,
            "oriented_short_side_m": short_side,
            "oriented_long_side_m": long_side,
            "oriented_long_axis_deg": math.degrees(angle),
            "height_m": height,
            "height_width_ratio": ratio,
            "footprint_aspect_ratio": long_side / short_side,
            "geometry_score": score,
            "geometry_match": not failed_gates,
            "failed_gates": failed_gates,
        }

    def _prepare_path_context(
        self, object_frame: str
    ) -> tuple[dict[str, Any], dict[str, Any] | None]:
        if self._trajectory_received_monotonic is None or len(
            self._trajectory_points
        ) < 2:
            return {"available": False, "reason": "NO_TRAJECTORY"}, None

        age = time.monotonic() - self._trajectory_received_monotonic
        public = {
            "available": False,
            "reason": "TRAJECTORY_STALE",
            "age_sec": round(age, 3),
            "frame_id": self._trajectory_frame,
            "point_count": len(self._trajectory_points),
        }
        if age > self._limits["trajectory_timeout"]:
            return public, None
        if not self._trajectory_frame or not object_frame:
            public["reason"] = "FRAME_ID_MISSING"
            return public, None

        transform = None
        if self._trajectory_frame == object_frame:
            ego_xy = (0.0, 0.0)
        else:
            if self._tf_buffer is None:
                public["reason"] = "TRANSFORM_UNAVAILABLE"
                return public, None
            try:
                stamped = self._tf_buffer.lookup_transform(
                    self._trajectory_frame,
                    object_frame,
                    Time(),
                    timeout=Duration(seconds=0.0),
                )
            except Exception:
                public["reason"] = "TRANSFORM_UNAVAILABLE"
                return public, None
            transform = stamped.transform
            ego_xy = transform_xy(0.0, 0.0, transform)

        ego_projection = project_point_to_polyline(
            ego_xy[0], ego_xy[1], self._trajectory_points
        )
        if ego_projection is None:
            public["reason"] = "EGO_PROJECTION_FAILED"
            return public, None

        public["available"] = True
        public["reason"] = "OK"
        return public, {
            "points": self._trajectory_points,
            "transform": transform,
            "ego_s": ego_projection[0],
        }

    def _add_path_relation(
        self, candidate: dict[str, Any], path_work: dict[str, Any] | None
    ) -> None:
        candidate["in_path_corridor"] = None
        candidate["path_forward_m"] = None
        candidate["path_lateral_m"] = None
        if path_work is None:
            return

        point_xy = (candidate["x_m"], candidate["y_m"])
        if path_work["transform"] is not None:
            point_xy = transform_xy(
                point_xy[0], point_xy[1], path_work["transform"]
            )
        projection = project_point_to_polyline(
            point_xy[0], point_xy[1], path_work["points"]
        )
        if projection is None:
            return

        forward = projection[0] - path_work["ego_s"]
        lateral = projection[1]
        candidate["path_forward_m"] = forward
        candidate["path_lateral_m"] = lateral
        candidate["in_path_corridor"] = (
            self._limits["path_min_forward"]
            <= forward
            <= self._limits["path_max_forward"]
            and abs(lateral) <= self._limits["path_half_width"]
        )

    def _required_hits(self) -> int:
        full_window = self._history.maxlen or 1
        ratio = min(1.0, self._min_hits / full_window)
        return max(1, math.ceil(ratio * len(self._history)))

    @staticmethod
    def _candidate_sort_key(candidate: dict[str, Any]) -> tuple[int, float, float]:
        relation = candidate.get("in_path_corridor")
        path_rank = 0 if relation is True else (1 if relation is None else 2)
        return path_rank, -candidate["geometry_score"], candidate["range_m"]

    def _on_objects(self, msg: DetectedObjects) -> None:
        self._last_input_monotonic = time.monotonic()
        path_public, path_work = self._prepare_path_context(msg.header.frame_id)

        measurements = [
            measurement
            for obj in msg.objects
            if (measurement := self._measurement_from_object(obj)) is not None
        ]
        for measurement in measurements:
            self._add_path_relation(measurement, path_work)
            measurement["strict_geometry_match"] = measurement["geometry_match"]
            measurement["strict_failed_gates"] = list(
                measurement["failed_gates"]
            )
            close_path_match = path_close_range_geometry_match(
                measurement, self._limits
            )
            measurement["path_close_range_match"] = close_path_match
            if measurement["strict_geometry_match"]:
                measurement["geometry_rule"] = "strict"
            elif close_path_match:
                measurement["geometry_match"] = True
                measurement["geometry_rule"] = "path_close_range"
                measurement["failed_gates"] = []
            else:
                measurement["geometry_rule"] = None
            fallback_match = (
                measurement["x_m"] >= self._limits["fallback_min_x"]
                and abs(measurement["y_m"])
                <= self._limits["fallback_max_abs_y"]
            )
            measurement["fallback_forward_roi"] = (
                fallback_match if path_work is None else None
            )
            measurement["detection_match"] = measurement["geometry_match"] and (
                path_work is not None or fallback_match
            )
            if measurement["geometry_match"] and not measurement["detection_match"]:
                measurement["failed_gates"] = ["fallback_forward_roi"]

        candidates = [item for item in measurements if item["detection_match"]]
        candidates.sort(key=self._candidate_sort_key)
        candidate = candidates[0] if candidates else None

        rejected = [item for item in measurements if not item["detection_match"]]
        rejected.sort(
            key=lambda item: (
                len(item["failed_gates"]),
                -item["geometry_score"],
                item["range_m"],
            )
        )
        best_rejected = rejected[0] if rejected else None
        path_rejected = [
            item
            for item in rejected
            if item.get("in_path_corridor") is True
        ]
        path_rejected.sort(
            key=lambda item: (
                len(item["failed_gates"]),
                -item["geometry_score"],
                item["range_m"],
            )
        )
        best_path_rejected = path_rejected[0] if path_rejected else None

        instant_match = candidate is not None
        self._history.append(instant_match)
        hits = sum(self._history)
        enough_samples = len(self._history) >= self._min_samples
        aps_like = enough_samples and hits >= self._required_hits()
        temporal_score = hits / len(self._history) if self._history else 0.0
        confidence = (
            candidate["geometry_score"] * temporal_score
            if aps_like and candidate is not None
            else 0.0
        )

        if not enough_samples:
            state = "WARMING_UP"
        elif not aps_like:
            state = "UNKNOWN"
        elif candidate is None:
            state = "APS_LIKE_TRACKING"
        elif candidate["in_path_corridor"] is True:
            state = "APS_LIKE_IN_PATH"
        elif candidate["in_path_corridor"] is False:
            state = "APS_LIKE_OUTSIDE_PATH"
        else:
            state = "APS_LIKE_PATH_UNKNOWN"

        if not aps_like:
            aps_like_ahead: bool | None = False
        elif candidate is None or candidate["in_path_corridor"] is None:
            aps_like_ahead = None
        else:
            aps_like_ahead = bool(candidate["in_path_corridor"])

        payload = {
            "aps_like": aps_like,
            "aps_like_ahead": aps_like_ahead,
            "state": state,
            "confidence": round(confidence, 4),
            "instant_match": instant_match,
            "matched_frames": hits,
            "window_frames": len(self._history),
            "required_hits": self._required_hits(),
            "candidate": self._rounded_mapping(candidate),
            "best_rejected_candidate": self._rounded_mapping(best_rejected),
            "best_path_rejected_candidate": self._rounded_mapping(
                best_path_rejected
            ),
            "path": path_public,
            "geometry_method": "minimum_area_oriented_box",
            "aps_model_geometry_m": self._rounded_mapping(self._model_geometry),
            "frame_id": msg.header.frame_id,
            "source_stamp": {
                "sec": msg.header.stamp.sec,
                "nanosec": msg.header.stamp.nanosec,
            },
            "meaning": "point-cloud APS-like geometry plus optional path relation; not vehicle identity",
        }
        self._publish(payload)
        if state != self._last_state:
            self.get_logger().info(
                f"state={state} hits={hits}/{len(self._history)} "
                f"instant_match={instant_match} path={path_public['reason']}"
            )
            self._last_state = state

    @staticmethod
    def _rounded_mapping(value: dict[str, Any] | None) -> dict[str, Any] | None:
        if value is None:
            return None
        return {
            key: round(item, 4) if isinstance(item, float) else item
            for key, item in value.items()
        }

    def _publish(self, payload: dict[str, Any]) -> None:
        output = String()
        output.data = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        self._publisher.publish(output)

    def _publish_stale_if_needed(self) -> None:
        if self._last_input_monotonic is None:
            age = None
        else:
            age = time.monotonic() - self._last_input_monotonic
            if age <= 1.0:
                return
        self._publish(
            {
                "aps_like": False,
                "aps_like_ahead": False,
                "state": "INPUT_STALE",
                "confidence": 0.0,
                "input_age_sec": None if age is None else round(age, 3),
                "meaning": "point-cloud APS-like geometry plus optional path relation; not vehicle identity",
            }
        )


def run_self_tests() -> None:
    class Point:
        def __init__(self, x: float, y: float) -> None:
            self.x = x
            self.y = y

    model = aps_model_geometry_from_vehicle_info(
        {
            "/**": {
                "ros__parameters": {
                    "wheel_base": 0.30,
                    "wheel_tread": 0.445,
                    "front_overhang": 0.386,
                    "rear_overhang": 0.492,
                    "left_overhang": 0.113,
                    "right_overhang": 0.113,
                    "vehicle_height": 1.7638,
                }
            }
        }
    )
    assert math.isclose(model["length"], 1.178, abs_tol=1e-9)
    assert math.isclose(model["width"], 0.671, abs_tol=1e-9)
    assert math.isclose(model["height"], 1.7638, abs_tol=1e-9)
    model_limits = aps_model_default_limits(model)

    angle = math.radians(42.0)
    cosine = math.cos(angle)
    sine = math.sin(angle)
    rectangle = []
    for x, y in ((-0.34, -0.33), (0.34, -0.33), (0.34, 0.33), (-0.34, 0.33)):
        rectangle.append(Point(x * cosine - y * sine, x * sine + y * cosine))
    box = minimum_area_box(rectangle)
    assert box is not None
    assert math.isclose(box[0], 0.66, abs_tol=1e-6)
    assert math.isclose(box[1], 0.68, abs_tol=1e-6)

    curved_path = [(0.0, 0.0), (2.0, 0.0), (4.0, 2.0), (4.0, 4.0)]
    ego = project_point_to_polyline(0.0, 0.0, curved_path)
    ahead = project_point_to_polyline(3.0, 1.0, curved_path)
    assert ego is not None and ahead is not None
    assert ahead[0] - ego[0] > 2.0
    assert abs(ahead[1]) < 1e-6
    outside = project_point_to_polyline(1.0, -1.5, curved_path)
    assert outside is not None and abs(outside[1]) > 1.2

    strict_limits = {
        "min_range": 0.5,
        "max_range": 8.0,
        **{
            key: model_limits[key]
            for key in (
                "min_depth",
                "max_depth",
                "max_footprint_aspect",
                "min_width",
                "max_width",
                "min_height",
                "max_height",
                "min_ratio",
                "max_ratio",
            )
        },
    }
    assert all(
        strict_geometry_gate_results(3.0, 0.66, 0.68, 1.55, strict_limits).values()
    )
    assert all(
        strict_geometry_gate_results(
            1.34, 0.3335, 0.6255, 1.5193, strict_limits
        ).values()
    )
    human_confuser_gates = strict_geometry_gate_results(
        3.44, 0.2834, 0.6455, 1.4333, strict_limits
    )
    assert {
        name for name, passed in human_confuser_gates.items() if not passed
    } == {"height", "footprint_aspect_ratio"}
    low_profile_confuser_gates = strict_geometry_gate_results(
        1.36, 0.4441, 0.6075, 1.3654, strict_limits
    )
    assert {
        name for name, passed in low_profile_confuser_gates.items() if not passed
    } == {"height"}

    close_limits = {
        "path_min_forward": 0.5,
        "path_close_max_forward": 2.5,
        **{
            key: model_limits[key]
            for key in (
                "path_close_min_depth",
                "path_close_max_depth",
                "max_width",
                "path_close_max_width",
                "path_close_min_height",
                "path_close_max_height",
                "path_close_min_ratio",
                "min_ratio",
            )
        },
    }
    close_candidate = {
        "in_path_corridor": True,
        "strict_failed_gates": ["width", "height_width_ratio"],
        "path_forward_m": 1.4,
        "oriented_short_side_m": 0.63,
        "oriented_long_side_m": 0.94,
        "height_m": 1.52,
        "height_width_ratio": 1.62,
    }
    assert path_close_range_geometry_match(close_candidate, close_limits)
    for field, value in (
        ("in_path_corridor", False),
        ("path_forward_m", 2.6),
        ("oriented_long_side_m", 1.11),
    ):
        rejected_candidate = dict(close_candidate)
        rejected_candidate[field] = value
        assert not path_close_range_geometry_match(
            rejected_candidate, close_limits
        )
    rejected_candidate = dict(close_candidate)
    rejected_candidate["strict_failed_gates"] = [
        "width",
        "height_width_ratio",
        "height",
    ]
    assert not path_close_range_geometry_match(rejected_candidate, close_limits)
    print(
        "self_test=PASS oriented_box=PASS curved_path_projection=PASS "
        "aps_model_geometry=PASS partial_aps_gate=PASS human_confuser_gate=PASS "
        "low_profile_confuser_gate=PASS "
        "path_close_range_rule=PASS"
    )


def main() -> None:
    if "--self-test" in sys.argv:
        run_self_tests()
        return
    rclpy.init()
    node = ApsLikeDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
