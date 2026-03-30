#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/hmi_env.sh"

export APS_FB_FRONTEND_MODE="${APS_FB_FRONTEND_MODE:-prod}"
export APS_FB_MICROSERVICE_MODE="${APS_FB_MICROSERVICE_MODE:-prod}"
export AUTO_BUILD_FRONTEND="${AUTO_BUILD_FRONTEND:-true}"
export AUTO_BUILD_MICROSERVICE="${AUTO_BUILD_MICROSERVICE:-true}"
export APS_LOCAL_STACK_WAIT_SEC="${APS_LOCAL_STACK_WAIT_SEC:-900}"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=8192}"
export APS_HMI_MODE="${APS_HMI_MODE:-single}"
export APS_HMI_WEBENGINE_GPU="${APS_HMI_WEBENGINE_GPU:-false}"
export APS_HMI_FULLSCREEN="${APS_HMI_FULLSCREEN:-false}"
export APS_HMI_WINDOW_WIDTH="${APS_HMI_WINDOW_WIDTH:-1920}"
export APS_HMI_WINDOW_HEIGHT="${APS_HMI_WINDOW_HEIGHT:-1080}"
export APS_HMI_RVIZ_RATIO="${APS_HMI_RVIZ_RATIO:-30}"
export APS_HMI_WEB_ZOOM_FACTOR="${APS_HMI_WEB_ZOOM_FACTOR:-1.25}"
export APS_HMI_FRONTEND_URL="${APS_HMI_FRONTEND_URL:-http://127.0.0.1:3001/aps/welcome}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

FRONTEND_ROOT="${APS_FRONTEND_BACKEND_ROOT:-$HOME/APS_Frontend_Backend}"

if [[ -x "${FRONTEND_ROOT}/start-all.sh" ]]; then
  exec bash "${SCRIPT_DIR}/start_local_hmi_stack.sh" "$@"
fi

echo "[INFO] missing ${FRONTEND_ROOT}/start-all.sh; falling back to external frontend/backend mode."
echo "[INFO] expected external frontend URL: ${APS_HMI_FRONTEND_URL}"
exec bash "${SCRIPT_DIR}/start_planning_simulator_hmi.sh" "$@"
