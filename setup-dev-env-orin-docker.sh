#!/usr/bin/env bash
# Helper wrapper for Jetson Orin hosts that already have Docker and NVIDIA toolkits installed.
# Skips the Docker-engine and NVIDIA-container-toolkit Ansible roles while delegating to setup-dev-env.sh.

set -e

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")

# Ensure the skip tags are set, but allow callers to override if they explicitly export the env var.
export ANSIBLE_SKIP_TAGS=${ANSIBLE_SKIP_TAGS:-"docker_engine,nvidia_container_toolkit"}

# Always target the docker playbook and skip driver/toolkit re-installation; forward any extra args.
exec "$SCRIPT_DIR/setup-dev-env.sh" docker --no-nvidia --no-cuda-drivers "$@"
