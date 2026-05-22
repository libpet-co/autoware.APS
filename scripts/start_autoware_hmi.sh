#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/hmi_env.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  start_autoware_hmi.sh [autoware ros2 launch args...]

Purpose:
  Start standalone aps_hmi_container together with Autoware autoware.launch.xml.

Defaults:
  Frontend URL: http://127.0.0.1:3001/aps/welcome
  use_sim_time:=false
  vehicle_model:=aps_vehicle
  sensor_model:=aps_sensor_kit
  sensor_config_profile:=aps998
  lanelet2_map_file:=frontway2.osm
  pointcloud_map_file:=front.pcd
  HMI mode: single

Environment overrides:
  APS_ROOT_DIR                    Autoware workspace root (default: $HOME/autoware.APS)
  APS_HMI_TEST_ROOT               Runtime root (default: $HOME/hmi_test)
  APS_HMI_PID_DIR                 PID directory (default: $APS_HMI_TEST_ROOT/.pid)
  APS_HMI_LOG_DIR                 Log directory (default: $APS_HMI_TEST_ROOT/.log)
  APS_HMI_ROS_DIR                 ROS_HOME directory (default: $APS_HMI_TEST_ROOT/.ros)
  APS_HMI_FRONTEND_URL            Local vehicle UI URL (default: http://127.0.0.1:3001/aps/welcome)
  APS_HMI_FULLSCREEN              true/false, forwarded to standalone HMI container (default: true)
  APS_HMI_WINDOW_TITLE            HMI window title (default: APS HMI Container)
  APS_HMI_RVIZ_RATIO              RViz width ratio inside HMI container (default: 30)
  APS_HMI_MODE                    single/compose (default: single)
  APS_HMI_RVIZ_CONFIG_NAME        RViz config filename under autoware_launch/rviz (default: autoware_hmi_startup.rviz)
  APS_HMI_TARGET_MONITOR          xrandr monitor name or "primary" (default: primary)
  APS_HMI_LAYOUT_DIRECTION        frontend_left/frontend_right (default: frontend_left)
  APS_HMI_WEBENGINE_GPU           true/false, forwarded via environment (default: false)
  APS_HMI_WEB_ZOOM_FACTOR         forwarded via environment (default: 1.25)
  APS_HMI_LAUNCH_PREFIX           Optional shell prefix for standalone HMI, e.g. 'taskset -c 2-3 nice -n 5'
  APS_AUTOWARE_LAUNCH_PREFIX      Optional shell prefix for autoware.launch.xml, e.g. 'taskset -c 0-1'
  APS_HMI_WAIT_UI_SEC             Max seconds waiting for local UI URL (default: 60)
  APS_HMI_WAIT_SHELL_SEC          Max seconds waiting for the native HMI shell before Autoware launch (default: 30)
  APS_HMI_UI_WAIT_MODE            block/async/skip local UI precheck mode (default: async)
  APS_HMI_SKIP_UI_CHECK           true/false skip local UI reachability check (default: false)
  APS_HMI_LOADING_GATE_SLOW_SEC   Seconds before Loading APS switches to delayed state (default: 90)
  APS_HMI_LOADING_GATE_WATCHDOG_LOG_SEC Seconds between repeated loading gate warnings (default: 15)
  APS_HMI_LOG_ROTATE_MAX_BYTES    Rotate active HMI/Autoware logs above this size before launch (default: 104857600; <=0 disables)
  APS_HMI_LOG_ROTATE_KEEP         Number of rotated timestamped logs to keep per file (default: 0, keep all)
  APS_HMI_USE_SETUP_ENV_CACHE     true/false use precomputed ROS setup env (default: false)
  APS_HMI_SETUP_ENV_CACHE         Sourceable env cache path (default: $APS_HMI_TEST_ROOT/.cache/autoware_setup_env.bash)
  APS_HMI_IMPORT_SHELL_ROS_ENV    true/false import ROS env from ~/.bashrc when needed
  APS_HMI_DISPLAY                 Explicit X11 display override (default: auto-detect, usually :0)
  APS_HMI_XAUTHORITY              Explicit X11 authority file override
  APS_ROS_DOMAIN_ID               Optional ROS_DOMAIN_ID override
  APS_CYCLONEDDS_CONFIG           CycloneDDS XML path (default: $HOME/cyclonedds.xml)
  APS_AUTOWARE_USE_SIM_TIME       Autoware use_sim_time value (default: false)
  APS_AUTOWARE_MAP_PATH           Optional explicit map_path override
  APS_AUTOWARE_VEHICLE_MODEL      vehicle_model override (default: aps_vehicle)
  APS_AUTOWARE_SENSOR_MODEL       sensor_model override (default: aps_sensor_kit)
  APS_AUTOWARE_SENSOR_CONFIG_PROFILE sensor_config_profile override (default: aps998)
  APS_AUTOWARE_LANELET2_MAP_FILE  lanelet2 map file override (default: frontway2.osm)
  APS_AUTOWARE_POINTCLOUD_MAP_FILE pointcloud map file override (default: front.pcd)
  APS_AUTOWARE_LAUNCH_MAP         launch_map override for main Autoware (default: true)
  APS_AUTOWARE_ENSURE_MAP_COMPONENTS ensure_map_components override for main Autoware (default: true)

Examples:
  bash /root/autoware.APS/scripts/start_autoware_hmi.sh
  APS_AUTOWARE_MAP_PATH=/data/map bash /root/autoware.APS/scripts/start_autoware_hmi.sh
EOF
  exit 0
fi

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
MAIN_LAUNCH_REPO="${APS_LAUNCH_REPO:-$ROOT_DIR/src/launcher/autoware_launch_APS}"
HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HOME/hmi_test}"
FRONTEND_URL="${APS_HMI_FRONTEND_URL:-http://127.0.0.1:3001/aps/welcome}"
PID_DIR="${APS_HMI_PID_DIR:-$HMI_TEST_ROOT/.pid}"
LOG_DIR="${APS_HMI_LOG_DIR:-$HMI_TEST_ROOT/.log}"
ROS_DIR="${APS_HMI_ROS_DIR:-$HMI_TEST_ROOT/.ros}"
WEBENGINE_CACHE_DIR="${APS_HMI_WEBENGINE_CACHE_DIR:-$HMI_TEST_ROOT/.cache/webengine}"
SETUP_ENV_CACHE="${APS_HMI_SETUP_ENV_CACHE:-$HMI_TEST_ROOT/.cache/autoware_setup_env.bash}"
USE_SETUP_ENV_CACHE="$(printf '%s' "${APS_HMI_USE_SETUP_ENV_CACHE:-false}" | tr '[:upper:]' '[:lower:]')"
AUTOWARE_LOG_FILE="${LOG_DIR}/autoware_launch_hmi.log"
AUTOWARE_PID_FILE="${PID_DIR}/autoware_launch.pid"
AUTOWARE_PGID_FILE="${PID_DIR}/autoware_launch.pgid"
HMI_LOG_FILE="${LOG_DIR}/hmi_container.log"
HMI_PID_FILE="${PID_DIR}/hmi_container.pid"
HMI_PGID_FILE="${PID_DIR}/hmi_container.pgid"
HMI_SHELL_WID_FILE="${PID_DIR}/hmi_shell.wid"
WAIT_UI_SEC="${APS_HMI_WAIT_UI_SEC:-60}"
WAIT_HMI_SHELL_SEC="${APS_HMI_WAIT_SHELL_SEC:-30}"
UI_WAIT_MODE="$(printf '%s' "${APS_HMI_UI_WAIT_MODE:-async}" | tr '[:upper:]' '[:lower:]')"
LOADING_GATE_SLOW_SEC="${APS_HMI_LOADING_GATE_SLOW_SEC:-90}"
LOADING_GATE_WATCHDOG_LOG_SEC="${APS_HMI_LOADING_GATE_WATCHDOG_LOG_SEC:-15}"
LOG_ROTATE_MAX_BYTES="${APS_HMI_LOG_ROTATE_MAX_BYTES:-104857600}"
LOG_ROTATE_KEEP="${APS_HMI_LOG_ROTATE_KEEP:-0}"
FULLSCREEN="${APS_HMI_FULLSCREEN:-true}"
RVIZ_RATIO="${APS_HMI_RVIZ_RATIO:-30}"
WINDOW_TITLE="${APS_HMI_WINDOW_TITLE:-APS HMI Container}"
HMI_MODE="$(printf '%s' "${APS_HMI_MODE:-single}" | tr '[:upper:]' '[:lower:]')"
RVIZ_CONFIG_NAME="${APS_HMI_RVIZ_CONFIG_NAME:-autoware_hmi_startup.rviz}"
TARGET_MONITOR="${APS_HMI_TARGET_MONITOR:-primary}"
LAYOUT_DIRECTION="${APS_HMI_LAYOUT_DIRECTION:-frontend_left}"
WEBENGINE_GPU="${APS_HMI_WEBENGINE_GPU:-false}"
WEB_ZOOM_FACTOR="${APS_HMI_WEB_ZOOM_FACTOR:-1.25}"
FORCE_SOFTWARE_GL="${APS_HMI_FORCE_SOFTWARE_GL:-false}"
HMI_LAUNCH_PREFIX="${APS_HMI_LAUNCH_PREFIX:-}"
AUTOWARE_LAUNCH_PREFIX="${APS_AUTOWARE_LAUNCH_PREFIX:-}"
ROS_DOMAIN_ID_VALUE="${APS_ROS_DOMAIN_ID:-${ROS_DOMAIN_ID:-}}"
ROS_DOMAIN_ID_DISPLAY="unset (ROS default 0)"
ROS_DOMAIN_ID_EXPORT_CMD=""
if [[ -n "${ROS_DOMAIN_ID_VALUE}" ]]; then
  ROS_DOMAIN_ID_DISPLAY="${ROS_DOMAIN_ID_VALUE}"
  ROS_DOMAIN_ID_EXPORT_CMD="export ROS_DOMAIN_ID=\"${ROS_DOMAIN_ID_VALUE}\"; "
