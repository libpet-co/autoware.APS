#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/hmi_env.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  start_planning_simulator_hmi.sh [planning_simulator ros2 launch args...]

Purpose:
  Start Autoware planning_simulator and the HMI container together.

Defaults:
  Frontend URL: http://127.0.0.1:3001/aps/welcome
  planning_simulator extra arg: rviz:=false
  HMI mode: single

Environment overrides:
  APS_ROOT_DIR                  Autoware workspace root (default: $HOME/autoware.APS)
  APS_HMI_TEST_ROOT             Runtime root (default: $HOME/hmi_test)
  APS_HMI_PID_DIR               PID directory (default: $APS_HMI_TEST_ROOT/.pid)
  APS_HMI_LOG_DIR               Log directory (default: $APS_HMI_TEST_ROOT/.log)
  APS_HMI_ROS_DIR               ROS_HOME directory (default: $APS_HMI_TEST_ROOT/.ros)
  APS_HMI_FRONTEND_URL          Local vehicle UI URL (default: http://127.0.0.1:3001/aps/welcome)
  APS_HMI_FULLSCREEN            true/false, forwarded to HMI container (default: true)
  APS_HMI_WINDOW_WIDTH          Single-container window width when not fullscreen (default: unset)
  APS_HMI_WINDOW_HEIGHT         Single-container window height when not fullscreen (default: unset)
  APS_HMI_WINDOW_X              Single-container window X when not fullscreen (default: unset)
  APS_HMI_WINDOW_Y              Single-container window Y when not fullscreen (default: unset)
  APS_HMI_RVIZ_RATIO            RViz width ratio inside HMI container (default: 60)
  APS_HMI_WINDOW_TITLE          HMI window title (default: APS HMI Container)
  APS_HMI_FRONTEND_WINDOW_TITLE Frontend-only window title in compose mode (default: APS HMI Frontend)
  APS_HMI_MODE                  single/compose (default: single)
  APS_HMI_RVIZ_CONFIG_NAME      RViz config filename under autoware_launch/rviz (default: autoware_minimal_fullscreen.rviz)
  APS_HMI_TARGET_MONITOR        xrandr monitor name or "primary" (default: primary)
  APS_HMI_LAYOUT_DIRECTION      frontend_left/frontend_right (default: frontend_left)
  APS_HMI_WEBENGINE_GPU         true/false, enable Qt WebEngine GPU path for left HMI pane (default: false)
  APS_HMI_WEB_ZOOM_FACTOR       Qt web view zoom factor for HMI frontend (default: 1.25)
  APS_HMI_WEBENGINE_CACHE_DIR   Cache dir for Qt WebEngine assets (default: $APS_HMI_TEST_ROOT/.cache/webengine)
  APS_HMI_WAIT_UI_SEC           Max seconds waiting for local UI port (default: 60)
  APS_HMI_WAIT_AUTOWARE_SEC     Extra seconds to wait before starting HMI after Autoware sanity check (default: 0)
  APS_HMI_USE_SIM_TIME          true/false override for HMI RViz use_sim_time
  APS_HMI_SKIP_UI_CHECK         true/false skip local UI port check (default: false)
  APS_HMI_IMPORT_SHELL_ROS_ENV  true/false import ROS domain/RMW/CycloneDDS from ~/.bashrc when current shell does not set them (default: true)
  APS_ROS_DOMAIN_ID             Optional ROS_DOMAIN_ID for both processes; if unset, rely on ROS default 0
  APS_CYCLONEDDS_CONFIG         CycloneDDS XML path (default: $HOME/cyclonedds.xml)

Examples:
  bash /root/autoware.APS/scripts/start_planning_simulator_hmi.sh
  bash /root/autoware.APS/scripts/start_planning_simulator_hmi.sh scenario_simulation:=true
EOF
  exit 0
fi

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
OVERLAY_WS="${APS_HMI_OVERLAY_WS:-$HOME/autoware.APS_hmi_overlay_ws}"
HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HOME/hmi_test}"
SCRIPT_HINT_DIR="${APS_HMI_SCRIPT_DIR:-$ROOT_DIR/scripts}"
FRONTEND_URL="${APS_HMI_FRONTEND_URL:-http://127.0.0.1:3001/aps/welcome}"
PID_DIR="${APS_HMI_PID_DIR:-$HMI_TEST_ROOT/.pid}"
LOG_DIR="${APS_HMI_LOG_DIR:-$HMI_TEST_ROOT/.log}"
ROS_DIR="${APS_HMI_ROS_DIR:-$HMI_TEST_ROOT/.ros}"
WEBENGINE_CACHE_DIR="${APS_HMI_WEBENGINE_CACHE_DIR:-$HMI_TEST_ROOT/.cache/webengine}"
AUTOWARE_LOG_FILE="${LOG_DIR}/planning_simulator.log"
AUTOWARE_PID_FILE="${PID_DIR}/planning_simulator.pid"
AUTOWARE_PGID_FILE="${PID_DIR}/planning_simulator.pgid"
HMI_LOG_FILE="${LOG_DIR}/hmi_container.log"
HMI_PID_FILE="${PID_DIR}/hmi_container.pid"
HMI_PGID_FILE="${PID_DIR}/hmi_container.pgid"
FRONTEND_LOG_FILE="${LOG_DIR}/hmi_frontend.log"
FRONTEND_PID_FILE="${PID_DIR}/hmi_frontend.pid"
FRONTEND_PGID_FILE="${PID_DIR}/hmi_frontend.pgid"
RVIZ_LOG_FILE="${LOG_DIR}/rviz_user.log"
RVIZ_PID_FILE="${PID_DIR}/rviz_user.pid"
RVIZ_PGID_FILE="${PID_DIR}/rviz_user.pgid"
LAYOUT_LOG_FILE="${LOG_DIR}/hmi_layout.log"
LAYOUT_PID_FILE="${PID_DIR}/hmi_layout.pid"
LAYOUT_PGID_FILE="${PID_DIR}/hmi_layout.pgid"
WAIT_UI_SEC="${APS_HMI_WAIT_UI_SEC:-60}"
WAIT_AUTOWARE_SEC="${APS_HMI_WAIT_AUTOWARE_SEC:-0}"
FULLSCREEN="${APS_HMI_FULLSCREEN:-true}"
WINDOW_WIDTH="${APS_HMI_WINDOW_WIDTH:-}"
WINDOW_HEIGHT="${APS_HMI_WINDOW_HEIGHT:-}"
WINDOW_X="${APS_HMI_WINDOW_X:-}"
WINDOW_Y="${APS_HMI_WINDOW_Y:-}"
RVIZ_RATIO="${APS_HMI_RVIZ_RATIO:-60}"
WINDOW_TITLE="${APS_HMI_WINDOW_TITLE:-APS HMI Container}"
FRONTEND_WINDOW_TITLE="${APS_HMI_FRONTEND_WINDOW_TITLE:-APS HMI Frontend}"
HMI_MODE="$(printf '%s' "${APS_HMI_MODE:-single}" | tr '[:upper:]' '[:lower:]')"
RVIZ_CONFIG_NAME="${APS_HMI_RVIZ_CONFIG_NAME:-autoware_minimal_fullscreen.rviz}"
TARGET_MONITOR="${APS_HMI_TARGET_MONITOR:-primary}"
LAYOUT_DIRECTION="${APS_HMI_LAYOUT_DIRECTION:-frontend_left}"
WEBENGINE_GPU="${APS_HMI_WEBENGINE_GPU:-false}"
WEB_ZOOM_FACTOR="${APS_HMI_WEB_ZOOM_FACTOR:-1.25}"
ROS_DOMAIN_ID_VALUE="${APS_ROS_DOMAIN_ID:-${ROS_DOMAIN_ID:-}}"
ROS_DOMAIN_ID_DISPLAY="unset (ROS default 0)"
ROS_DOMAIN_ID_EXPORT_CMD=""
if [[ -n "${ROS_DOMAIN_ID_VALUE}" ]]; then
  ROS_DOMAIN_ID_DISPLAY="${ROS_DOMAIN_ID_VALUE}"
  ROS_DOMAIN_ID_EXPORT_CMD="export ROS_DOMAIN_ID=\"${ROS_DOMAIN_ID_VALUE}\"; "
