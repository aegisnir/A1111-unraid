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
#
# IMPORTANT: As of March 2026, new installs require the dev branch of AUTOMATIC1111 due to a missing dependency repository. The main branch will fail to start. See README for details.
#
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

# Set HOME for the non-root user to /data for consistent config/cache locations
export HOME=/data

# Use persistent temp storage in /data so large downloads (for example torch wheels)
# do not exhaust the container's limited writable temp space.
export TMPDIR=/data/tmp

# Use persistent pip cache in /data for faster rebuilds
export PIP_CACHE_DIR=/data/pip-cache

if [[ "$(id -u)" == "0" ]]; then
  echo "ERROR: Refusing to run as root. Please use a non-root user (UID 99 recommended for Unraid)." >&2
  exit 1
fi

WEBUI_DIR="/opt/stable-diffusion-webui"
LOCAL_WEBUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/WebUI"
VENV_DIR="${A1111_VENV_DIR:-/data/venv}"
VENV_PYTHON="${VENV_DIR}/bin/python"
BOOTSTRAP_STAMP="${VENV_DIR}/.a1111-bootstrap-complete"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu128}"
RUNTIME_REPOS_DIR="/data/repositories"
RUNTIME_CONFIG_STATES_DIR="/data/config_states"
MIN_BOOTSTRAP_FREE_MB="${MIN_BOOTSTRAP_FREE_MB:-8192}"
TORCH_VERSION="${TORCH_VERSION:-2.7.0}"
TORCHVISION_VERSION="${TORCHVISION_VERSION:-0.22.0}"
XFORMERS_VERSION="${XFORMERS_VERSION:-0.0.30}"
WEBUI_USERNAME="${WEBUI_USERNAME:-admin}"
WEBUI_PASSWORD="${WEBUI_PASSWORD:-changeme-now}"
WEBUI_AUTH_FILE="${WEBUI_AUTH_FILE:-}"
API_AUTH_MODE="${API_AUTH_MODE:-mirror-webui}"
API_AUTH_FILE_MODE="${API_AUTH_FILE_MODE:-mirror-webui-file}"
UMASK="${UMASK:-}"
export PIP_NO_BUILD_ISOLATION="${PIP_NO_BUILD_ISOLATION:-1}"

if [[ -n "${UMASK}" ]]; then
  if [[ ! "${UMASK}" =~ ^[0-7]{3,4}$ ]]; then
    echo "ERROR: UMASK must be a 3- or 4-digit octal value (for example 027 or 0027)." >&2
    exit 1
  fi
  umask "${UMASK}"
  echo "Using UMASK=${UMASK}" >&2
fi

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
mkdir -p "${RUNTIME_REPOS_DIR}"
mkdir -p "${RUNTIME_CONFIG_STATES_DIR}"
mkdir -p "${TMPDIR}"
mkdir -p "${PIP_CACHE_DIR}"

