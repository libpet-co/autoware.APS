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
AUTOWARE_SENSOR_MODEL="${APS_AUTOWARE_SENSOR_MODEL:-aps_sensor_kit}"
AUTOWARE_SENSOR_CONFIG_PROFILE="${APS_AUTOWARE_SENSOR_CONFIG_PROFILE:-aps998}"

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

vehicle_launch_share="$(ros2 pkg prefix tier4_vehicle_launch)/share/tier4_vehicle_launch"
sensor_description_share="$(ros2 pkg prefix "${AUTOWARE_SENSOR_MODEL}_description")/share/${AUTOWARE_SENSOR_MODEL}_description"
model_file="${vehicle_launch_share}/urdf/vehicle.xacro"
config_dir="${sensor_description_share}/config/${AUTOWARE_SENSOR_CONFIG_PROFILE}"
runtime_dir="${HMI_TEST_ROOT}/.cache/robot_description"
urdf_file="${runtime_dir}/robot_description_${AUTOWARE_SENSOR_CONFIG_PROFILE}.urdf"
mkdir -p "${runtime_dir}"

echo "[INFO] APS robot description prelaunch starting"
echo "[INFO] ROS setup env: ${setup_desc}"
echo "[INFO] ROS_HOME: ${ROS_HOME}"
echo "[INFO] vehicle_model: ${AUTOWARE_VEHICLE_MODEL}"
echo "[INFO] sensor_model: ${AUTOWARE_SENSOR_MODEL}"
echo "[INFO] sensor_config_profile: ${AUTOWARE_SENSOR_CONFIG_PROFILE}"
echo "[INFO] model_file: ${model_file}"
echo "[INFO] config_dir: ${config_dir}"

for required in "${model_file}" "${config_dir}"; do
  if [[ ! -e "${required}" ]]; then
    echo "[ERROR] missing robot description input: ${required}" >&2
    exit 1
  fi
done

xacro "${model_file}" \
  "vehicle_model:=${AUTOWARE_VEHICLE_MODEL}" \
  "sensor_model:=${AUTOWARE_SENSOR_MODEL}" \
  "config_dir:=${config_dir}" \
  > "${urdf_file}"

echo "[INFO] generated URDF: ${urdf_file} ($(stat -c '%s' "${urdf_file}") bytes)"

exec ros2 run robot_state_publisher robot_state_publisher "${urdf_file}" \
  --ros-args \
  -r __node:=aps_robot_description_prelaunch \
  -p "use_sim_time:=${AUTOWARE_USE_SIM_TIME}"
