#!/usr/bin/env bash
#
# start.sh - Container entrypoint for AUTOMATIC1111 Stable Diffusion Web UI
#
# This script launches the web UI using configuration supplied via
# environment variables. It is designed to fail fast with clear errors.
#
# Environment variables:
#   COMMANDLINE_ARGS  - Optional arguments passed to launch.py
#
set -euo pipefail

WEBUI_DIR="/opt/stable-diffusion-webui"

# Fail fast if the expected directory does not exist.
if [[ ! -d "${WEBUI_DIR}" ]]; then
  echo "ERROR: Stable Diffusion WebUI directory not found: ${WEBUI_DIR}" >&2
  exit 1
fi

cd "${WEBUI_DIR}"

# Launch AUTOMATIC1111.
# If COMMANDLINE_ARGS is unset, no arguments are passed.
python3 launch.py ${COMMANDLINE_ARGS:-}