available_kb="$(df -Pk /data | awk 'NR==2 {print $4}')"
if [[ -z "${available_kb}" || ! "${available_kb}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Unable to determine free space for /data." >&2
  echo "       Verify that /data is mounted and writable before starting the container." >&2
  exit 1
fi

if [[ -e "${WEBUI_DIR}/config_states" && ! -L "${WEBUI_DIR}/config_states" ]]; then
  echo "ERROR: ${WEBUI_DIR}/config_states exists and is not a symlink." >&2
  echo "       On a read-only container filesystem, start.sh cannot replace it at runtime." >&2
  echo "       Rebuild the image without that path, or remove it before enabling --read-only." >&2
  exit 1
fi

if [[ -L "${WEBUI_DIR}/config_states" ]]; then
  existing_target="$(readlink "${WEBUI_DIR}/config_states")"
  if [[ "${existing_target}" != "${RUNTIME_CONFIG_STATES_DIR}" ]]; then
    echo "ERROR: ${WEBUI_DIR}/config_states points to ${existing_target}, expected ${RUNTIME_CONFIG_STATES_DIR}." >&2
    echo "       Rebuild the image so the config_states symlink matches the persistent runtime path." >&2
    exit 1
  fi
else
  echo "ERROR: ${WEBUI_DIR}/config_states symlink is missing." >&2
  echo "       This image now expects that symlink to be created at build time so startup works with --read-only." >&2
  exit 1
fi

available_mb="$(( available_kb / 1024 ))"
echo "Detected free space in /data: ${available_mb} MiB"

required_kb="$(( MIN_BOOTSTRAP_FREE_MB * 1024 ))"
if [[ ! -f "${BOOTSTRAP_STAMP}" && "${available_kb}" -lt "${required_kb}" ]]; then
  echo "ERROR: Not enough free space in /data for first-run dependency bootstrap." >&2
  echo "       Available: ${available_mb} MiB" >&2
  echo "       Recommended minimum: ${MIN_BOOTSTRAP_FREE_MB} MiB" >&2
  echo "       Torch, torchvision, xformers, and pip temp files can require several GB on first startup." >&2
  echo "       Free additional space in the mapped /data path, or set MIN_BOOTSTRAP_FREE_MB if you intentionally want a different threshold." >&2
  exit 1
fi

if [[ -e "${WEBUI_DIR}/repositories" && ! -L "${WEBUI_DIR}/repositories" ]]; then
  echo "ERROR: ${WEBUI_DIR}/repositories exists and is not a symlink." >&2
  echo "       On a read-only container filesystem, start.sh cannot replace it at runtime." >&2
  echo "       Rebuild the image with the symlink baked in, or remove that path before enabling --read-only." >&2
  exit 1
fi

if [[ -L "${WEBUI_DIR}/repositories" ]]; then
  existing_target="$(readlink "${WEBUI_DIR}/repositories")"
  if [[ "${existing_target}" != "${RUNTIME_REPOS_DIR}" ]]; then
    echo "ERROR: ${WEBUI_DIR}/repositories points to ${existing_target}, expected ${RUNTIME_REPOS_DIR}." >&2
    echo "       Rebuild the image so the repositories symlink matches the persistent runtime path." >&2
    exit 1
  fi
else
  echo "ERROR: ${WEBUI_DIR}/repositories symlink is missing." >&2
  echo "       This image now expects that symlink to be created at build time so startup works with --read-only." >&2
  exit 1
fi

if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "Creating persistent Python virtual environment in ${VENV_DIR}" >&2
  python3 -m venv "${VENV_DIR}"
fi

if [[ ! -f "${BOOTSTRAP_STAMP}" ]]; then
  echo "Installing first-start Python dependencies (this may take a while)..." >&2
  echo "Bootstrap dependency targets: torch=${TORCH_VERSION}, torchvision=${TORCHVISION_VERSION}, xformers=${XFORMERS_VERSION}" >&2
  # Upgrade pip to latest version
  "${VENV_PYTHON}" -m pip install --upgrade pip
  # Pin setuptools for compatibility, upgrade wheel
  "${VENV_PYTHON}" -m pip install --prefer-binary --upgrade "setuptools<70" wheel
  # Core dependencies
  "${VENV_PYTHON}" -m pip install --prefer-binary --upgrade packaging requests regex tqdm ftfy
  # Torch and torchvision
  "${VENV_PYTHON}" -m pip install --prefer-binary \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    --extra-index-url "${TORCH_INDEX_URL}"
  # Try to install xformers (optional, non-fatal if it fails).
  # Pin to a version compatible with the torch/torchvision versions above so pip
  # does not upgrade torch to an incompatible release.
  if ! "${VENV_PYTHON}" -m pip install --prefer-binary "xformers==${XFORMERS_VERSION}"; then
    echo "[WARNING] xformers install failed for version ${XFORMERS_VERSION}. WebUI will run without it."
  fi
  "${VENV_PYTHON}" - <<'PY'
import importlib

packages = ["torch", "torchvision", "xformers"]
versions = []

for name in packages:
    try:
        module = importlib.import_module(name)
        versions.append(f"{name}={getattr(module, '__version__', 'unknown')}")
    except Exception:
        versions.append(f"{name}=not-installed")

print("Installed dependency versions: " + ", ".join(versions))
PY
  touch "${BOOTSTRAP_STAMP}"
fi

if ! TORCH_VERSION="${TORCH_VERSION}" TORCHVISION_VERSION="${TORCHVISION_VERSION}" XFORMERS_VERSION="${XFORMERS_VERSION}" "${VENV_PYTHON}" - <<'PY'
import importlib
import os
import sys

def normalize_version(version: str) -> str:
  return version.split("+", 1)[0]

expected = {
  "torch": os.environ["TORCH_VERSION"],
  "torchvision": os.environ["TORCHVISION_VERSION"],
  "xformers": os.environ["XFORMERS_VERSION"],
}

installed = {}
errors = []

for name, expected_version in expected.items():
  try:
    module = importlib.import_module(name)
    installed_version = getattr(module, "__version__", "unknown")
    installed[name] = installed_version
    if normalize_version(installed_version) != normalize_version(expected_version):
      errors.append(f"{name}: expected {expected_version}, found {installed_version}")
  except Exception as exc:
    errors.append(f"{name}: not importable ({exc.__class__.__name__})")

print("Dependency sanity check: " + ", ".join(f"{name}={installed.get(name, 'missing')}" for name in expected))

if errors:
  print("Dependency version mismatch detected:", file=sys.stderr)
  for error in errors:
    print(f" - {error}", file=sys.stderr)
  sys.exit(1)
PY
then
  echo "ERROR: Installed dependency versions do not match the configured bootstrap pins." >&2
  echo "       Remove ${VENV_DIR} and retry so the container can rebuild a clean environment." >&2
  exit 1
fi

AUTH_ARGS=()
USING_WEBUI_AUTH_FILE=0

if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth([=[:space:]]|$) ]]; then
  echo "WebUI authentication is being managed via COMMANDLINE_ARGS." >&2