fi
CYCLONEDDS_CONFIG="${APS_CYCLONEDDS_CONFIG:-$HOME/cyclonedds.xml}"
SKIP_UI_CHECK="${APS_HMI_SKIP_UI_CHECK:-false}"

AUTOWARE_USE_SIM_TIME="${APS_AUTOWARE_USE_SIM_TIME:-false}"
AUTOWARE_MAP_PATH="${APS_AUTOWARE_MAP_PATH:-}"
AUTOWARE_VEHICLE_MODEL="${APS_AUTOWARE_VEHICLE_MODEL:-aps_vehicle}"
AUTOWARE_SENSOR_MODEL="${APS_AUTOWARE_SENSOR_MODEL:-aps_sensor_kit}"
AUTOWARE_SENSOR_CONFIG_PROFILE="${APS_AUTOWARE_SENSOR_CONFIG_PROFILE:-aps998}"
AUTOWARE_LANELET2_MAP_FILE="${APS_AUTOWARE_LANELET2_MAP_FILE:-frontway2.osm}"
AUTOWARE_POINTCLOUD_MAP_FILE="${APS_AUTOWARE_POINTCLOUD_MAP_FILE:-front.pcd}"
AUTOWARE_LAUNCH_MAP="${APS_AUTOWARE_LAUNCH_MAP:-true}"
AUTOWARE_ENSURE_MAP_COMPONENTS="${APS_AUTOWARE_ENSURE_MAP_COMPONENTS:-true}"