fi
CYCLONEDDS_CONFIG="${APS_CYCLONEDDS_CONFIG:-$HOME/cyclonedds.xml}"
SKIP_UI_CHECK="${APS_HMI_SKIP_UI_CHECK:-false}"

stop_hint="${SCRIPT_HINT_DIR}/stop_planning_simulator_hmi.sh"
if [[ ! -x "${stop_hint}" && -x "${SCRIPT_HINT_DIR}/archive/stop_planning_simulator_hmi.sh" ]]; then
  stop_hint="${SCRIPT_HINT_DIR}/archive/stop_planning_simulator_hmi.sh"
elif [[ ! -x "${stop_hint}" ]]; then
  stop_hint="${ROOT_DIR}/scripts/stop_planning_simulator_hmi.sh"
fi

mkdir -p "${PID_DIR}" "${LOG_DIR}" "${ROS_DIR}" "${ROS_DIR}/log" "${WEBENGINE_CACHE_DIR}"

if [[ "${HMI_MODE}" != "compose" && "${HMI_MODE}" != "single" ]]; then
  echo "[ERROR] unsupported APS_HMI_MODE: ${HMI_MODE}" >&2
  echo "Use APS_HMI_MODE=compose or APS_HMI_MODE=single" >&2
  exit 1
fi

