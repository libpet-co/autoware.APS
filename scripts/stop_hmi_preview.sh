#!/usr/bin/env bash
set -euo pipefail

OVERLAY_WS="${APS_HMI_OVERLAY_WS:-$HOME/autoware.APS_hmi_overlay_ws}"
LAUNCH_PID_FILE="${OVERLAY_WS}/log/hmi_launch.pid"
UI_PID_FILE="${OVERLAY_WS}/log/hmi_ui_preview.pid"

process_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

wait_for_exit() {
  local target="$1"
  local is_group="${2:-false}"
  local attempts="${3:-6}"

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

stop_pid_file() {
  local pid_file="$1"
  local label="$2"
  if [[ ! -f "${pid_file}" ]]; then
    return
  fi

  local pid
  pid="$(cat "${pid_file}")"
  local pgid=""
  if [[ -n "${pid}" ]] && process_alive "${pid}"; then
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
  fi

  if [[ -n "${pgid}" ]] && kill -0 "-${pgid}" >/dev/null 2>&1; then
    echo "[INFO] stopping ${label} process group (${pgid})"
    kill -TERM "-${pgid}" >/dev/null 2>&1 || true
    if ! wait_for_exit "${pgid}" true 4; then
      echo "[WARN] force killing ${label} process group (${pgid})"
      kill -KILL "-${pgid}" >/dev/null 2>&1 || true
      wait_for_exit "${pgid}" true 2 || true
    fi
  fi

  if [[ -n "${pid}" ]] && process_alive "${pid}"; then
    echo "[INFO] stopping ${label} (pid ${pid})"
    kill -TERM "${pid}" >/dev/null 2>&1 || true
    if ! wait_for_exit "${pid}" false 2; then
      echo "[WARN] force killing ${label} (pid ${pid})"
      kill -KILL "${pid}" >/dev/null 2>&1 || true
      wait_for_exit "${pid}" false 2 || true
    fi
  fi
  rm -f "${pid_file}"
}

stop_pid_file "${LAUNCH_PID_FILE}" "HMI launch"
stop_pid_file "${UI_PID_FILE}" "HMI UI preview"

if command -v pgrep >/dev/null 2>&1; then
  while IFS= read -r pid; do
    [[ -z "${pid}" ]] && continue
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
    if [[ -n "${pgid}" ]] && kill -0 "-${pgid}" >/dev/null 2>&1; then
      echo "[INFO] stopping fallback HMI launch process group (${pgid})"
      kill -TERM "-${pgid}" >/dev/null 2>&1 || true
      sleep 1
      kill -KILL "-${pgid}" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -f '/opt/ros/.*/bin/ros2 launch autoware_launch autoware.launch.xml' 2>/dev/null || true)
fi

if command -v xdotool >/dev/null 2>&1; then
  xdotool search --name 'APS HMI Container' 2>/dev/null | xargs -r -n1 xdotool windowclose >/dev/null 2>&1 || true
fi