mkdir -p "${PID_DIR}" "${LOG_DIR}" "${ROS_DIR}" "${ROS_DIR}/log" "${WEBENGINE_CACHE_DIR}"

if [[ ! -f "${ROOT_DIR}/install/setup.bash" ]]; then
  echo "[ERROR] missing main workspace setup: ${ROOT_DIR}/install/setup.bash" >&2
  exit 1
fi

ROS_SETUP_CMD="source /opt/ros/humble/setup.bash; source \"${ROOT_DIR}/install/setup.bash\";"
ROS_SETUP_SOURCE_DESC="full setup (${ROOT_DIR}/install/setup.bash)"
if [[ "${USE_SETUP_ENV_CACHE}" == "true" ]]; then
  if [[ -r "${SETUP_ENV_CACHE}" ]]; then
    ROS_SETUP_CMD="source \"${SETUP_ENV_CACHE}\";"
    ROS_SETUP_SOURCE_DESC="cached env (${SETUP_ENV_CACHE})"
  else
    echo "[WARN] APS_HMI_USE_SETUP_ENV_CACHE=true but cache is missing: ${SETUP_ENV_CACHE}; falling back to full ROS setup" >&2
  fi
fi

case "${UI_WAIT_MODE}" in
  block|async|skip)
    ;;
  *)
    echo "[ERROR] unsupported APS_HMI_UI_WAIT_MODE: ${UI_WAIT_MODE}" >&2
    echo "Use APS_HMI_UI_WAIT_MODE=block, async, or skip" >&2
    exit 1
    ;;
