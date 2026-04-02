#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/hmi_env.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  start_local_hmi_stack.sh [planning_simulator ros2 launch args...]

Purpose:
  Start the full local vehicle stack together:
  - local vehicle UI on 3001
  - local microservice on 3003
  - Autoware planning_simulator
  - HMI frontend + RViz layout

Defaults:
  - reuses /root/APS_Frontend_Backend/start-all.sh for 3001/3003
  - disables the remote UI SSH tunnel by default
  - points HMI to http://127.0.0.1:3001/aps/welcome
  - uses APS_HMI_MODE=single by default

Environment overrides:
  APS_ROOT_DIR                    Autoware workspace root (default: $HOME/autoware.APS)
  APS_FRONTEND_BACKEND_ROOT       Local APS frontend/backend repo (default: $HOME/APS_Frontend_Backend)
  APS_HMI_TEST_ROOT               Runtime root (default: $HOME/hmi_test)
  APS_LOCAL_STACK_PID_DIR         PID directory (default: $APS_HMI_TEST_ROOT/.pid)
  APS_LOCAL_STACK_LOG_DIR         Log directory (default: $APS_HMI_TEST_ROOT/.log)
  APS_HMI_ROS_DIR                 ROS_HOME directory (default: $APS_HMI_TEST_ROOT/.ros)
  APS_LOCAL_STACK_WAIT_SEC        Max seconds to wait for local UI/microservice readiness (default: 180)
  APS_LOCAL_STACK_PREWARM         true/false, prewarm HMI frontend routes in background (default: true)
  APS_HMI_FRONTEND_URL            Frontend URL passed into HMI (default: http://127.0.0.1:3001/aps/welcome)
  APS_HMI_MODE                    single/compose, forwarded to start_planning_simulator_hmi.sh (default: single)
  APS_HMI_WEBENGINE_GPU           true/false, enable Qt WebEngine GPU path for left HMI pane (default: false)
  APS_HMI_WEB_ZOOM_FACTOR         Qt web view zoom factor for HMI frontend (default: 1.25)
  APS_FB_FRONTEND_MODE            dev/prod, forwarded to start-all.sh (default: dev)
  APS_FB_MICROSERVICE_MODE        dev/prod, forwarded to start-all.sh (default: dev)
  AUTO_START_REMOTE_UI_TUNNEL     Passed to start-all.sh (default: false)
  KEEP_DOCKER_UP                  Forwarded to start-all.sh/clear-all-services.sh if set

Examples:
  bash /root/autoware.APS/scripts/start_local_hmi_stack.sh
  bash /root/autoware.APS/scripts/start_local_hmi_stack.sh scenario_simulation:=true
EOF
  exit 0
fi

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
FRONTEND_ROOT="${APS_FRONTEND_BACKEND_ROOT:-$HOME/APS_Frontend_Backend}"
HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HOME/hmi_test}"
SCRIPT_HINT_DIR="${APS_HMI_SCRIPT_DIR:-$ROOT_DIR/scripts}"
STACK_PID_DIR="${APS_LOCAL_STACK_PID_DIR:-$HMI_TEST_ROOT/.pid}"
STACK_LOG_DIR="${APS_LOCAL_STACK_LOG_DIR:-$HMI_TEST_ROOT/.log}"
ROS_DIR="${APS_HMI_ROS_DIR:-$HMI_TEST_ROOT/.ros}"
STACK_LOG_FILE="${STACK_LOG_DIR}/start_all_local.log"
STACK_PID_FILE="${STACK_PID_DIR}/start_all.pid"
STACK_PGID_FILE="${STACK_PID_DIR}/start_all.pgid"
WAIT_SEC="${APS_LOCAL_STACK_WAIT_SEC:-180}"
PREWARM="${APS_LOCAL_STACK_PREWARM:-true}"
FRONTEND_URL="${APS_HMI_FRONTEND_URL:-http://127.0.0.1:3001/aps/welcome}"
HMI_MODE="${APS_HMI_MODE:-single}"
WEBENGINE_GPU="${APS_HMI_WEBENGINE_GPU:-false}"
WEB_ZOOM_FACTOR="${APS_HMI_WEB_ZOOM_FACTOR:-1.25}"
AUTO_TUNNEL="${AUTO_START_REMOTE_UI_TUNNEL:-false}"
MICROSERVICE_PORT="${APS_LOCAL_MICROSERVICE_PORT:-3003}"
FRONTEND_MODE="${APS_FB_FRONTEND_MODE:-dev}"
MICROSERVICE_MODE="${APS_FB_MICROSERVICE_MODE:-dev}"

