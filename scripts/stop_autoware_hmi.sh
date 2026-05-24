#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/hmi_env.sh"

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HOME/hmi_test}"
PID_DIR="${APS_HMI_PID_DIR:-$HMI_TEST_ROOT/.pid}"
AUTOWARE_PID_FILE="${PID_DIR}/autoware_launch.pid"
AUTOWARE_PGID_FILE="${PID_DIR}/autoware_launch.pgid"
HMI_PID_FILE="${PID_DIR}/hmi_container.pid"
HMI_PGID_FILE="${PID_DIR}/hmi_container.pgid"
RVIZ_PRESTART_PID_FILE="${PID_DIR}/rviz_user_prestart.pid"
RVIZ_PRESTART_PGID_FILE="${PID_DIR}/rviz_user_prestart.pgid"

process_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

wait_for_exit() {
  local target="$1"
  local is_group="${2:-false}"
  local attempts="${3:-8}"

  for _ in $(seq 1 "${attempts}"); do
    if [[ "${is_group}" == "true" ]]; then
      if ! kill -0 "-${target}" >/dev/null 2>&1; then
        return 0
      fi
    else
      if ! kill -0 "${target}" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

stop_target() {
  local pid="${1:-}"
  local pgid="${2:-}"
  local label="$3"
  local stopped="false"

  if [[ -n "${pgid}" ]] && kill -0 "-${pgid}" >/dev/null 2>&1; then
    echo "[INFO] stopping ${label} process group (${pgid})"
    kill -TERM "-${pgid}" >/dev/null 2>&1 || true
    if ! wait_for_exit "${pgid}" true 5; then
      echo "[WARN] force killing ${label} process group (${pgid})"
      kill -KILL "-${pgid}" >/dev/null 2>&1 || true
      wait_for_exit "${pgid}" true 3 || true
    fi
    stopped="true"
  fi

  if [[ -n "${pid}" ]] && process_alive "${pid}"; then
    if [[ "${stopped}" != "true" ]]; then
      echo "[INFO] stopping ${label} (pid ${pid})"
    fi
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    if ! wait_for_exit "${pid}" false 3; then
      echo "[WARN] force killing ${label} (pid ${pid})"
      kill -KILL "${pid}" >/dev/null 2>&1 || true
      wait_for_exit "${pid}" false 2 || true
    fi
  fi
}

stop_pid_file() {
  local pid_file="$1"
  local pgid_file="$2"
  local label="$3"

  if [[ ! -f "${pid_file}" ]]; then
    return 0
  fi

  local pid
  pid="$(cat "${pid_file}")"
  local pgid=""
  if [[ -f "${pgid_file}" ]]; then
    pgid="$(cat "${pgid_file}")"
  elif [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
  fi

  stop_target "${pid}" "${pgid}" "${label}"

  rm -f "${pid_file}" "${pgid_file}"
}

stop_pattern_group() {
  local pattern="$1"
  local label="$2"
  local pid=""
  while IFS= read -r pid; do
    [[ -z "${pid}" ]] && continue
    local pgid=""
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
    stop_target "${pid}" "${pgid}" "${label}"
  done < <(pgrep -f "${pattern}" 2>/dev/null || true)
}

close_hmi_windows() {
  if command -v xdotool >/dev/null 2>&1; then
    xdotool search --name 'APS HMI Container' 2>/dev/null | xargs -r -n1 xdotool windowclose >/dev/null 2>&1 || true
    xdotool search --name 'APS HMI Container :: frontend' 2>/dev/null | xargs -r -n1 xdotool windowclose >/dev/null 2>&1 || true
    xdotool search --name 'APS HMI Container :: rviz' 2>/dev/null | xargs -r -n1 xdotool windowclose >/dev/null 2>&1 || true
    xdotool search --name 'RViz User' 2>/dev/null | xargs -r -n1 xdotool windowclose >/dev/null 2>&1 || true
  fi
}

bash "${ROOT_DIR}/scripts/stop_hmi_preview.sh" >/dev/null 2>&1 || true
stop_pid_file "${AUTOWARE_PID_FILE}" "${AUTOWARE_PGID_FILE}" "autoware.launch"
stop_pid_file "${HMI_PID_FILE}" "${HMI_PGID_FILE}" "HMI container"
stop_pid_file "${RVIZ_PRESTART_PID_FILE}" "${RVIZ_PRESTART_PGID_FILE}" "HMI prestarted rviz"
stop_pattern_group 'build/aps_hmi_container/aps_hmi_container .*--frontend-only true' 'HMI frontend'
stop_pattern_group 'build/aps_hmi_container/aps_hmi_container .*--rviz-only true' 'HMI rviz'
stop_pattern_group 'build/aps_hmi_container/aps_hmi_container' 'HMI child process'
stop_pattern_group 'aps_hmi_container/lib/aps_hmi_container/aps_hmi_container' 'HMI container'
stop_pattern_group '/opt/ros/.*/bin/ros2 launch autoware_launch autoware.launch.xml' 'autoware.launch launcher'
stop_pattern_group 'ros2 launch autoware_launch autoware.launch.xml' 'autoware.launch launcher'
close_hmi_windows
