#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/hmi_env.sh"
UI_HOST="${APS_UI_HOST:-127.0.0.1}"
UI_PORT="${APS_UI_PORT:-3000}"
FRONTEND_URL="${HMI_FRONTEND_URL:-http://${UI_HOST}:${UI_PORT}/aps/welcome}"
RVIZ_RATIO="${HMI_RVIZ_RATIO:-60}"
FULLSCREEN="${HMI_FULLSCREEN:-true}"
WINDOW_TITLE="${HMI_WINDOW_TITLE:-APS HMI Container}"
AUTO_START_UI="${APS_HMI_AUTO_START_UI:-true}"
CYCLONEDDS_CONFIG="${APS_CYCLONEDDS_CONFIG:-$HOME/cyclonedds.xml}"
UI_LOG="${APS_HMI_LOG_DIR}/hmi_ui_preview.log"
UI_PID_FILE="${APS_HMI_PID_DIR}/hmi_ui_preview.pid"
LAUNCH_PID_FILE="${APS_HMI_PID_DIR}/hmi_launch.pid"

if [[ ! -f "${ROOT_DIR}/install/setup.bash" ]]; then
  echo "[ERROR] missing main workspace setup: ${ROOT_DIR}/install/setup.bash" >&2
  exit 1
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
source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
if [[ -z "${CYCLONEDDS_URI:-}" && -f "${CYCLONEDDS_CONFIG}" ]]; then
  export CYCLONEDDS_URI="file://${CYCLONEDDS_CONFIG}"
fi

echo "[INFO] frontend: ${FRONTEND_URL}"
echo "[INFO] main workspace: ${ROOT_DIR}"
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