mkdir -p "${STACK_PID_DIR}" "${STACK_LOG_DIR}" "${ROS_DIR}" "${ROS_DIR}/log"

process_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

port_listening() {
  local host="$1"
  local port="$2"

  if command -v ss >/dev/null 2>&1; then
    if [[ -n "${host}" && "${host}" != "*" ]]; then
      ss -ltn 2>/dev/null | awk -v target="${host}:${port}" '$1 == "LISTEN" && $4 == target { found = 1 } END { exit(found ? 0 : 1) }'
    else
      ss -ltn 2>/dev/null | awk -v suffix=":${port}" '$1 == "LISTEN" && substr($4, length($4) - length(suffix) + 1) == suffix { found = 1 } END { exit(found ? 0 : 1) }'
    fi
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${port}" -sTCP:LISTEN -n -P >/dev/null 2>&1
    return $?
  fi

  return 1
}

http_ready() {
  local url="$1"
  local code
  code="$(curl -L -s -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
  [[ "${code}" =~ ^2|^3 ]]
}

prewarm_hmi_frontend() {
  local frontend_url="$1"
  local frontend_origin
  frontend_origin="$(python3 - "${frontend_url}" <<'PY'
import sys
from urllib.parse import urlparse
url = urlparse(sys.argv[1])
origin = f"{url.scheme}://{url.hostname or '127.0.0.1'}"
if url.port:
    origin += f":{url.port}"
print(origin)
PY
)"

  (
    curl -L -sS "${frontend_url}" >/dev/null 2>&1 || true
    curl -L -sS "${frontend_origin}/api/home-page/stream" --max-time 5 >/dev/null 2>&1 || true
    curl -L -sS "${frontend_origin}/api/battery/stream" --max-time 5 >/dev/null 2>&1 || true
  ) &
}

frontend_host="$(python3 - "${FRONTEND_URL}" <<'PY'
import sys
from urllib.parse import urlparse
url = urlparse(sys.argv[1])
print(url.hostname or "127.0.0.1")
PY
)"

frontend_port="$(python3 - "${FRONTEND_URL}" <<'PY'
import sys
from urllib.parse import urlparse
url = urlparse(sys.argv[1])
print(url.port or (443 if url.scheme == "https" else 80))
PY
)"

echo "[INFO] cleaning previous local HMI stack..."
bash "${ROOT_DIR}/scripts/stop_local_hmi_stack.sh" >/dev/null 2>&1 || true

if [[ ! -x "${FRONTEND_ROOT}/start-all.sh" ]]; then
  echo "[ERROR] missing start-all.sh at ${FRONTEND_ROOT}/start-all.sh" >&2
  exit 1
fi

start_all_cmd="cd $(printf '%q' "${FRONTEND_ROOT}"); \
export AUTO_START_REMOTE_UI_TUNNEL=$(printf '%q' "${AUTO_TUNNEL}"); \
export APS_FB_RUNTIME_ROOT=$(printf '%q' "${HMI_TEST_ROOT}"); \
export APS_FB_PID_DIR=$(printf '%q' "${STACK_PID_DIR}"); \
export APS_FB_LOG_DIR=$(printf '%q' "${STACK_LOG_DIR}"); \
export APS_FB_ROS_DIR=$(printf '%q' "${ROS_DIR}"); \
if [[ -n \"\${KEEP_DOCKER_UP:-}\" ]]; then export KEEP_DOCKER_UP; fi; \
exec ./start-all.sh"

