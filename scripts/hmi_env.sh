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