esac

if [[ "${HMI_MODE}" == "single" ]]; then
  HMI_SINGLE_CONTAINER="true"
  HMI_COMPOSE_LAYOUT="false"
elif [[ "${HMI_MODE}" == "compose" ]]; then
  HMI_SINGLE_CONTAINER="false"
  HMI_COMPOSE_LAYOUT="true"
else
  echo "[ERROR] unsupported APS_HMI_MODE: ${HMI_MODE}" >&2
  echo "Use APS_HMI_MODE=single or APS_HMI_MODE=compose" >&2
  exit 1
fi

ensure_hmi_display_access

http_ready() {
  local url="$1"
  local code
  code="$(curl -L -s -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
  [[ "${code}" =~ ^2|^3 ]]
}

wait_for_hmi_shell() {
  local pid="$1"
  local wait_sec="$2"

  if [[ ! "${wait_sec}" =~ ^[0-9]+$ || "${wait_sec}" -le 0 ]]; then
    return 0
  fi

  echo "[INFO] waiting up to ${wait_sec}s for native HMI shell before Autoware launch"
  for _ in $(seq 1 "${wait_sec}"); do
    if [[ -s "${HMI_SHELL_WID_FILE}" ]]; then
      echo "[INFO] native HMI shell is ready"
      return 0
    fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      echo "[ERROR] standalone aps_hmi_container exited before native HMI shell was ready" >&2
      tail -n 80 "${HMI_LOG_FILE}" >&2 || true
      rm -f "${HMI_PID_FILE}" "${HMI_PGID_FILE}"
      exit 1
    fi
    sleep 1
  done

  echo "[WARN] native HMI shell did not become ready within ${wait_sec}s; continuing with Autoware launch"
}

rotate_log_file_if_large() {
  local log_file="$1"

  if [[ ! "${LOG_ROTATE_MAX_BYTES}" =~ ^[0-9]+$ || "${LOG_ROTATE_MAX_BYTES}" -le 0 ]]; then
    return 0
  fi
  if [[ ! -f "${log_file}" ]]; then
    return 0
  fi

  local size
  size="$(stat -c '%s' "${log_file}" 2>/dev/null || echo 0)"
  if [[ ! "${size}" =~ ^[0-9]+$ || "${size}" -lt "${LOG_ROTATE_MAX_BYTES}" ]]; then
    return 0
  fi

  local rotated_file
  rotated_file="${log_file}.$(date +%Y%m%d-%H%M%S)"
  mv -- "${log_file}" "${rotated_file}"
  : > "${log_file}"
  echo "[INFO] rotated log: ${log_file} -> ${rotated_file} (${size} bytes)"

  if [[ ! "${LOG_ROTATE_KEEP}" =~ ^[0-9]+$ || "${LOG_ROTATE_KEEP}" -le 0 ]]; then
    return 0
  fi

  mapfile -t old_logs < <(find "$(dirname "${log_file}")" -maxdepth 1 -type f -name "$(basename "${log_file}").20*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk -v keep="${LOG_ROTATE_KEEP}" 'NR > keep {print $2}')
  for old_log in "${old_logs[@]}"; do
    echo "[INFO] removing old rotated log: ${old_log}"
    rm -f -- "${old_log}"
  done
}

pid_file_has_live_hmi_target() {
  local pid_file="$1"
  local pid=""
  local cmd=""

  [[ -f "${pid_file}" ]] || return 1
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1

  cmd="$(ps -p "${pid}" -o args= 2>/dev/null || true)"
  [[ -n "${cmd}" ]] || return 1

  case "${cmd}" in
    *aps_hmi_container*|*"ros2 launch autoware_launch autoware.launch.xml"*)
      return 0
      ;;
  esac

  return 1
}

