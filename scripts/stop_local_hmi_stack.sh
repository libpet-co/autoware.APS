#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/hmi_env.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  stop_local_hmi_stack.sh

Purpose:
  Stop the full local vehicle + Autoware + HMI stack started by
  start_local_hmi_stack.sh.
EOF
  exit 0
fi

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
FRONTEND_ROOT="${APS_FRONTEND_BACKEND_ROOT:-$HOME/APS_Frontend_Backend}"
HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HOME/hmi_test}"
STACK_PID_DIR="${APS_LOCAL_STACK_PID_DIR:-$HMI_TEST_ROOT/.pid}"
STACK_LOG_DIR="${APS_LOCAL_STACK_LOG_DIR:-$HMI_TEST_ROOT/.log}"
ROS_DIR="${APS_HMI_ROS_DIR:-$HMI_TEST_ROOT/.ros}"
STACK_PID_FILE="${STACK_PID_DIR}/start_all.pid"
STACK_PGID_FILE="${STACK_PID_DIR}/start_all.pgid"

process_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

wait_for_exit() {
  local pid="$1"
  local attempts="${2:-25}"
  for _ in $(seq 1 "${attempts}"); do
    if ! process_alive "${pid}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

port_listening() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${port}" -sTCP:LISTEN -n -P >/dev/null 2>&1
    return $?
  fi
  ss -ltn 2>/dev/null | awk -v suffix=":${port}" '$1 == "LISTEN" && substr($4, length($4) - length(suffix) + 1) == suffix { found = 1 } END { exit(found ? 0 : 1) }'
}

force_kill_port() {
  local port="$1"
  if [[ -x "${FRONTEND_ROOT}/kill-ports.sh" ]]; then
    (
      cd "${FRONTEND_ROOT}"
      bash ./kill-ports.sh "${port}" >/dev/null 2>&1 || true
    )
  fi
}

stop_matching_start_all() {
  local pid
  while IFS= read -r pid; do
    [[ -z "${pid}" ]] && continue
    local cwd
    cwd="$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)"
    if [[ "${cwd}" != "${FRONTEND_ROOT}"* ]]; then
      continue
    fi

    local pgid=""
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
    echo "[INFO] stopping fallback start-all controller (pid ${pid})"
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    sleep 1
    if process_alive "${pid}"; then
      if [[ -n "${pgid}" ]] && kill -0 "-${pgid}" >/dev/null 2>&1; then
        kill -TERM "-${pgid}" >/dev/null 2>&1 || true
        sleep 1
        kill -KILL "-${pgid}" >/dev/null 2>&1 || true
      fi
      kill -KILL "${pid}" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -f 'bash ./start-all.sh' 2>/dev/null || true)
}

stop_controller() {
  local pid_file="$1"
  local pgid_file="$2"
  local label="$3"

  if [[ ! -f "${pid_file}" ]]; then
    return 0
  fi

  local pid
  local pgid=""
  pid="$(cat "${pid_file}")"
  if [[ -f "${pgid_file}" ]]; then
    pgid="$(cat "${pgid_file}")"
  elif process_alive "${pid}"; then
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
  fi

  if process_alive "${pid}"; then
    echo "[INFO] stopping ${label} controller (pid ${pid})"
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    if ! wait_for_exit "${pid}" 30; then
      if [[ -n "${pgid}" ]] && kill -0 "-${pgid}" >/dev/null 2>&1; then
        echo "[WARN] force killing ${label} controller process group (${pgid})"
        kill -TERM "-${pgid}" >/dev/null 2>&1 || true
        sleep 2
        kill -KILL "-${pgid}" >/dev/null 2>&1 || true
      fi
      if process_alive "${pid}"; then
        echo "[WARN] force killing ${label} controller (pid ${pid})"
        kill -KILL "${pid}" >/dev/null 2>&1 || true
      fi
    fi
  fi

  rm -f "${pid_file}" "${pgid_file}"
}

echo "[INFO] stopping planning_simulator + HMI..."
APS_HMI_TEST_ROOT="${HMI_TEST_ROOT}" \
APS_HMI_PID_DIR="${STACK_PID_DIR}" \
APS_HMI_LOG_DIR="${STACK_LOG_DIR}" \
APS_HMI_ROS_DIR="${ROS_DIR}" \
bash "${ROOT_DIR}/scripts/stop_planning_simulator_hmi.sh" >/dev/null 2>&1 || true

stop_controller "${STACK_PID_FILE}" "${STACK_PGID_FILE}" "local vehicle stack"

if [[ -x "${FRONTEND_ROOT}/clear-all-services.sh" ]]; then
  echo "[INFO] clearing local APS frontend/backend services..."
  (
    cd "${FRONTEND_ROOT}"
    export APS_FB_RUNTIME_ROOT="${HMI_TEST_ROOT}"
    export APS_FB_PID_DIR="${STACK_PID_DIR}"
    export APS_FB_LOG_DIR="${STACK_LOG_DIR}"
    export APS_FB_ROS_DIR="${ROS_DIR}"
    if [[ -n "${KEEP_DOCKER_UP:-}" ]]; then
      export KEEP_DOCKER_UP
    fi
    bash ./clear-all-services.sh >/dev/null 2>&1 || true
  )
fi

stop_matching_start_all

for port in 3001 3003; do
  for _ in $(seq 1 10); do
    if ! port_listening "${port}"; then
      break
    fi
    sleep 1
  done
  if port_listening "${port}"; then
    echo "[WARN] port ${port} still listening after initial stop; forcing cleanup"
    force_kill_port "${port}"
  fi
  for _ in $(seq 1 5); do
    if ! port_listening "${port}"; then
      break
    fi
    sleep 1
  done
  if port_listening "${port}"; then
    echo "[WARN] port ${port} is still listening after forced cleanup"
  fi
done

echo "[INFO] local HMI stack stopped."