elif [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth-path([=[:space:]]|$) ]]; then
  echo "WebUI authentication file is being managed via COMMANDLINE_ARGS." >&2
elif [[ -n "${WEBUI_AUTH_FILE}" ]]; then
  if [[ ! -f "${WEBUI_AUTH_FILE}" ]]; then
    echo "ERROR: WEBUI_AUTH_FILE is set but the file does not exist: ${WEBUI_AUTH_FILE}" >&2
    exit 1
  fi
  if [[ ! -s "${WEBUI_AUTH_FILE}" ]]; then
    echo "ERROR: WEBUI_AUTH_FILE is set but the file is empty: ${WEBUI_AUTH_FILE}" >&2
    exit 1
  fi
  AUTH_ARGS+=("--gradio-auth-path" "${WEBUI_AUTH_FILE}")
  USING_WEBUI_AUTH_FILE=1
  echo "WebUI authentication file is enabled via WEBUI_AUTH_FILE." >&2
else
  if [[ "${WEBUI_PASSWORD}" == "changeme-now" ]]; then
    echo "ERROR: WEBUI_PASSWORD is still set to the insecure default value." >&2
    echo "       Set WEBUI_PASSWORD to a unique password before starting the container." >&2
    echo "       Alternatively, manage authentication explicitly with --gradio-auth, --gradio-auth-path, or WEBUI_AUTH_FILE." >&2
    exit 1
  fi
  AUTH_ARGS+=("--gradio-auth" "${WEBUI_USERNAME}:${WEBUI_PASSWORD}")
  echo "WebUI login is enabled by default. Username: ${WEBUI_USERNAME}" >&2
fi

if [[ "${USING_WEBUI_AUTH_FILE}" == "1" ]]; then
  if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
    echo "API authentication is being managed via COMMANDLINE_ARGS." >&2
  elif [[ "${API_AUTH_FILE_MODE}" == "mirror-webui-file" ]]; then
    api_auth_value="$(python3 - <<'PY' "${WEBUI_AUTH_FILE}"
