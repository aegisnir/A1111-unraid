#!/usr/bin/env bash
#
# start.sh - Container entrypoint for AUTOMATIC1111 Stable Diffusion WebUI
#
# Purpose:
#   Start the WebUI from within the container using configuration provided via
#   environment variables. This script includes basic sanity checks and clearer
#   error messages to help with troubleshooting.
#
# This project is maintained as a personal, AI-assisted learning project.
# The checks below are intended to catch obvious problems early, but they should
# not be read as proof that the runtime is secure, correct, or production-ready.
#
# Notes:
#   - This script does not attempt to configure networking, authentication,
#     or reverse proxy behavior. Those are deployment concerns and may vary by environment.
#   - If you change runtime flags (e.g., network exposure), the risk characteristics
#     of the deployment may not match the original intent of this repository.
#

set -euo pipefail

WEBUI_DIR="/opt/stable-diffusion-webui"
LOCAL_WEBUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/WebUI"
VENV_DIR="${A1111_VENV_DIR:-/data/venv}"
VENV_PYTHON="${VENV_DIR}/bin/python"
BOOTSTRAP_STAMP="${VENV_DIR}/.a1111-bootstrap-complete"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu121}"
export PIP_NO_BUILD_ISOLATION="${PIP_NO_BUILD_ISOLATION:-1}"

if [[ ! -d "${WEBUI_DIR}" && -d "${LOCAL_WEBUI_DIR}" ]]; then
  echo "Container WebUI directory not found; falling back to local workspace path: ${LOCAL_WEBUI_DIR}" >&2
  WEBUI_DIR="${LOCAL_WEBUI_DIR}"
fi

# Basic sanity checks to make failures easier to diagnose.
# These are here mostly to fail fast with clearer messages instead of producing
# a less helpful Python or file-not-found error later in startup.
if [[ ! -d "${WEBUI_DIR}" ]]; then
  echo "ERROR: Expected WebUI directory not found: ${WEBUI_DIR}" >&2
  echo "       The image build may have failed or WEBUI_DIR may be incorrect." >&2
  exit 1
fi

if [[ ! -f "${WEBUI_DIR}/launch.py" ]]; then
  echo "ERROR: launch.py not found in: ${WEBUI_DIR}" >&2
  echo "       The repository contents may be incomplete or not checked out as expected." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is not available in PATH." >&2
  echo "       The base image or dependency installation may be incomplete." >&2
  exit 1
fi

if [[ ! -d "/data" ]]; then
  echo "ERROR: Expected mapped data directory not found at /data" >&2
  echo "       Map /data to a writable host path before starting the container." >&2
  exit 1
fi

cd "${WEBUI_DIR}"

mkdir -p "${VENV_DIR}"

if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "Creating persistent Python virtual environment in ${VENV_DIR}" >&2
  python3 -m venv "${VENV_DIR}"
fi

if [[ ! -f "${BOOTSTRAP_STAMP}" ]]; then
  echo "Installing first-start Python dependencies (this may take a while)..." >&2
  "${VENV_PYTHON}" -m pip install --upgrade "pip<25" "setuptools<70" wheel
  "${VENV_PYTHON}" -m pip install --upgrade packaging requests regex tqdm ftfy
  "${VENV_PYTHON}" -m pip install \
    torch==2.1.2 \
    torchvision==0.16.2 \
    --extra-index-url "${TORCH_INDEX_URL}"
  touch "${BOOTSTRAP_STAMP}"
fi

# Optional: print a minimal startup banner (avoids echoing all args verbatim).
# This is intentionally conservative to reduce the chance of logging sensitive values
# if users pass secrets via COMMANDLINE_ARGS.
#
# Recommendation:
# Avoid placing secrets in COMMANDLINE_ARGS if at all possible. Command-line
# arguments are often easier to leak through logs, diagnostics, process lists,
# screenshots, or copy/paste mistakes than dedicated secret-management methods.
if [[ -n "${COMMANDLINE_ARGS:-}" ]]; then
  echo "Starting WebUI (COMMANDLINE_ARGS set)."
else
  echo "Starting WebUI (no COMMANDLINE_ARGS provided)."
fi

# Launch AUTOMATIC1111.
# - If COMMANDLINE_ARGS is unset, pass nothing.
# - If set, arguments are expanded as-is.
# - This script intentionally avoids trying to sanitize or validate every user-
#   supplied switch because that can become brittle and may create a false sense
#   of safety. Users should review the flags they pass and decide what is
#   appropriate for their own environment.
# - Recommended Unraid usage is to include: --data-dir /data
#   and map `/data` to a host path with plenty of space.
"${VENV_PYTHON}" launch.py ${COMMANDLINE_ARGS:-}

# Instructions to build and run the Docker container for AUTOMATIC1111.
# These commands should be run in the directory containing the Dockerfile.

# Build the Docker image
# docker build -t a1111-webui-aegisnir .

# Run the Docker container
# Replace <host_port> with the desired port on the host
# Replace <container_port> with the port exposed by the application (default is usually 7860)
# Default recommended host data path: /mnt/user/ai/data/
# docker run -d -p <host_port>:<container_port> -v /mnt/user/ai/data/:/data --name a1111-webui-aegisnir a1111-webui-aegisnir
