#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HOME/hmi_test}"
LOG_DIR="${APS_HMI_LOG_DIR:-$HMI_TEST_ROOT/.log}"
ROS_DIR="${APS_HMI_ROS_DIR:-$HMI_TEST_ROOT/.ros}"
SETUP_ENV_CACHE="${APS_HMI_SETUP_ENV_CACHE:-$HMI_TEST_ROOT/.cache/autoware_setup_env.bash}"
USE_SETUP_ENV_CACHE="$(printf '%s' "${APS_HMI_USE_SETUP_ENV_CACHE:-true}" | tr '[:upper:]' '[:lower:]')"
CYCLONEDDS_CONFIG="${APS_CYCLONEDDS_CONFIG:-$HOME/cyclonedds.xml}"
ENSURE_DELAY_SEC="${APS_MAP_PRELAUNCH_ENSURE_DELAY_SEC:-60}"

AUTOWARE_USE_SIM_TIME="${APS_AUTOWARE_USE_SIM_TIME:-false}"
AUTOWARE_MAP_PATH="${APS_AUTOWARE_MAP_PATH:-}"
AUTOWARE_VEHICLE_MODEL="${APS_AUTOWARE_VEHICLE_MODEL:-aps_vehicle}"
AUTOWARE_SENSOR_MODEL="${APS_AUTOWARE_SENSOR_MODEL:-aps_sensor_kit}"
AUTOWARE_SENSOR_CONFIG_PROFILE="${APS_AUTOWARE_SENSOR_CONFIG_PROFILE:-aps998}"
AUTOWARE_LANELET2_MAP_FILE="${APS_AUTOWARE_LANELET2_MAP_FILE:-frontway2.osm}"
AUTOWARE_POINTCLOUD_MAP_FILE="${APS_AUTOWARE_POINTCLOUD_MAP_FILE:-front.pcd}"

mkdir -p "${LOG_DIR}" "${ROS_DIR}" "${ROS_DIR}/log"

if [[ ! -f "${ROOT_DIR}/install/setup.bash" ]]; then
  echo "[ERROR] missing main workspace setup: ${ROOT_DIR}/install/setup.bash" >&2
  exit 1
fi

set +u
source /opt/ros/humble/setup.bash
if [[ "${USE_SETUP_ENV_CACHE}" == "true" && -r "${SETUP_ENV_CACHE}" ]]; then
  source "${SETUP_ENV_CACHE}"
  setup_desc="cached env (${SETUP_ENV_CACHE})"
else
  source "${ROOT_DIR}/install/setup.bash"
  setup_desc="full setup (${ROOT_DIR}/install/setup.bash)"
fi
set -u

export ROS_HOME="${ROS_DIR}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
if [[ -z "${CYCLONEDDS_URI:-}" && -f "${CYCLONEDDS_CONFIG}" ]]; then
  export CYCLONEDDS_URI="file://${CYCLONEDDS_CONFIG}"
fi

autoware_launch_share="$(ros2 pkg prefix autoware_launch)/share/autoware_launch"
if [[ -z "${AUTOWARE_MAP_PATH}" ]]; then
  AUTOWARE_MAP_PATH="${autoware_launch_share}/autoware_maps/test_map"
fi

pointcloud_map_path="${AUTOWARE_MAP_PATH}/${AUTOWARE_POINTCLOUD_MAP_FILE}"
pointcloud_metadata_path="${AUTOWARE_MAP_PATH}/pointcloud_map_metadata.yaml"
lanelet2_map_path="${AUTOWARE_MAP_PATH}/${AUTOWARE_LANELET2_MAP_FILE}"
map_projector_info_path="${AUTOWARE_MAP_PATH}/map_projector_info.yaml"
ensure_script="${autoware_launch_share}/scripts/ensure_map_components.py"

echo "[INFO] APS map prelaunch starting"
echo "[INFO] ROS setup env: ${setup_desc}"
echo "[INFO] ROS_HOME: ${ROS_HOME}"
echo "[INFO] vehicle_model: ${AUTOWARE_VEHICLE_MODEL}"
echo "[INFO] sensor_model: ${AUTOWARE_SENSOR_MODEL}"
echo "[INFO] sensor_config_profile: ${AUTOWARE_SENSOR_CONFIG_PROFILE}"
echo "[INFO] map_path: ${AUTOWARE_MAP_PATH}"
echo "[INFO] lanelet2_map_file: ${AUTOWARE_LANELET2_MAP_FILE}"
echo "[INFO] pointcloud_map_file: ${AUTOWARE_POINTCLOUD_MAP_FILE}"
echo "[INFO] ensure delay sec: ${ENSURE_DELAY_SEC}"

for required in "${pointcloud_map_path}" "${lanelet2_map_path}"; do
  if [[ ! -e "${required}" ]]; then
    echo "[ERROR] missing map input: ${required}" >&2
    exit 1
  fi
done

map_pid=""
ensure_pid=""
cleanup() {
  trap - TERM INT EXIT
  if [[ -n "${ensure_pid}" ]] && kill -0 "${ensure_pid}" >/dev/null 2>&1; then
    kill "${ensure_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${map_pid}" ]] && kill -0 "${map_pid}" >/dev/null 2>&1; then
    kill "${map_pid}" >/dev/null 2>&1 || true
    wait "${map_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup TERM INT EXIT

ros2 launch tier4_map_launch map.launch.xml \
  "pointcloud_map_path:=${pointcloud_map_path}" \
  "pointcloud_map_metadata_path:=${pointcloud_metadata_path}" \
  "lanelet2_map_path:=${lanelet2_map_path}" \
  "map_projector_info_path:=${map_projector_info_path}" \
  "pointcloud_map_loader_param_path:=${autoware_launch_share}/config/map/pointcloud_map_loader.param.yaml" \
  "lanelet2_map_loader_param_path:=${autoware_launch_share}/config/map/lanelet2_map_loader.param.yaml" \
  "map_tf_generator_param_path:=${autoware_launch_share}/config/map/map_tf_generator.param.yaml" \
  "map_projection_loader_param_path:=${autoware_launch_share}/config/map/map_projection_loader.param.yaml" \
  "use_multithread:=true" &
map_pid=$!

sleep 1
if ! kill -0 "${map_pid}" >/dev/null 2>&1; then
  echo "[ERROR] map prelaunch exited during startup" >&2
  wait "${map_pid}"
fi

if [[ -x "${ensure_script}" ]]; then
  if [[ "${ENSURE_DELAY_SEC}" =~ ^[0-9]+$ && "${ENSURE_DELAY_SEC}" -gt 0 ]]; then
    sleep "${ENSURE_DELAY_SEC}"
  fi
  "${ensure_script}" "${pointcloud_map_path}" "${pointcloud_metadata_path}" "${lanelet2_map_path}" &
  ensure_pid=$!
else
  echo "[WARN] map ensure script not executable: ${ensure_script}" >&2
fi

wait "${map_pid}"