port_listening() {
  local host="$1"
  local port="$2"

  if command -v ss >/dev/null 2>&1; then
    if [[ "$host" == "127.0.0.1" || "$host" == "localhost" ]]; then
      ss -ltn 2>/dev/null | awk -v target="127.0.0.1:${port}" '$1 == "LISTEN" && $4 == target { found = 1 } END { exit(found ? 0 : 1) }'
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

  if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    echo "[INFO] stopping ${label} (pid ${pid})"
    kill "${pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${pgid}" ]] && kill -0 "-${pgid}" >/dev/null 2>&1; then
    kill "-${pgid}" >/dev/null 2>&1 || true
  fi

  rm -f "${pid_file}" "${pgid_file}"
}

frontend_host="$(python3 - "${FRONTEND_URL}" <<'PY'
import sys
from urllib.parse import urlparse
url = urlparse(sys.argv[1])
print(url.hostname or "")
PY
)"

frontend_port="$(python3 - "${FRONTEND_URL}" <<'PY'
import sys
from urllib.parse import urlparse
url = urlparse(sys.argv[1])
print(url.port or (443 if url.scheme == "https" else 80))
PY
)"

if [[ "${SKIP_UI_CHECK}" != "true" && ( "${frontend_host}" == "127.0.0.1" || "${frontend_host}" == "localhost" ) ]]; then
  echo "[INFO] waiting for local vehicle UI on ${frontend_host}:${frontend_port}"
  ready="false"
  for _ in $(seq 1 "${WAIT_UI_SEC}"); do
    if port_listening "${frontend_host}" "${frontend_port}"; then
      ready="true"
      break
    fi
    sleep 1
  done
  if [[ "${ready}" != "true" ]]; then
    echo "[ERROR] local vehicle UI is not listening on ${frontend_host}:${frontend_port}" >&2
    echo "Start your local vehicle UI/Nest stack first, or rerun with APS_HMI_SKIP_UI_CHECK=true" >&2
    exit 1
  fi
