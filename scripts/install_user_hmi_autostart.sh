#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="${SCRIPT_DIR}/autostart"

TARGET_AUTOSTART_DIR="${HOME}/.config/autostart"
TARGET_SYSTEMD_DIR="${HOME}/.config/systemd/user"
TARGET_DROPIN_DIR="${TARGET_SYSTEMD_DIR}/aps-local-hmi-stack.service.d"
TARGET_BIN_DIR="${HOME}/bin"

KEEP_LEGACY_AUTOSTART="false"
BACKUP_DIR=""

usage() {
  cat <<'EOF'
Usage:
  install_user_hmi_autostart.sh [--keep-legacy-autostart]

Purpose:
  Install the APS local HMI GNOME autostart entry, wrapper script, and
  `aps-local-hmi-stack.service` user unit for the current user.

Options:
  --keep-legacy-autostart   Keep legacy desktop entries such as
                            `start_autoware_aps.sh.desktop` and
                            `APS_UI_Management.sh.desktop`
EOF
}

ensure_backup_dir() {
  if [[ -n "${BACKUP_DIR}" ]]; then
    return 0
  fi
  BACKUP_DIR="${HOME}/autostart_migration_backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "${BACKUP_DIR}"
}

backup_if_exists() {
  local path="$1"

  if [[ ! -e "${path}" ]]; then
    return 0
  fi

  ensure_backup_dir
  cp -a "${path}" "${BACKUP_DIR}/"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-legacy-autostart)
      KEEP_LEGACY_AUTOSTART="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for required in \
  "${ASSET_DIR}/start_local_hmi_stack_fast.sh.desktop" \
  "${ASSET_DIR}/start_local_hmi_stack_fast_autostart.sh" \
  "${ASSET_DIR}/aps-local-hmi-stack.service" \
  "${ASSET_DIR}/aps-local-hmi-stack.service.d/cpu-tuning.conf"; do
  if [[ ! -f "${required}" ]]; then
    echo "[ERROR] missing asset: ${required}" >&2
    exit 1
  fi
done

mkdir -p \
  "${TARGET_AUTOSTART_DIR}" \
  "${TARGET_SYSTEMD_DIR}" \
  "${TARGET_DROPIN_DIR}" \
  "${TARGET_BIN_DIR}"

backup_if_exists "${TARGET_AUTOSTART_DIR}/start_local_hmi_stack_fast.sh.desktop"
backup_if_exists "${TARGET_BIN_DIR}/start_local_hmi_stack_fast_autostart.sh"
backup_if_exists "${TARGET_SYSTEMD_DIR}/aps-local-hmi-stack.service"
backup_if_exists "${TARGET_DROPIN_DIR}/cpu-tuning.conf"

install -m 0644 \
  "${ASSET_DIR}/start_local_hmi_stack_fast.sh.desktop" \
  "${TARGET_AUTOSTART_DIR}/start_local_hmi_stack_fast.sh.desktop"
install -m 0755 \
  "${ASSET_DIR}/start_local_hmi_stack_fast_autostart.sh" \
  "${TARGET_BIN_DIR}/start_local_hmi_stack_fast_autostart.sh"
install -m 0644 \
  "${ASSET_DIR}/aps-local-hmi-stack.service" \
  "${TARGET_SYSTEMD_DIR}/aps-local-hmi-stack.service"
install -m 0644 \
  "${ASSET_DIR}/aps-local-hmi-stack.service.d/cpu-tuning.conf" \
  "${TARGET_DROPIN_DIR}/cpu-tuning.conf"

if [[ "${KEEP_LEGACY_AUTOSTART}" != "true" ]]; then
  backup_if_exists "${TARGET_AUTOSTART_DIR}/start_autoware_aps.sh.desktop"
  backup_if_exists "${TARGET_AUTOSTART_DIR}/APS_UI_Management.sh.desktop"
  rm -f \
    "${TARGET_AUTOSTART_DIR}/start_autoware_aps.sh.desktop" \
    "${TARGET_AUTOSTART_DIR}/APS_UI_Management.sh.desktop"
fi

systemctl --user daemon-reload

echo "[INFO] installed APS local HMI autostart assets."
echo "[INFO] desktop: ${TARGET_AUTOSTART_DIR}/start_local_hmi_stack_fast.sh.desktop"
echo "[INFO] wrapper: ${TARGET_BIN_DIR}/start_local_hmi_stack_fast_autostart.sh"
echo "[INFO] user unit: ${TARGET_SYSTEMD_DIR}/aps-local-hmi-stack.service"
echo "[INFO] drop-in: ${TARGET_DROPIN_DIR}/cpu-tuning.conf"
if [[ -n "${BACKUP_DIR}" ]]; then
  echo "[INFO] backup dir: ${BACKUP_DIR}"
fi
echo "[INFO] test now with: ${TARGET_BIN_DIR}/start_local_hmi_stack_fast_autostart.sh"
