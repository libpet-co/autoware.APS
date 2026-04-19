#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
HMI_TEST_ROOT="${HMI_TEST_ROOT:-$HOME/hmi_test}"
BASHRC_PATH="${APS_HMI_ENV_BASHRC:-$HOME/.bashrc}"

inherit_ros_env_from_bashrc() {
  if [[ -n "${APS_ROS_DOMAIN_ID:-}" || -n "${ROS_DOMAIN_ID:-}" ]]; then
    return 0
  fi
  if [[ ! -f "${BASHRC_PATH}" ]]; then
    return 0
  fi

  local bashrc_env
  bashrc_env="$(
    HOME="${HOME}" \
    USER="${USER:-$(id -un)}" \
    LOGNAME="${LOGNAME:-${USER:-$(id -un)}}" \
    SHELL=/bin/bash \
    PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}" \
    bash -ic 'printf "APS_ROS_DOMAIN_ID=%s\nROS_DOMAIN_ID=%s\nRMW_IMPLEMENTATION=%s\nCYCLONEDDS_URI=%s\n" "${APS_ROS_DOMAIN_ID:-}" "${ROS_DOMAIN_ID:-}" "${RMW_IMPLEMENTATION:-}" "${CYCLONEDDS_URI:-}"' 2>/dev/null || true
  )"

  while IFS='=' read -r key value; do
    [[ -n "${value}" ]] || continue
    case "${key}" in
      APS_ROS_DOMAIN_ID)
        export APS_ROS_DOMAIN_ID="${value}"
        ;;
      ROS_DOMAIN_ID)
        if [[ -z "${APS_ROS_DOMAIN_ID:-}" ]]; then
          export ROS_DOMAIN_ID="${value}"
        fi
        ;;
      RMW_IMPLEMENTATION)
        export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-${value}}"
        ;;
      CYCLONEDDS_URI)
        export CYCLONEDDS_URI="${CYCLONEDDS_URI:-${value}}"
        ;;
    esac
  done <<< "${bashrc_env}"
}

if [[ "${APS_HMI_IMPORT_SHELL_ROS_ENV:-true}" == "true" ]]; then
  inherit_ros_env_from_bashrc
fi

export APS_ROOT_DIR="${ROOT_DIR}"
export HMI_TEST_ROOT="${HMI_TEST_ROOT}"
export APS_HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HMI_TEST_ROOT}"
export APS_HMI_PID_DIR="${APS_HMI_PID_DIR:-$HMI_TEST_ROOT/.pid}"
export APS_HMI_LOG_DIR="${APS_HMI_LOG_DIR:-$HMI_TEST_ROOT/.log}"
export APS_HMI_ROS_DIR="${APS_HMI_ROS_DIR:-$HMI_TEST_ROOT/.ros}"
export APS_HMI_WEBENGINE_CACHE_DIR="${APS_HMI_WEBENGINE_CACHE_DIR:-$HMI_TEST_ROOT/.cache/webengine}"
export APS_LOCAL_STACK_PID_DIR="${APS_LOCAL_STACK_PID_DIR:-$APS_HMI_PID_DIR}"
export APS_LOCAL_STACK_LOG_DIR="${APS_LOCAL_STACK_LOG_DIR:-$APS_HMI_LOG_DIR}"
export APS_FB_RUNTIME_ROOT="${APS_FB_RUNTIME_ROOT:-$HMI_TEST_ROOT}"
export APS_FB_PID_DIR="${APS_FB_PID_DIR:-$APS_HMI_PID_DIR}"
export APS_FB_LOG_DIR="${APS_FB_LOG_DIR:-$APS_HMI_LOG_DIR}"
export APS_FB_ROS_DIR="${APS_FB_ROS_DIR:-$APS_HMI_ROS_DIR}"
export APS_HMI_SCRIPT_DIR="${APS_HMI_SCRIPT_DIR:-$ROOT_DIR/scripts}"

mkdir -p \
  "${APS_HMI_PID_DIR}" \
  "${APS_HMI_LOG_DIR}" \
  "${APS_HMI_ROS_DIR}" \
  "${APS_HMI_ROS_DIR}/log" \
  "${APS_HMI_WEBENGINE_CACHE_DIR}"

detect_hmi_display() {
  local socket

  if [[ -n "${APS_HMI_DISPLAY:-}" ]]; then
    printf '%s\n' "${APS_HMI_DISPLAY}"
    return 0
  fi

  if [[ -n "${DISPLAY:-}" ]]; then
    printf '%s\n' "${DISPLAY}"
    return 0
  fi

  if [[ -S /tmp/.X11-unix/X0 ]]; then
    printf ':0\n'
    return 0
  fi

  for socket in /tmp/.X11-unix/X*; do
    [[ -S "${socket}" ]] || continue
    printf ':%s\n' "${socket##*X}"
    return 0
  done

  return 1
}