fi

planning_use_sim_time="false"
scenario_simulation_value=""
for arg in "$@"; do
  case "${arg}" in
    use_sim_time:=*)
      planning_use_sim_time="${arg#use_sim_time:=}"
      ;;
    scenario_simulation:=*)
      scenario_simulation_value="${arg#scenario_simulation:=}"
      ;;
  esac
done
if [[ -z "${APS_HMI_USE_SIM_TIME:-}" && "${planning_use_sim_time}" == "false" && "${scenario_simulation_value}" == "true" ]]; then
  planning_use_sim_time="true"
fi
if [[ -n "${APS_HMI_USE_SIM_TIME:-}" ]]; then
  planning_use_sim_time="${APS_HMI_USE_SIM_TIME}"
fi

echo "[INFO] frontend URL: ${FRONTEND_URL}"
echo "[INFO] pid dir: ${PID_DIR}"
echo "[INFO] log dir: ${LOG_DIR}"
echo "[INFO] ros dir: ${ROS_DIR}"
echo "[INFO] WebEngine cache dir: ${WEBENGINE_CACHE_DIR}"
echo "[INFO] ROS_DOMAIN_ID: ${ROS_DOMAIN_ID_DISPLAY}"
echo "[INFO] HMI use_sim_time: ${planning_use_sim_time}"
echo "[INFO] HMI mode: ${HMI_MODE}"
echo "[INFO] HMI WebEngine GPU: ${WEBENGINE_GPU}"
echo "[INFO] HMI web zoom factor: ${WEB_ZOOM_FACTOR}"

bash "${ROOT_DIR}/scripts/stop_planning_simulator_hmi.sh" >/dev/null 2>&1 || true

if [[ ! -f "${OVERLAY_WS}/install/setup.bash" ]]; then
  bash "${ROOT_DIR}/scripts/build_hmi_launch_overlay.sh" >/dev/null
fi

HMI_BIN="${OVERLAY_WS}/install/aps_hmi_container/lib/aps_hmi_container/aps_hmi_container"
RVIZ_CONFIG="${OVERLAY_WS}/src/autoware_launch_APS/autoware_launch/rviz/${RVIZ_CONFIG_NAME}"
if [[ ! -x "${HMI_BIN}" ]]; then
  echo "[ERROR] missing HMI container binary: ${HMI_BIN}" >&2
  exit 1
fi
if [[ ! -f "${RVIZ_CONFIG}" ]]; then
  echo "[ERROR] missing RViz config: ${RVIZ_CONFIG}" >&2
  exit 1
fi

AUTOWARE_CMD="set -euo pipefail; \
set +u; source /opt/ros/humble/setup.bash; source \"${ROOT_DIR}/install/setup.bash\"; set -u; \
mkdir -p \"${ROS_DIR}\" \"${ROS_DIR}/log\"; \
export ROS_HOME=\"${ROS_DIR}\"; \
export APS_HMI_PID_DIR=\"${PID_DIR}\"; \
${ROS_DOMAIN_ID_EXPORT_CMD}\
export RMW_IMPLEMENTATION=\"\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}\"; \
if [[ -z \"\${CYCLONEDDS_URI:-}\" && -f \"${CYCLONEDDS_CONFIG}\" ]]; then export CYCLONEDDS_URI=\"file://${CYCLONEDDS_CONFIG}\"; fi; \
exec ros2 launch autoware_launch planning_simulator.launch.xml rviz:=false"

for arg in "$@"; do
  AUTOWARE_CMD+=" $(printf '%q' "${arg}")"
done

echo "[INFO] starting planning_simulator..."
nohup setsid bash -lc "${AUTOWARE_CMD}" >>"${AUTOWARE_LOG_FILE}" 2>&1 &
autoware_pid=$!
echo "${autoware_pid}" > "${AUTOWARE_PID_FILE}"
autoware_pgid="$(ps -o pgid= -p "${autoware_pid}" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "${autoware_pgid}" ]]; then
  echo "${autoware_pgid}" > "${AUTOWARE_PGID_FILE}"