import sys
from pathlib import Path

path = Path(sys.argv[1])
entries = []

for raw_line in path.read_text(encoding='utf-8').splitlines():
    line = raw_line.strip()
    if not line or line.startswith('#'):
        continue
    for cred in line.split(','):
        cred = cred.strip()
        if cred:
            entries.append(cred)

print(','.join(entries))
PY
)"
    if [[ -z "${api_auth_value}" ]]; then
      echo "ERROR: WEBUI_AUTH_FILE is set but no usable credentials were found in ${WEBUI_AUTH_FILE}" >&2
      exit 1
    fi
    AUTH_ARGS+=("--api-auth" "${api_auth_value}")
    echo "API authentication is mirrored from WEBUI_AUTH_FILE." >&2
  elif [[ "${API_AUTH_FILE_MODE}" == "disabled" ]]; then
    echo "API auth mirroring from WEBUI_AUTH_FILE disabled via API_AUTH_FILE_MODE=disabled." >&2
  else
    echo "WARNING: Unrecognized API_AUTH_FILE_MODE=${API_AUTH_FILE_MODE}. Expected mirror-webui-file or disabled. Falling back to mirror-webui-file." >&2
    api_auth_value="$(python3 - <<'PY' "${WEBUI_AUTH_FILE}"
import sys
from pathlib import Path

path = Path(sys.argv[1])
entries = []

for raw_line in path.read_text(encoding='utf-8').splitlines():
    line = raw_line.strip()
    if not line or line.startswith('#'):
        continue
    for cred in line.split(','):
        cred = cred.strip()
        if cred:
            entries.append(cred)

print(','.join(entries))
PY
)"
    if [[ -z "${api_auth_value}" ]]; then
      echo "ERROR: WEBUI_AUTH_FILE is set but no usable credentials were found in ${WEBUI_AUTH_FILE}" >&2
      exit 1
    fi
    AUTH_ARGS+=("--api-auth" "${api_auth_value}")
    echo "API authentication is mirrored from WEBUI_AUTH_FILE." >&2
  fi
elif [[ "${API_AUTH_MODE}" == "mirror-webui" ]]; then
  if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
    echo "API authentication is being managed via COMMANDLINE_ARGS." >&2
  else
    AUTH_ARGS+=("--api-auth" "${WEBUI_USERNAME}:${WEBUI_PASSWORD}")
  fi
elif [[ "${API_AUTH_MODE}" == "disabled" ]]; then
  echo "API authentication mirroring disabled via API_AUTH_MODE=disabled." >&2
else
  echo "WARNING: Unrecognized API_AUTH_MODE=${API_AUTH_MODE}. Expected mirror-webui or disabled. Falling back to mirror-webui." >&2
  if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
    echo "API authentication is being managed via COMMANDLINE_ARGS." >&2
  else
    AUTH_ARGS+=("--api-auth" "${WEBUI_USERNAME}:${WEBUI_PASSWORD}")
  fi
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
if [[ ${#AUTH_ARGS[@]} -gt 0 ]]; then
  quoted_auth_args=()
  for arg in "${AUTH_ARGS[@]}"; do
    quoted_auth_args+=("$(printf '%q' "${arg}")")
  done
  export COMMANDLINE_ARGS="${COMMANDLINE_ARGS:-} ${quoted_auth_args[*]}"
fi

"${VENV_PYTHON}" launch.py

# Instructions to build and run the Docker container for AUTOMATIC1111.
# These commands should be run in the directory containing the Dockerfile.

# Build the Docker image
# docker build -t a1111-webui-aegisnir .

# Run the Docker container
# Replace <host_port> with the desired port on the host
# Replace <container_port> with the port exposed by the application (default is usually 7860)
# Default recommended host data path: /mnt/user/ai/data/
# docker run -d -p <host_port>:<container_port> -v /mnt/user/ai/data/:/data --name a1111-webui-aegisnir a1111-webui-aegisnir
