#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
OVERLAY_WS="${APS_HMI_OVERLAY_WS:-$HOME/autoware.APS_hmi_overlay_ws}"
UI_HOST="${APS_UI_HOST:-127.0.0.1}"
UI_PORT="${APS_UI_PORT:-3000}"
FRONTEND_URL="${HMI_FRONTEND_URL:-http://${UI_HOST}:${UI_PORT}/aps/welcome}"
RVIZ_RATIO="${HMI_RVIZ_RATIO:-60}"
FULLSCREEN="${HMI_FULLSCREEN:-true}"
WINDOW_TITLE="${HMI_WINDOW_TITLE:-APS HMI Container}"
AUTO_START_UI="${APS_HMI_AUTO_START_UI:-true}"
CYCLONEDDS_CONFIG="${APS_CYCLONEDDS_CONFIG:-$HOME/cyclonedds.xml}"
UI_LOG="${OVERLAY_WS}/log/hmi_ui_preview.log"
UI_PID_FILE="${OVERLAY_WS}/log/hmi_ui_preview.pid"
LAUNCH_PID_FILE="${OVERLAY_WS}/log/hmi_launch.pid"

mkdir -p "${OVERLAY_WS}/log"

if [[ ! -f "${OVERLAY_WS}/install/setup.bash" ]]; then
  "${ROOT_DIR}/scripts/build_hmi_launch_overlay.sh"
fi

if [[ "${AUTO_START_UI}" == "true" ]]; then
  if ! curl -fsS --max-time 3 "${FRONTEND_URL}" >/dev/null 2>&1; then
    echo "[INFO] starting frontend preview on ${FRONTEND_URL}"
    nohup "${ROOT_DIR}/scripts/start_hmi_ui_preview.sh" >"${UI_LOG}" 2>&1 &
    echo $! > "${UI_PID_FILE}"
    for _ in $(seq 1 30); do
      if curl -fsS --max-time 3 "${FRONTEND_URL}" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  fi
fi

set +u
source "${OVERLAY_WS}/install/setup.bash"
set -u

export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
if [[ -z "${CYCLONEDDS_URI:-}" && -f "${CYCLONEDDS_CONFIG}" ]]; then
  export CYCLONEDDS_URI="file://${CYCLONEDDS_CONFIG}"
fi

echo "[INFO] frontend: ${FRONTEND_URL}"
echo "[INFO] overlay: ${OVERLAY_WS}"
echo "[INFO] middleware: RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}"
if [[ -n "${CYCLONEDDS_URI:-}" ]]; then
  echo "[INFO] middleware: CYCLONEDDS_URI=${CYCLONEDDS_URI}"
fi

echo $$ > "${LAUNCH_PID_FILE}"

exec ros2 launch autoware_launch autoware.launch.xml \
  hmi_single_container:=true \
  hmi_single_fullscreen:="${FULLSCREEN}" \
  hmi_single_window_title:="${WINDOW_TITLE}" \
  hmi_compose_layout:=false \
  rviz_fullscreen:=false \
  hmi_frontend_url:="${FRONTEND_URL}" \
  hmi_rviz_ratio:="${RVIZ_RATIO}" \
  "$@"