hmi_stack_process_running() {
  local pid_file=""

  for pid_file in \
    "${AUTOWARE_PID_FILE}" \
    "${HMI_PID_FILE}" \
    "${PID_DIR}/hmi_frontend.pid" \
    "${PID_DIR}/rviz_user.pid"; do
    if pid_file_has_live_hmi_target "${pid_file}"; then
      return 0
    fi
  done

  pgrep -f 'aps_hmi_container|ros2 launch autoware_launch autoware.launch.xml' >/dev/null 2>&1
}

clear_stale_hmi_runtime_files() {
  rm -f \
    "${AUTOWARE_PID_FILE}" \
    "${AUTOWARE_PGID_FILE}" \
    "${HMI_PID_FILE}" \
    "${HMI_PGID_FILE}" \
    "${HMI_SHELL_WID_FILE}" \
    "${PID_DIR}/frontend_host.wid" \
    "${PID_DIR}/hmi_frontend.pid" \
    "${PID_DIR}/hmi_frontend.render_ready" \
    "${PID_DIR}/rviz_host.wid" \
    "${PID_DIR}/rviz_user.pid"
}

frontend_host="$(python3 - "${FRONTEND_URL}" <<'PY'
import sys
from urllib.parse import urlparse
url = urlparse(sys.argv[1])
print(url.hostname or "")
PY
)"

if [[ "${SKIP_UI_CHECK}" != "true" && ( "${frontend_host}" == "127.0.0.1" || "${frontend_host}" == "localhost" ) ]]; then
  if http_ready "${FRONTEND_URL}"; then
    :
  elif [[ "${UI_WAIT_MODE}" == "block" ]]; then
    echo "[INFO] waiting for local vehicle UI at ${FRONTEND_URL}"
    ready="false"
    for _ in $(seq 1 "${WAIT_UI_SEC}"); do
      if http_ready "${FRONTEND_URL}"; then
        ready="true"
        break
      fi
      sleep 1
    done
    if [[ "${ready}" != "true" ]]; then
      echo "[ERROR] local vehicle UI is not reachable at ${FRONTEND_URL}" >&2
      echo "Start your local vehicle UI/Nest stack first, or rerun with APS_HMI_SKIP_UI_CHECK=true" >&2
      exit 1
    fi
  elif [[ "${UI_WAIT_MODE}" == "async" ]]; then
    echo "[INFO] local vehicle UI is not ready yet at ${FRONTEND_URL}; starting HMI immediately and letting it retry in background"
  else
    echo "[INFO] skipping local vehicle UI precheck for ${FRONTEND_URL}"
  fi
fi

