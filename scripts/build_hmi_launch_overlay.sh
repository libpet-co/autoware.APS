#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${APS_ROOT_DIR:-$HOME/autoware.APS}"
LAUNCH_REPO="${APS_LAUNCH_REPO:-$ROOT_DIR/src/launcher/autoware_launch_APS}"
OVERLAY_WS="${APS_HMI_OVERLAY_WS:-$HOME/autoware.APS_hmi_overlay_ws}"
OVERLAY_SRC="${OVERLAY_WS}/src/autoware_launch_APS"
LAUNCH_REF="${APS_HMI_LAUNCH_REF:-origin/speed_test_hmi}"

if ! git -C "${LAUNCH_REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] launch repo not found: ${LAUNCH_REPO}" >&2
  exit 1
fi

mkdir -p "${OVERLAY_WS}/src" "${OVERLAY_WS}/build" "${OVERLAY_WS}/install" "${OVERLAY_WS}/log"

if [[ ! -e "${OVERLAY_SRC}/.git" ]]; then
  echo "[INFO] creating launch overlay worktree at ${OVERLAY_SRC}"
  git -C "${LAUNCH_REPO}" worktree add "${OVERLAY_SRC}" --detach "${LAUNCH_REF}"
fi

echo "[INFO] overlay source: ${OVERLAY_SRC}"
echo "[INFO] overlay ref: $(git -C "${OVERLAY_SRC}" rev-parse --short HEAD)"

set +u
source /opt/ros/humble/setup.bash
if [[ -f "${ROOT_DIR}/install/setup.bash" ]]; then
  source "${ROOT_DIR}/install/setup.bash"
fi
set -u

colcon --log-base "${OVERLAY_WS}/log" build \
  --base-paths "${OVERLAY_WS}/src" \
  --build-base "${OVERLAY_WS}/build" \
  --install-base "${OVERLAY_WS}/install" \
  --packages-select aps_hmi_container autoware_launch \
  --cmake-force-configure \
  --symlink-install \
  --allow-overriding autoware_launch \
  --cmake-args -DBUILD_TESTING=OFF

echo "[INFO] overlay build ready: ${OVERLAY_WS}/install/setup.bash"