x11_access_check() {
  local display="$1"
  local xauthority="${2:-}"

  if ! command -v xset >/dev/null 2>&1; then
    return 2
  fi

  if [[ -n "${xauthority}" ]]; then
    DISPLAY="${display}" XAUTHORITY="${xauthority}" xset q >/dev/null 2>&1
  else
    DISPLAY="${display}" xset q >/dev/null 2>&1
  fi
}

find_working_hmi_xauthority() {
  local display="$1"
  local candidate
  local gdm_uid=""
  local current_uid=""
  local -a candidates=()
  local seen=":"

  if [[ -n "${APS_HMI_XAUTHORITY:-}" ]]; then
    candidates+=("${APS_HMI_XAUTHORITY}")
  fi
  if [[ -n "${XAUTHORITY:-}" ]]; then
    candidates+=("${XAUTHORITY}")
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    candidates+=("${XDG_RUNTIME_DIR}/gdm/Xauthority")
  fi
  if current_uid="$(id -u 2>/dev/null)"; then
    candidates+=("/run/user/${current_uid}/gdm/Xauthority")
  fi
  candidates+=("${HOME}/.Xauthority")

  if gdm_uid="$(id -u gdm 2>/dev/null)"; then
    candidates+=("/run/user/${gdm_uid}/gdm/Xauthority")
  fi

  for candidate in "${candidates[@]}"; do
    [[ -n "${candidate}" && -r "${candidate}" ]] || continue
    case "${seen}" in
      *":${candidate}:"*)
        continue
        ;;
    esac
    seen="${seen}${candidate}:"
    if x11_access_check "${display}" "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

find_gdm_xauthority() {
  local candidate
  local gdm_uid=""
  local current_uid=""
  local xorg_cmd=""

  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    candidate="${XDG_RUNTIME_DIR}/gdm/Xauthority"
    if [[ -r "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if current_uid="$(id -u 2>/dev/null)"; then
    candidate="/run/user/${current_uid}/gdm/Xauthority"
    if [[ -r "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if gdm_uid="$(id -u gdm 2>/dev/null)"; then
    candidate="/run/user/${gdm_uid}/gdm/Xauthority"
    if [[ -r "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  xorg_cmd="$(ps -u gdm -o args= 2>/dev/null | awk '/[X]org/ { print; exit }')"
  if [[ -n "${xorg_cmd}" ]]; then
    candidate="$(awk '{
      for (i = 1; i <= NF; ++i) {
        if ($i == "-auth" && (i + 1) <= NF) {
          print $(i + 1)
          exit
        }
      }
    }' <<< "${xorg_cmd}")"
    if [[ -n "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  return 1
}

grant_hmi_x11_access_via_gdm() {
  local display="$1"
  local current_user="${USER:-$(id -un)}"
  local gdm_auth=""

  command -v sudo >/dev/null 2>&1 || return 1
  command -v xhost >/dev/null 2>&1 || return 1

  gdm_auth="$(find_gdm_xauthority || true)"
  [[ -n "${gdm_auth}" ]] || return 1

  sudo -n -u gdm DISPLAY="${display}" XAUTHORITY="${gdm_auth}" \
    xhost "+SI:localuser:${current_user}" >/dev/null 2>&1
}

ensure_hmi_display_access() {
  local display=""
  local xauthority=""

  display="$(detect_hmi_display || true)"
  if [[ -z "${display}" ]]; then
    echo "[ERROR] no X11 display detected. Set APS_HMI_DISPLAY or DISPLAY, or log into the desktop session first." >&2
    return 1
  fi

  export DISPLAY="${display}"

  xauthority="$(find_working_hmi_xauthority "${display}" || true)"
  if [[ -n "${xauthority}" ]]; then
    export XAUTHORITY="${xauthority}"
    echo "[INFO] X11 ready on ${DISPLAY} (XAUTHORITY=${XAUTHORITY})"
    return 0
  fi

  unset XAUTHORITY || true
  if x11_access_check "${display}" ""; then
    echo "[INFO] X11 ready on ${DISPLAY}"
    return 0
  fi

  if grant_hmi_x11_access_via_gdm "${display}"; then
    unset XAUTHORITY || true
    if x11_access_check "${display}" ""; then
      echo "[INFO] X11 access granted on ${DISPLAY} via gdm xhost"
      return 0
    fi

    xauthority="$(find_working_hmi_xauthority "${display}" || true)"
    if [[ -n "${xauthority}" ]]; then
      export XAUTHORITY="${xauthority}"
      echo "[INFO] X11 access granted on ${DISPLAY} via gdm xhost"
      return 0
    fi
  fi

  echo "[ERROR] unable to access X11 display ${DISPLAY}. If you are starting HMI over SSH, set APS_HMI_DISPLAY/APS_HMI_XAUTHORITY or log into the desktop session first." >&2
  return 1
}