echo "[INFO] frontend URL: ${FRONTEND_URL}"
echo "[INFO] pid dir: ${PID_DIR}"
echo "[INFO] log dir: ${LOG_DIR}"
echo "[INFO] ros dir: ${ROS_DIR}"
echo "[INFO] WebEngine cache dir: ${WEBENGINE_CACHE_DIR}"
echo "[INFO] ROS_DOMAIN_ID: ${ROS_DOMAIN_ID_DISPLAY}"
echo "[INFO] HMI mode: ${HMI_MODE}"
echo "[INFO] HMI fullscreen: ${FULLSCREEN}"
echo "[INFO] HMI rviz ratio: ${RVIZ_RATIO}"
echo "[INFO] HMI WebEngine GPU: ${WEBENGINE_GPU}"
echo "[INFO] HMI web zoom factor: ${WEB_ZOOM_FACTOR}"
echo "[INFO] HMI UI wait mode: ${UI_WAIT_MODE}"
echo "[INFO] HMI shell wait sec: ${WAIT_HMI_SHELL_SEC}"
echo "[INFO] HMI loading gate slow sec: ${LOADING_GATE_SLOW_SEC}"
echo "[INFO] HMI loading gate watchdog log sec: ${LOADING_GATE_WATCHDOG_LOG_SEC}"
echo "[INFO] ROS setup env: ${ROS_SETUP_SOURCE_DESC}"
if [[ -n "${HMI_LAUNCH_PREFIX}" ]]; then
  echo "[INFO] HMI launch prefix: ${HMI_LAUNCH_PREFIX}"
fi
if [[ -n "${AUTOWARE_LAUNCH_PREFIX}" ]]; then
  echo "[INFO] autoware launch prefix: ${AUTOWARE_LAUNCH_PREFIX}"
fi
echo "[INFO] Autoware use_sim_time: ${AUTOWARE_USE_SIM_TIME}"
echo "[INFO] vehicle_model: ${AUTOWARE_VEHICLE_MODEL}"
echo "[INFO] sensor_model: ${AUTOWARE_SENSOR_MODEL}"
echo "[INFO] sensor_config_profile: ${AUTOWARE_SENSOR_CONFIG_PROFILE}"
echo "[INFO] lanelet2_map_file: ${AUTOWARE_LANELET2_MAP_FILE}"
echo "[INFO] pointcloud_map_file: ${AUTOWARE_POINTCLOUD_MAP_FILE}"
echo "[INFO] launch_map: ${AUTOWARE_LAUNCH_MAP}"
echo "[INFO] ensure_map_components: ${AUTOWARE_ENSURE_MAP_COMPONENTS}"
if [[ -n "${AUTOWARE_MAP_PATH}" ]]; then
  echo "[INFO] map_path: ${AUTOWARE_MAP_PATH}"
fi

if hmi_stack_process_running; then
  bash "${ROOT_DIR}/scripts/stop_autoware_hmi.sh" >/dev/null 2>&1 || true
else
  echo "[INFO] no existing HMI stack process detected; skipping stop cleanup"
  clear_stale_hmi_runtime_files
fi
rotate_log_file_if_large "${HMI_LOG_FILE}"
rotate_log_file_if_large "${AUTOWARE_LOG_FILE}"

MAIN_HMI_BIN="${ROOT_DIR}/install/aps_hmi_container/lib/aps_hmi_container/aps_hmi_container"
MAIN_RVIZ_CONFIG="${MAIN_LAUNCH_REPO}/autoware_launch/rviz/${RVIZ_CONFIG_NAME}"

HMI_BIN="${MAIN_HMI_BIN}"
RVIZ_CONFIG="${MAIN_RVIZ_CONFIG}"
echo "[INFO] HMI artifacts: using main workspace (${ROOT_DIR})"