fi

sleep 2
if ! kill -0 "${autoware_pid}" >/dev/null 2>&1; then
  echo "[ERROR] planning_simulator failed to stay up. Last log lines:" >&2
  tail -n 80 "${AUTOWARE_LOG_FILE}" >&2 || true
  rm -f "${AUTOWARE_PID_FILE}" "${AUTOWARE_PGID_FILE}"
  exit 1
fi

if [[ "${WAIT_AUTOWARE_SEC}" != "0" ]]; then
  sleep "${WAIT_AUTOWARE_SEC}"
fi

if [[ "${HMI_MODE}" == "single" ]]; then
  HMI_CMD="set -euo pipefail; \
set +u; source /opt/ros/humble/setup.bash; source \"${ROOT_DIR}/install/setup.bash\"; source \"${OVERLAY_WS}/install/setup.bash\"; set -u; \
mkdir -p \"${ROS_DIR}\" \"${ROS_DIR}/log\"; \
export ROS_HOME=\"${ROS_DIR}\"; \
${ROS_DOMAIN_ID_EXPORT_CMD}\
export RMW_IMPLEMENTATION=\"\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}\"; \
if [[ -z \"\${CYCLONEDDS_URI:-}\" && -f \"${CYCLONEDDS_CONFIG}\" ]]; then export CYCLONEDDS_URI=\"file://${CYCLONEDDS_CONFIG}\"; fi; \
export QT_QPA_PLATFORM=xcb; \
export QT_OPENGL=desktop; \
export APS_HMI_WEBENGINE_GPU=$(printf '%q' "${WEBENGINE_GPU}"); \
export APS_HMI_WEB_ZOOM_FACTOR=$(printf '%q' "${WEB_ZOOM_FACTOR}"); \
export APS_HMI_WEBENGINE_CACHE_DIR=$(printf '%q' "${WEBENGINE_CACHE_DIR}"); \
if [[ \"${WEBENGINE_GPU}\" == \"true\" ]]; then \
  unset QTWEBENGINE_DISABLE_GPU; \
  export QTWEBENGINE_CHROMIUM_FLAGS='--force-device-scale-factor=1'; \
else \
  export QTWEBENGINE_DISABLE_GPU=1; \
  export QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu --disable-gpu-compositing --disable-gpu-rasterization --ignore-gpu-blocklist --force-device-scale-factor=1'; \
fi; \
exec \"${HMI_BIN}\" \
--frontend-url $(printf '%q' "${FRONTEND_URL}") \
--rviz-config $(printf '%q' "${RVIZ_CONFIG}") \
--rviz-title 'RViz User' \
--window-title $(printf '%q' "${WINDOW_TITLE}") \
--rviz-ratio $(printf '%q' "${RVIZ_RATIO}") \
--fullscreen $(printf '%q' "${FULLSCREEN}") \
--use-sim-time $(printf '%q' "${planning_use_sim_time}") \
--ros-args -r __node:=aps_hmi_container -p use_sim_time:=${planning_use_sim_time}"

  echo "[INFO] starting HMI container..."
  nohup setsid bash -lc "${HMI_CMD}" >>"${HMI_LOG_FILE}" 2>&1 &
  hmi_pid=$!
  echo "${hmi_pid}" > "${HMI_PID_FILE}"
  hmi_pgid="$(ps -o pgid= -p "${hmi_pid}" 2>/dev/null | tr -d ' ' || true)"
  if [[ -n "${hmi_pgid}" ]]; then
    echo "${hmi_pgid}" > "${HMI_PGID_FILE}"
  fi

  sleep 2
  if ! kill -0 "${hmi_pid}" >/dev/null 2>&1; then
    echo "[ERROR] HMI container failed to stay up. Last log lines:" >&2
    tail -n 80 "${HMI_LOG_FILE}" >&2 || true
    rm -f "${HMI_PID_FILE}" "${HMI_PGID_FILE}"
    exit 1
  fi

  if [[ "${FULLSCREEN}" != "true" && -n "${WINDOW_WIDTH}" && -n "${WINDOW_HEIGHT}" ]]; then
    (
      if ! command -v xdotool >/dev/null 2>&1; then
        exit 0
      fi

      for _ in $(seq 1 20); do
        hmi_wid="$(xdotool search --pid "${hmi_pid}" 2>/dev/null | head -n 1 || true)"
        if [[ -n "${hmi_wid}" ]]; then
          xdotool windowsize "${hmi_wid}" "${WINDOW_WIDTH}" "${WINDOW_HEIGHT}" >/dev/null 2>&1 || true
          if [[ -n "${WINDOW_X}" && -n "${WINDOW_Y}" ]]; then
            xdotool windowmove "${hmi_wid}" "${WINDOW_X}" "${WINDOW_Y}" >/dev/null 2>&1 || true
          fi
          exit 0
        fi
        sleep 0.5
      done
    ) &
  fi

  echo "[INFO] started:"
  echo "  planning_simulator log: ${AUTOWARE_LOG_FILE}"
  echo "  hmi log: ${HMI_LOG_FILE}"
  echo "  ros dir: ${ROS_DIR}"
  echo "  stop command: bash ${stop_hint}"
  exit 0
