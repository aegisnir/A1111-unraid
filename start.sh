#!/usr/bin/env bash
#
# start.sh - Container entrypoint for AUTOMATIC1111 Stable Diffusion WebUI
#
# Purpose:
#   Start the WebUI from within the container using configuration provided via
#   environment variables. This script includes basic sanity checks and clearer
#   error messages to help with troubleshooting.
#
# Notes:
#   - This script does not attempt to configure networking, authentication,
#     or reverse proxy behavior. Those are deployment concerns and may vary by environment.
#   - If you change runtime flags (e.g., network exposure), the risk characteristics
#     of the deployment may not match the original intent of this repository.
#

set -euo pipefail

WEBUI_DIR="/opt/stable-diffusion-webui"

# Basic sanity checks to make failures easier to diagnose.
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

cd "${WEBUI_DIR}"

# Optional: print a minimal startup banner (avoids echoing all args verbatim).
# This is intentionally conservative to reduce the chance of logging sensitive values
# if users pass secrets via COMMANDLINE_ARGS (not recommended).
if [[ -n "${COMMANDLINE_ARGS:-}" ]]; then
  echo "Starting WebUI (COMMANDLINE_ARGS set)."
else
  echo "Starting WebUI (no COMMANDLINE_ARGS provided)."
fi

# Launch AUTOMATIC1111.
# - If COMMANDLINE_ARGS is unset, pass nothing.
# - If set, arguments are expanded as-is.
python3 launch.py ${COMMANDLINE_ARGS:-}