if [[ "${HMI_MODE}" == "single" ]]; then
  if [[ ! -x "${HMI_BIN}" ]]; then
    echo "[ERROR] missing HMI container binary: ${HMI_BIN}" >&2
    echo "Build it with: colcon build --packages-select aps_hmi_container autoware_launch --cmake-force-configure --symlink-install --allow-overriding autoware_launch --cmake-args -DBUILD_TESTING=OFF" >&2
    exit 1
  fi
  if [[ ! -f "${RVIZ_CONFIG}" ]]; then
    echo "[ERROR] missing RViz config: ${RVIZ_CONFIG}" >&2
    echo "Check APS_LAUNCH_REPO or rebuild the main workspace launch artifacts." >&2
    exit 1
  fi

  HMI_CMD="set -euo pipefail; \
set +u; ${ROS_SETUP_CMD} set -u; \
mkdir -p \"${ROS_DIR}\" \"${ROS_DIR}/log\"; \
export ROS_HOME=\"${ROS_DIR}\"; \
export APS_HMI_PID_DIR=\"${PID_DIR}\"; \
${ROS_DOMAIN_ID_EXPORT_CMD}\
export RMW_IMPLEMENTATION=\"\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}\"; \
if [[ -z \"\${CYCLONEDDS_URI:-}\" && -f \"${CYCLONEDDS_CONFIG}\" ]]; then export CYCLONEDDS_URI=\"file://${CYCLONEDDS_CONFIG}\"; fi; \
export QT_QPA_PLATFORM=xcb; \
export QT_OPENGL=desktop; \
export APS_HMI_WEBENGINE_GPU=$(printf '%q' "${WEBENGINE_GPU}"); \
export APS_HMI_WEB_ZOOM_FACTOR=$(printf '%q' "${WEB_ZOOM_FACTOR}"); \
export APS_HMI_WEBENGINE_CACHE_DIR=$(printf '%q' "${WEBENGINE_CACHE_DIR}"); \
export APS_HMI_FORCE_SOFTWARE_GL=$(printf '%q' "${FORCE_SOFTWARE_GL}"); \
if [[ \"${WEBENGINE_GPU}\" == \"true\" ]]; then \
  unset QTWEBENGINE_DISABLE_GPU; \
  export QTWEBENGINE_CHROMIUM_FLAGS='--force-device-scale-factor=1'; \
else \
  export QTWEBENGINE_DISABLE_GPU=1; \
  export QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu --disable-gpu-compositing --disable-gpu-rasterization --ignore-gpu-blocklist --force-device-scale-factor=1'; \
fi; \
exec ${HMI_LAUNCH_PREFIX} \"${HMI_BIN}\" \
--frontend-url $(printf '%q' "${FRONTEND_URL}") \
--rviz-config $(printf '%q' "${RVIZ_CONFIG}") \
--rviz-title 'RViz User' \
--window-title $(printf '%q' "${WINDOW_TITLE}") \
--rviz-ratio $(printf '%q' "${RVIZ_RATIO}") \
--fullscreen $(printf '%q' "${FULLSCREEN}") \
--use-sim-time $(printf '%q' "${AUTOWARE_USE_SIM_TIME}") \
--ros-args -r __node:=aps_hmi_container -p use_sim_time:=${AUTOWARE_USE_SIM_TIME}"

  echo "[INFO] starting standalone aps_hmi_container..."
  rm -f "${HMI_SHELL_WID_FILE}"
  nohup setsid bash -lc "${HMI_CMD}" >>"${HMI_LOG_FILE}" 2>&1 &
  hmi_pid=$!
  echo "${hmi_pid}" > "${HMI_PID_FILE}"
  hmi_pgid="$(ps -o pgid= -p "${hmi_pid}" 2>/dev/null | tr -d ' ' || true)"
  if [[ -n "${hmi_pgid}" ]]; then
    echo "${hmi_pgid}" > "${HMI_PGID_FILE}"
  fi

  sleep 2
  if ! kill -0 "${hmi_pid}" >/dev/null 2>&1; then
    echo "[ERROR] standalone aps_hmi_container failed to stay up. Last log lines:" >&2
    tail -n 80 "${HMI_LOG_FILE}" >&2 || true
    rm -f "${HMI_PID_FILE}" "${HMI_PGID_FILE}"
    exit 1
  fi

  wait_for_hmi_shell "${hmi_pid}" "${WAIT_HMI_SHELL_SEC}"
fi