fi

FRONTEND_CMD="set -euo pipefail; \
set +u; source /opt/ros/humble/setup.bash; source \"${ROOT_DIR}/install/setup.bash\"; source \"${OVERLAY_WS}/install/setup.bash\"; set -u; \
mkdir -p \"${ROS_DIR}\" \"${ROS_DIR}/log\"; \
export ROS_HOME=\"${ROS_DIR}\"; \
${ROS_DOMAIN_ID_EXPORT_CMD}\
export RMW_IMPLEMENTATION=\"\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}\"; \
if [[ -z \"\${CYCLONEDDS_URI:-}\" && -f \"${CYCLONEDDS_CONFIG}\" ]]; then export CYCLONEDDS_URI=\"file://${CYCLONEDDS_CONFIG}\"; fi; \
export QT_QPA_PLATFORM=xcb; \
export QT_OPENGL=desktop; \
export APS_HMI_WEBENGINE_GPU=$(printf '%q' "${WEBENGINE_GPU}"); \
export APS_HMI_WEB_ZOOM_FACTOR=$(printf '%q' "${WEB_ZOOM_FACTOR}"); \
export APS_HMI_WEBENGINE_CACHE_DIR=$(printf '%q' "${WEBENGINE_CACHE_DIR}"); \
if [[ \"${WEBENGINE_GPU}\" == \"true\" ]]; then \
  unset QTWEBENGINE_DISABLE_GPU; \
  export QTWEBENGINE_CHROMIUM_FLAGS='--force-device-scale-factor=1'; \
else \
  export QTWEBENGINE_DISABLE_GPU=1; \
  export QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu --disable-gpu-compositing --disable-gpu-rasterization --ignore-gpu-blocklist --force-device-scale-factor=1'; \
fi; \
exec \"${HMI_BIN}\" \
--frontend-url $(printf '%q' "${FRONTEND_URL}") \
--window-title $(printf '%q' "${FRONTEND_WINDOW_TITLE}") \
--fullscreen false \
--frontend-only true"

