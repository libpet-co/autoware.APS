#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
HMI_TEST_ROOT="${APS_HMI_TEST_ROOT:-$HOME/hmi_test}"
LOG_DIR="${APS_HMI_LOG_DIR:-$HMI_TEST_ROOT/.log}"
ROS_DIR="${APS_HMI_ROS_DIR:-$HMI_TEST_ROOT/.ros}"
SETUP_ENV_CACHE="${APS_HMI_SETUP_ENV_CACHE:-$HMI_TEST_ROOT/.cache/autoware_setup_env.bash}"
USE_SETUP_ENV_CACHE="$(printf '%s' "${APS_HMI_USE_SETUP_ENV_CACHE:-true}" | tr '[:upper:]' '[:lower:]')"
CYCLONEDDS_CONFIG="${APS_CYCLONEDDS_CONFIG:-$HOME/cyclonedds.xml}"

AUTOWARE_USE_SIM_TIME="${APS_AUTOWARE_USE_SIM_TIME:-false}"
AUTOWARE_VEHICLE_MODEL="${APS_AUTOWARE_VEHICLE_MODEL:-aps_vehicle}"
AUTOWARE_POINTCLOUD_CONTAINER_NAME="${APS_AUTOWARE_POINTCLOUD_CONTAINER_NAME:-pointcloud_container}"
AUTOWARE_LOCALIZATION_POINTCLOUD_CONTAINER_NAME="${APS_AUTOWARE_LOCALIZATION_POINTCLOUD_CONTAINER_NAME:-/${AUTOWARE_POINTCLOUD_CONTAINER_NAME}}"
AUTOWARE_SYSTEM_RUN_MODE="${APS_AUTOWARE_SYSTEM_RUN_MODE:-online}"

mkdir -p "${LOG_DIR}" "${ROS_DIR}" "${ROS_DIR}/log"

if [[ ! -f "${ROOT_DIR}/install/setup.bash" ]]; then
  echo "[ERROR] missing main workspace setup: ${ROOT_DIR}/install/setup.bash" >&2
  exit 1
fi

set +u
source /opt/ros/humble/setup.bash
if [[ "${USE_SETUP_ENV_CACHE}" == "true" && -r "${SETUP_ENV_CACHE}" ]]; then
  source "${SETUP_ENV_CACHE}"
  setup_desc="cached env (${SETUP_ENV_CACHE})"
else
  source "${ROOT_DIR}/install/setup.bash"
  setup_desc="full setup (${ROOT_DIR}/install/setup.bash)"
fi
set -u

export ROS_HOME="${ROS_DIR}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
if [[ -z "${CYCLONEDDS_URI:-}" && -f "${CYCLONEDDS_CONFIG}" ]]; then
  export CYCLONEDDS_URI="file://${CYCLONEDDS_CONFIG}"
fi

echo "[INFO] APS localization prelaunch starting"
echo "[INFO] ROS setup env: ${setup_desc}"
echo "[INFO] ROS_HOME: ${ROS_HOME}"
echo "[INFO] vehicle_model: ${AUTOWARE_VEHICLE_MODEL}"
echo "[INFO] pointcloud_container_name: ${AUTOWARE_POINTCLOUD_CONTAINER_NAME}"
echo "[INFO] localization_pointcloud_container_name: ${AUTOWARE_LOCALIZATION_POINTCLOUD_CONTAINER_NAME}"
echo "[INFO] system_run_mode: ${AUTOWARE_SYSTEM_RUN_MODE}"

exec ros2 launch autoware_launch localization_prelaunch.launch.xml \
  "use_sim_time:=${AUTOWARE_USE_SIM_TIME}" \
  "vehicle_model:=${AUTOWARE_VEHICLE_MODEL}" \
  "pointcloud_container_name:=${AUTOWARE_POINTCLOUD_CONTAINER_NAME}" \
  "localization_pointcloud_container_name:=${AUTOWARE_LOCALIZATION_POINTCLOUD_CONTAINER_NAME}" \
  "system_run_mode:=${AUTOWARE_SYSTEM_RUN_MODE}"