echo "[INFO] starting local vehicle stack (3001/3003)..."
echo "[INFO] frontend mode: ${FRONTEND_MODE}"
echo "[INFO] microservice mode: ${MICROSERVICE_MODE}"
echo "[INFO] HMI mode: ${HMI_MODE}"
: > "${STACK_LOG_FILE}"
nohup setsid bash -lc "${start_all_cmd}" >>"${STACK_LOG_FILE}" 2>&1 &
stack_pid=$!
echo "${stack_pid}" > "${STACK_PID_FILE}"
stack_pgid="$(ps -o pgid= -p "${stack_pid}" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "${stack_pgid}" ]]; then
  echo "${stack_pgid}" > "${STACK_PGID_FILE}"
fi

echo "[INFO] waiting for frontend ${FRONTEND_URL} and microservice :${MICROSERVICE_PORT}..."
for _ in $(seq 1 "${WAIT_SEC}"); do
  if ! process_alive "${stack_pid}"; then
    echo "[ERROR] local vehicle stack controller exited early. Last log lines:" >&2
    tail -n 80 "${STACK_LOG_FILE}" >&2 || true
    rm -f "${STACK_PID_FILE}" "${STACK_PGID_FILE}"
    exit 1
  fi

  if http_ready "${FRONTEND_URL}" && port_listening "*" "${MICROSERVICE_PORT}"; then
    ready="true"
    break
  fi

  ready="false"
  sleep 1
done

if [[ "${ready:-false}" != "true" ]]; then
  echo "[ERROR] timed out waiting for local vehicle UI/microservice." >&2
  tail -n 80 "${STACK_LOG_FILE}" >&2 || true
  bash "${ROOT_DIR}/scripts/stop_local_hmi_stack.sh" >/dev/null 2>&1 || true
  exit 1
fi

echo "[INFO] local vehicle stack ready."
if [[ "${PREWARM}" == "true" ]]; then
  echo "[INFO] prewarming HMI frontend routes in background..."
  prewarm_hmi_frontend "${FRONTEND_URL}"
fi
if ! APS_HMI_TEST_ROOT="${HMI_TEST_ROOT}" \
  APS_HMI_PID_DIR="${STACK_PID_DIR}" \
  APS_HMI_LOG_DIR="${STACK_LOG_DIR}" \
  APS_HMI_ROS_DIR="${ROS_DIR}" \
  APS_HMI_FRONTEND_URL="${FRONTEND_URL}" \
  APS_HMI_MODE="${HMI_MODE}" \
  APS_HMI_WEBENGINE_GPU="${WEBENGINE_GPU}" \
  APS_HMI_WEB_ZOOM_FACTOR="${WEB_ZOOM_FACTOR}" \
  APS_HMI_SKIP_UI_CHECK="true" \
  bash "${ROOT_DIR}/scripts/start_planning_simulator_hmi.sh" "$@"; then
  echo "[ERROR] failed to start planning_simulator + HMI. Cleaning up..." >&2
  bash "${ROOT_DIR}/scripts/stop_local_hmi_stack.sh" >/dev/null 2>&1 || true
  exit 1
fi

echo "[INFO] started full local HMI stack:"
echo "  frontend: ${FRONTEND_URL}"
echo "  microservice: http://127.0.0.1:${MICROSERVICE_PORT}"
echo "  pid dir: ${STACK_PID_DIR}"
echo "  start-all log: ${STACK_LOG_FILE}"
echo "  ros dir: ${ROS_DIR}"
echo "  stop command: bash ${SCRIPT_HINT_DIR}/stop_local_hmi_stack.sh"