RVIZ_CMD="set -euo pipefail; \
set +u; source /opt/ros/humble/setup.bash; source \"${ROOT_DIR}/install/setup.bash\"; set -u; \
mkdir -p \"${ROS_DIR}\" \"${ROS_DIR}/log\"; \
export ROS_HOME=\"${ROS_DIR}\"; \
${ROS_DOMAIN_ID_EXPORT_CMD}\
export RMW_IMPLEMENTATION=\"\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}\"; \
if [[ -z \"\${CYCLONEDDS_URI:-}\" && -f \"${CYCLONEDDS_CONFIG}\" ]]; then export CYCLONEDDS_URI=\"file://${CYCLONEDDS_CONFIG}\"; fi; \
export QT_QPA_PLATFORM=xcb; \
export QT_OPENGL=desktop; \
exec rviz2 -d $(printf '%q' "${RVIZ_CONFIG}") -qwindowtitle 'RViz User' --ros-args -p use_sim_time:=${planning_use_sim_time}"

echo "[INFO] starting frontend window..."
nohup setsid bash -lc "${FRONTEND_CMD}" >>"${FRONTEND_LOG_FILE}" 2>&1 &
frontend_pid=$!
echo "${frontend_pid}" > "${FRONTEND_PID_FILE}"
frontend_pgid="$(ps -o pgid= -p "${frontend_pid}" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "${frontend_pgid}" ]]; then
  echo "${frontend_pgid}" > "${FRONTEND_PGID_FILE}"
fi

sleep 2
if ! kill -0 "${frontend_pid}" >/dev/null 2>&1; then
  echo "[ERROR] frontend window failed to stay up. Last log lines:" >&2
  tail -n 80 "${FRONTEND_LOG_FILE}" >&2 || true
  rm -f "${FRONTEND_PID_FILE}" "${FRONTEND_PGID_FILE}"
  exit 1
fi

echo "[INFO] starting standalone RViz..."
nohup setsid bash -lc "${RVIZ_CMD}" >>"${RVIZ_LOG_FILE}" 2>&1 &
rviz_pid=$!
echo "${rviz_pid}" > "${RVIZ_PID_FILE}"
rviz_pgid="$(ps -o pgid= -p "${rviz_pid}" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "${rviz_pgid}" ]]; then
  echo "${rviz_pgid}" > "${RVIZ_PGID_FILE}"
fi

sleep 2
if ! kill -0 "${rviz_pid}" >/dev/null 2>&1; then
  echo "[ERROR] standalone RViz failed to stay up. Last log lines:" >&2
  tail -n 80 "${RVIZ_LOG_FILE}" >&2 || true
  rm -f "${RVIZ_PID_FILE}" "${RVIZ_PGID_FILE}"
  exit 1
fi

