#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${HOME}/hmi_test/.log"
LOG_FILE="${LOG_DIR}/startup_application.log"

mkdir -p "${LOG_DIR}"

{
  echo "==== $(date '+%F %T') start_local_hmi_stack_fast_autostart.sh begin ===="
  echo "USER=${USER:-}"
  echo "DISPLAY=${DISPLAY:-}"
  echo "XAUTHORITY=${XAUTHORITY:-}"
  echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}"
  systemctl --user daemon-reload
  systemctl --user start aps-local-hmi-stack.service
  systemctl --user is-active aps-local-hmi-stack.service || true
  echo "==== $(date '+%F %T') start_local_hmi_stack_fast_autostart.sh end ===="
} >>"${LOG_FILE}" 2>&1
