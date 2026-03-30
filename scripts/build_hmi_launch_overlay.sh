#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
if [[ ! -d "${ROOT_DIR}" ]]; then
  echo "[ERROR] main workspace not found: ${ROOT_DIR}" >&2
  exit 1
fi

echo "[WARN] build_hmi_launch_overlay.sh is deprecated."
echo "[WARN] Building HMI artifacts in the main workspace instead: ${ROOT_DIR}"

set +u
source /opt/ros/humble/setup.bash
if [[ -f "${ROOT_DIR}/install/setup.bash" ]]; then
  source "${ROOT_DIR}/install/setup.bash"
fi
set -u

colcon --log-base "${ROOT_DIR}/log" build \
  --packages-select aps_hmi_container autoware_launch \
  --cmake-force-configure \
  --symlink-install \
  --allow-overriding autoware_launch \
  --cmake-args -DBUILD_TESTING=OFF

echo "[INFO] main workspace build ready: ${ROOT_DIR}/install/setup.bash"