LAYOUT_CMD="set -euo pipefail; \
frontend_pid=$(printf '%q' "${frontend_pid}"); \
rviz_pid=$(printf '%q' "${rviz_pid}"); \
target_monitor=$(printf '%q' "${TARGET_MONITOR}"); \
layout_direction=$(printf '%q' "${LAYOUT_DIRECTION}"); \
rviz_ratio=$(printf '%q' "${RVIZ_RATIO}"); \
if ! command -v xdotool >/dev/null 2>&1; then echo '[hmi_layout] xdotool not found; skipping layout.'; exit 0; fi; \
monitor_geom=''; \
if command -v xrandr >/dev/null 2>&1; then \
  if [[ \"${TARGET_MONITOR}\" == 'primary' ]]; then \
    monitor_geom=\$(xrandr --current 2>/dev/null | awk '/ connected primary / { for (i = 1; i <= NF; i++) if (\$i ~ /^[0-9]+x[0-9]+\\+[0-9]+\\+[0-9]+$/) { print \$i; exit } }'); \
  else \
    monitor_geom=\$(xrandr --current 2>/dev/null | awk -v m=\"${TARGET_MONITOR}\" '\$1 == m && / connected / { for (i = 1; i <= NF; i++) if (\$i ~ /^[0-9]+x[0-9]+\\+[0-9]+\\+[0-9]+$/) { print \$i; exit } }'); \
  fi; \
  if [[ -z \"${monitor_geom}\" ]]; then \
    monitor_geom=\$(xrandr --current 2>/dev/null | awk '/ connected / { for (i = 1; i <= NF; i++) if (\$i ~ /^[0-9]+x[0-9]+\\+[0-9]+\\+[0-9]+$/) { print \$i; exit } }'); \
  fi; \
fi; \
if [[ -z \"${monitor_geom}\" ]]; then monitor_geom='1920x1080+0+0'; fi; \
monitor_w=\${monitor_geom%%x*}; \
rest=\${monitor_geom#*x}; \
monitor_h=\${rest%%+*}; \
rest=\${rest#*+}; \
monitor_x=\${rest%%+*}; \
monitor_y=\${rest#*+}; \
if ! [[ \"${rviz_ratio}\" =~ ^[0-9]+$ ]]; then rviz_ratio=60; fi; \
if (( rviz_ratio < 1 )); then rviz_ratio=1; fi; \
if (( rviz_ratio > 99 )); then rviz_ratio=99; fi; \
rviz_w=\$((monitor_w * rviz_ratio / 100)); \
frontend_w=\$((monitor_w - rviz_w)); \
if (( rviz_w < 320 || frontend_w < 320 )); then rviz_w=\$((monitor_w / 2)); frontend_w=\$((monitor_w - rviz_w)); fi; \
for _ in \$(seq 1 20); do \
  frontend_wid=\$(xdotool search --pid \"${frontend_pid}\" 2>/dev/null | head -n 1 || true); \
  rviz_wid=\$(xdotool search --pid \"${rviz_pid}\" 2>/dev/null | head -n 1 || true); \
  if [[ -n \"${frontend_wid}\" && -n \"${rviz_wid}\" ]]; then \
    if [[ \"${layout_direction}\" == 'frontend_right' ]]; then \
      rviz_x=\${monitor_x}; frontend_x=\$((monitor_x + rviz_w)); \
    else \
      frontend_x=\${monitor_x}; rviz_x=\$((monitor_x + frontend_w)); \
    fi; \
    for __ in \$(seq 1 12); do \
      xdotool windowsize \"${frontend_wid}\" \"${frontend_w}\" \"${monitor_h}\" >/dev/null 2>&1 || true; \
      xdotool windowmove \"${frontend_wid}\" \"${frontend_x}\" \"${monitor_y}\" >/dev/null 2>&1 || true; \
      xdotool windowsize \"${rviz_wid}\" \"${rviz_w}\" \"${monitor_h}\" >/dev/null 2>&1 || true; \
      xdotool windowmove \"${rviz_wid}\" \"${rviz_x}\" \"${monitor_y}\" >/dev/null 2>&1 || true; \
      sleep 0.5; \
    done; \
    echo \"[hmi_layout] monitor=\${monitor_geom} frontend=\${frontend_wid} rviz=\${rviz_wid}\"; \
    exit 0; \
  fi; \
  sleep 1; \
done; \
echo '[hmi_layout] timeout waiting for frontend/RViz windows.' >&2; \
exit 0"

echo "[INFO] arranging frontend + RViz layout..."
nohup setsid bash -lc "${LAYOUT_CMD}" >>"${LAYOUT_LOG_FILE}" 2>&1 &
layout_pid=$!
echo "${layout_pid}" > "${LAYOUT_PID_FILE}"
layout_pgid="$(ps -o pgid= -p "${layout_pid}" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "${layout_pgid}" ]]; then
  echo "${layout_pgid}" > "${LAYOUT_PGID_FILE}"
fi

echo "[INFO] started:"
echo "  planning_simulator log: ${AUTOWARE_LOG_FILE}"
echo "  frontend log: ${FRONTEND_LOG_FILE}"
echo "  rviz log: ${RVIZ_LOG_FILE}"
echo "  layout log: ${LAYOUT_LOG_FILE}"
echo "  ros dir: ${ROS_DIR}"
echo "  stop command: bash ${stop_hint}"
