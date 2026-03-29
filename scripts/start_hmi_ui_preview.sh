#!/usr/bin/env bash
set -euo pipefail

UI_REPO="${APS_UI_REPO:-$HOME/APS_Frontend_Backend/APS_management_system_ui}"
PREVIEW_DIR="${APS_UI_PREVIEW_DIR:-${UI_REPO}_hmi_preview}"
UI_REF="${APS_UI_REF:-origin/fw/hmi-ui}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-3000}"

if ! git -C "${UI_REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] APS frontend repo not found: ${UI_REPO}" >&2
  exit 1
fi

if [[ ! -e "${PREVIEW_DIR}/.git" ]]; then
  echo "[INFO] creating HMI preview worktree at ${PREVIEW_DIR}"
  git -C "${UI_REPO}" worktree add "${PREVIEW_DIR}" --detach "${UI_REF}"
fi

if [[ ! -e "${PREVIEW_DIR}/.env.local" && -f "${UI_REPO}/.env.local" ]]; then
  ln -s "${UI_REPO}/.env.local" "${PREVIEW_DIR}/.env.local"
fi

if [[ ! -e "${PREVIEW_DIR}/node_modules" ]]; then
  if [[ -d "${UI_REPO}/node_modules" ]]; then
    ln -s "${UI_REPO}/node_modules" "${PREVIEW_DIR}/node_modules"
  else
    echo "[INFO] installing frontend dependencies into preview worktree"
    (cd "${PREVIEW_DIR}" && npm ci)
  fi
fi

echo "[INFO] preview worktree: ${PREVIEW_DIR}"
echo "[INFO] preview ref: $(git -C "${PREVIEW_DIR}" rev-parse --short HEAD)"
echo "[INFO] open: http://${HOST}:${PORT}/aps/welcome"

cd "${PREVIEW_DIR}"

# Turbopack panics in this detached worktree on this machine; plain next dev is stable.
NEXT_TELEMETRY_DISABLED=1 ./node_modules/.bin/next dev --hostname "${HOST}" --port "${PORT}"