AUTOWARE_ARGS=(
  "use_sim_time:=${AUTOWARE_USE_SIM_TIME}"
  "vehicle_model:=${AUTOWARE_VEHICLE_MODEL}"
  "sensor_model:=${AUTOWARE_SENSOR_MODEL}"
  "sensor_config_profile:=${AUTOWARE_SENSOR_CONFIG_PROFILE}"
  "lanelet2_map_file:=${AUTOWARE_LANELET2_MAP_FILE}"
  "pointcloud_map_file:=${AUTOWARE_POINTCLOUD_MAP_FILE}"
  "launch_map:=${AUTOWARE_LAUNCH_MAP}"
  "ensure_map_components:=${AUTOWARE_ENSURE_MAP_COMPONENTS}"
  "launch_hmi_container:=false"
  "hmi_single_container:=${HMI_SINGLE_CONTAINER}"
  "hmi_compose_layout:=${HMI_COMPOSE_LAYOUT}"
  "hmi_single_fullscreen:=${FULLSCREEN}"
  "rviz_fullscreen:=false"
  "hmi_frontend_url:=${FRONTEND_URL}"
  "hmi_rviz_ratio:=${RVIZ_RATIO}"
  "hmi_single_window_title:=${WINDOW_TITLE}"
  "hmi_target_monitor:=${TARGET_MONITOR}"
  "hmi_layout_direction:=${LAYOUT_DIRECTION}"
  "hmi_force_software_gl:=${FORCE_SOFTWARE_GL}"
)

if [[ -n "${AUTOWARE_MAP_PATH}" ]]; then
  AUTOWARE_ARGS+=("map_path:=${AUTOWARE_MAP_PATH}")
fi

for arg in "$@"; do
  AUTOWARE_ARGS+=("${arg}")
done

AUTOWARE_ARG_STRING=""
for arg in "${AUTOWARE_ARGS[@]}"; do
  AUTOWARE_ARG_STRING+=" $(printf '%q' "${arg}")"
done

AUTOWARE_CMD="set -euo pipefail; \
set +u; ${ROS_SETUP_CMD} set -u; \
mkdir -p \"${ROS_DIR}\" \"${ROS_DIR}/log\"; \
export ROS_HOME=\"${ROS_DIR}\"; \
export APS_HMI_PID_DIR=\"${PID_DIR}\"; \
export APS_HMI_WEBENGINE_GPU=$(printf '%q' "${WEBENGINE_GPU}"); \
export APS_HMI_WEB_ZOOM_FACTOR=$(printf '%q' "${WEB_ZOOM_FACTOR}"); \
export APS_HMI_WEBENGINE_CACHE_DIR=$(printf '%q' "${WEBENGINE_CACHE_DIR}"); \
${ROS_DOMAIN_ID_EXPORT_CMD}\
export RMW_IMPLEMENTATION=\"\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}\"; \
if [[ -z \"\${CYCLONEDDS_URI:-}\" && -f \"${CYCLONEDDS_CONFIG}\" ]]; then export CYCLONEDDS_URI=\"file://${CYCLONEDDS_CONFIG}\"; fi; \
exec ${AUTOWARE_LAUNCH_PREFIX} ros2 launch autoware_launch autoware.launch.xml${AUTOWARE_ARG_STRING}"

echo "[INFO] starting autoware.launch.xml..."
nohup setsid bash -lc "${AUTOWARE_CMD}" >>"${AUTOWARE_LOG_FILE}" 2>&1 &
autoware_pid=$!
echo "${autoware_pid}" > "${AUTOWARE_PID_FILE}"
autoware_pgid="$(ps -o pgid= -p "${autoware_pid}" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "${autoware_pgid}" ]]; then
  echo "${autoware_pgid}" > "${AUTOWARE_PGID_FILE}"
fi

sleep 2
if ! kill -0 "${autoware_pid}" >/dev/null 2>&1; then
  echo "[ERROR] autoware.launch.xml failed to stay up. Last log lines:" >&2
  tail -n 80 "${AUTOWARE_LOG_FILE}" >&2 || true
  rm -f "${AUTOWARE_PID_FILE}" "${AUTOWARE_PGID_FILE}"
  bash "${ROOT_DIR}/scripts/stop_autoware_hmi.sh" >/dev/null 2>&1 || true
  exit 1
fi

echo "[INFO] started:"
echo "  autoware log: ${AUTOWARE_LOG_FILE}"
if [[ "${HMI_MODE}" == "single" ]]; then
  echo "  hmi log: ${HMI_LOG_FILE}"
fi
echo "  ros dir: ${ROS_DIR}"
echo "  stop command: bash ${ROOT_DIR}/scripts/stop_autoware_hmi.sh"
