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

# ── Color palette ────────────────────────────────────────────────────────────
# C_INFO   (violet)  → informational / status messages
# C_WARN   (orange)  → caution / warnings that need attention but are not fatal
# C_CRIT   (scarlet) → critical errors requiring user action
# C_ACCENT (cyan)    → accent / highlights (URLs, commands, structural chrome)
# Colors are enabled by default because Docker/Unraid log viewers render ANSI.
# Set NO_COLOR=1 or TERM=dumb in the container environment to suppress them.
if [[ "${NO_COLOR:-}" == "" && "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_ACCENT=$'\e[96m'
  C_INFO=$'\e[35m'; C_WARN=$'\e[93m'; C_CRIT=$'\e[91m'
else
  C_RESET='' C_BOLD='' C_ACCENT='' C_INFO='' C_WARN='' C_CRIT=''
fi

# Set HOME for the non-root user to /data for consistent config/cache locations
export HOME=/data

# Use persistent temp storage in /data so large downloads (for example torch wheels)
# do not exhaust the container's limited writable temp space.
export TMPDIR=/data/tmp

# Use persistent pip cache in /data for faster rebuilds
export PIP_CACHE_DIR=/data/pip-cache

if [[ "$(id -u)" == "0" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Refusing to run as root. Please use a non-root user (UID 99 recommended for Unraid).${C_RESET}" >&2
  exit 1
fi

# ── Paths & version pins ─────────────────────────────────────────────────────
# These defaults are designed for the Docker image layout. Override via env vars
# if testing locally or using a non-standard data volume path.

WEBUI_DIR="/opt/stable-diffusion-webui"                            # A1111 source, cloned at image build time
LOCAL_WEBUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/WebUI"  # Fallback for local (non-Docker) development
VENV_DIR="${A1111_VENV_DIR:-/data/venv}"                           # Persistent Python venv, survives container recreation
VENV_PYTHON="${VENV_DIR}/bin/python"                               # Absolute path to the venv interpreter
BOOTSTRAP_STAMP="${VENV_DIR}/.a1111-bootstrap-complete"            # Marker file: first-run pip install already done
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu128}"  # PyPI extra index for CUDA wheels
RUNTIME_REPOS_DIR="/data/repositories"                             # Persistent upstream sub-repos (e.g. k-diffusion)
RUNTIME_CONFIG_STATES_DIR="/data/config_states"                    # Persistent extension state snapshots
MIN_BOOTSTRAP_FREE_MB="${MIN_BOOTSTRAP_FREE_MB:-8192}"             # Abort first-run if /data has less than this free
TORCH_VERSION="${TORCH_VERSION:-2.7.0}"                            # Pinned version — update alongside CUDA base image
TORCHVISION_VERSION="${TORCHVISION_VERSION:-0.22.0}"
XFORMERS_VERSION="${XFORMERS_VERSION:-0.0.30}"

# ── Authentication paths ─────────────────────────────────────────────────────
# The user-facing auth file (WEBUI_AUTH_FILE) can contain comments and blank
# lines for readability. The runtime copy (WEBUI_AUTH_RUNTIME_FILE) is a
# sanitized version with only username:password lines that Gradio can parse.
WEBUI_AUTH_FILE_DEFAULT="/config/auth/webui-auth.txt"
WEBUI_AUTH_FILE="${WEBUI_AUTH_FILE:-${WEBUI_AUTH_FILE_DEFAULT}}"
WEBUI_AUTH_RUNTIME_FILE="/config/auth/.webui-auth.runtime.txt"

# mirror-webui-file = copy WebUI credentials to --api-auth when --api is enabled
# disabled        = do not auto-set --api-auth; user manages it manually
API_AUTH_FILE_MODE="${API_AUTH_FILE_MODE:-mirror-webui-file}"

UMASK="${UMASK:-}"                                                 # Optional: override default umask for all file creation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_AUTH_SAMPLE_FILE="${SCRIPT_DIR}/webui-auth.txt"              # Bundled sample; copied to /data on first launch
export PIP_NO_BUILD_ISOLATION="${PIP_NO_BUILD_ISOLATION:-1}"       # Required by some A1111 dependency builds

if [[ -n "${UMASK}" ]]; then
  if [[ ! "${UMASK}" =~ ^[0-7]{3,4}$ ]]; then
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} UMASK must be a 3- or 4-digit octal value (for example 027 or 0027).${C_RESET}" >&2
    exit 1
  fi
  umask "${UMASK}"
  echo "${C_ACCENT}Using UMASK=${UMASK}${C_RESET}" >&2
fi

if [[ ! -d "${WEBUI_DIR}" && -d "${LOCAL_WEBUI_DIR}" ]]; then
  echo "${C_WARN}Container WebUI directory not found; falling back to local workspace path: ${LOCAL_WEBUI_DIR}${C_RESET}" >&2
  WEBUI_DIR="${LOCAL_WEBUI_DIR}"
fi

# Basic sanity checks to make failures easier to diagnose.
# These are here mostly to fail fast with clearer messages instead of producing
# a less helpful Python or file-not-found error later in startup.
if [[ ! -d "${WEBUI_DIR}" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Expected WebUI directory not found: ${WEBUI_DIR}${C_RESET}" >&2
  echo "${C_CRIT}       The image build may have failed or WEBUI_DIR may be incorrect.${C_RESET}" >&2
  exit 1
fi

if [[ ! -f "${WEBUI_DIR}/launch.py" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} launch.py not found in: ${WEBUI_DIR}${C_RESET}" >&2
  echo "${C_CRIT}       The repository contents may be incomplete or not checked out as expected.${C_RESET}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} python3 is not available in PATH.${C_RESET}" >&2
  echo "${C_CRIT}       The base image or dependency installation may be incomplete.${C_RESET}" >&2
  exit 1
fi

if [[ ! -d "/data" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Expected mapped data directory not found at /data${C_RESET}" >&2
  echo "${C_CRIT}       Map /data to a writable host path before starting the container.${C_RESET}" >&2
  exit 1
fi

if [[ ! -w "/data" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} /data exists but is not writable by the current user (uid=$(id -u)).${C_RESET}" >&2
  echo "${C_CRIT}       The container entrypoint attempted to correct this automatically but could not.${C_RESET}" >&2
  echo "${C_CRIT}       This can happen with NFS root squash, unusual host permissions, or SELinux policies.${C_RESET}" >&2
  echo "" >&2
  echo "${C_WARN}       To fix manually, run the following on the Unraid host (as root) and then restart${C_RESET}" >&2
  echo "${C_WARN}       the container (adjust the path to match your container template's /data bind-mount):${C_RESET}" >&2
  echo "" >&2
  echo "${C_ACCENT}         chown nobody:users <your-data-path>${C_RESET}" >&2
  echo "${C_ACCENT}         chmod 775 <your-data-path>${C_RESET}" >&2
  echo "" >&2
  echo "${C_WARN}       Adjust the path above if your Unraid share path is different.${C_RESET}" >&2
  exit 1
fi

cd "${WEBUI_DIR}"

mkdir -p "${VENV_DIR}"
mkdir -p "${RUNTIME_REPOS_DIR}"
mkdir -p "${RUNTIME_CONFIG_STATES_DIR}"
mkdir -p "${TMPDIR}"
mkdir -p "${PIP_CACHE_DIR}"
# Ensure standard data subtrees exist so the WebUI finds expected paths on a
# fresh or restored /data volume without requiring the user to re-create them.
mkdir -p /data/models/Stable-diffusion
mkdir -p /data/models/VAE
mkdir -p /data/models/Lora
mkdir -p /data/outputs
mkdir -p /config/auth

available_kb="$(df -Pk /data | awk 'NR==2 {print $4}')"
if [[ -z "${available_kb}" || ! "${available_kb}" =~ ^[0-9]+$ ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Unable to determine free space for /data.${C_RESET}" >&2
  echo "${C_CRIT}       Verify that /data is mounted and writable before starting the container.${C_RESET}" >&2
  exit 1
fi

if [[ -e "${WEBUI_DIR}/config_states" && ! -L "${WEBUI_DIR}/config_states" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${WEBUI_DIR}/config_states exists and is not a symlink.${C_RESET}" >&2
  echo "${C_CRIT}       On a read-only container filesystem, start.sh cannot replace it at runtime.${C_RESET}" >&2
  echo "${C_WARN}       Rebuild the image without that path, or remove it before enabling --read-only.${C_RESET}" >&2
  exit 1
fi

if [[ -L "${WEBUI_DIR}/config_states" ]]; then
  existing_target="$(readlink "${WEBUI_DIR}/config_states")"
  if [[ "${existing_target}" != "${RUNTIME_CONFIG_STATES_DIR}" ]]; then
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${WEBUI_DIR}/config_states points to ${existing_target}, expected ${RUNTIME_CONFIG_STATES_DIR}.${C_RESET}" >&2
    echo "${C_WARN}       Rebuild the image so the config_states symlink matches the persistent runtime path.${C_RESET}" >&2
    exit 1
  fi
else
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${WEBUI_DIR}/config_states symlink is missing.${C_RESET}" >&2
  echo "${C_WARN}       This image now expects that symlink to be created at build time so startup works with --read-only.${C_RESET}" >&2
  exit 1
fi

available_mb="$(( available_kb / 1024 ))"
echo "${C_ACCENT}Detected free space in /data: ${available_mb} MiB${C_RESET}"

required_kb="$(( MIN_BOOTSTRAP_FREE_MB * 1024 ))"
if [[ ! -f "${BOOTSTRAP_STAMP}" && "${available_kb}" -lt "${required_kb}" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Not enough free space in /data for first-run dependency bootstrap.${C_RESET}" >&2
  echo "${C_CRIT}       Available: ${available_mb} MiB${C_RESET}" >&2
  echo "${C_CRIT}       Recommended minimum: ${MIN_BOOTSTRAP_FREE_MB} MiB${C_RESET}" >&2
  echo "${C_WARN}       Torch, torchvision, xformers, and pip temp files can require several GB on first startup.${C_RESET}" >&2
  echo "${C_WARN}       Free additional space in the mapped /data path, or set MIN_BOOTSTRAP_FREE_MB if you intentionally want a different threshold.${C_RESET}" >&2
  exit 1
fi

if [[ -e "${WEBUI_DIR}/repositories" && ! -L "${WEBUI_DIR}/repositories" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${WEBUI_DIR}/repositories exists and is not a symlink.${C_RESET}" >&2
  echo "${C_CRIT}       On a read-only container filesystem, start.sh cannot replace it at runtime.${C_RESET}" >&2
  echo "${C_WARN}       Rebuild the image with the symlink baked in, or remove that path before enabling --read-only.${C_RESET}" >&2
  exit 1
fi

if [[ -L "${WEBUI_DIR}/repositories" ]]; then
  existing_target="$(readlink "${WEBUI_DIR}/repositories")"
  if [[ "${existing_target}" != "${RUNTIME_REPOS_DIR}" ]]; then
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${WEBUI_DIR}/repositories points to ${existing_target}, expected ${RUNTIME_REPOS_DIR}.${C_RESET}" >&2
    echo "${C_WARN}       Rebuild the image so the repositories symlink matches the persistent runtime path.${C_RESET}" >&2
    exit 1
  fi
else
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${WEBUI_DIR}/repositories symlink is missing.${C_RESET}" >&2
  echo "${C_WARN}       This image now expects that symlink to be created at build time so startup works with --read-only.${C_RESET}" >&2
  exit 1
fi

if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "${C_INFO}Creating persistent Python virtual environment in ${VENV_DIR}${C_RESET}" >&2
  python3 -m venv "${VENV_DIR}"
fi

if [[ ! -f "${BOOTSTRAP_STAMP}" ]]; then
  echo "${C_WARN}Installing first-start Python dependencies (this may take a while)...${C_RESET}" >&2
  echo "${C_ACCENT}Bootstrap dependency targets: torch=${TORCH_VERSION}, torchvision=${TORCHVISION_VERSION}, xformers=${XFORMERS_VERSION}${C_RESET}" >&2
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

required_expected = {
  "torch": os.environ["TORCH_VERSION"],
  "torchvision": os.environ["TORCHVISION_VERSION"],
}
optional_expected = {
  "xformers": os.environ["XFORMERS_VERSION"],
}

installed = {}
errors = []
warnings = []

for name, expected_version in required_expected.items():
  try:
    module = importlib.import_module(name)
    installed_version = getattr(module, "__version__", "unknown")
    installed[name] = installed_version
    if normalize_version(installed_version) != normalize_version(expected_version):
      errors.append(f"{name}: expected {expected_version}, found {installed_version}")
  except Exception as exc:
    errors.append(f"{name}: not importable ({exc.__class__.__name__})")

for name, expected_version in optional_expected.items():
  try:
    module = importlib.import_module(name)
    installed_version = getattr(module, "__version__", "unknown")
    installed[name] = installed_version
    if normalize_version(installed_version) != normalize_version(expected_version):
      warnings.append(f"{name}: expected {expected_version}, found {installed_version} (continuing)")
  except Exception as exc:
    warnings.append(f"{name}: not importable ({exc.__class__.__name__}) (continuing)")

print("Dependency sanity check: " + ", ".join(f"{name}={installed.get(name, 'missing')}" for name in {**required_expected, **optional_expected}))

if warnings:
  print("Optional dependency warnings:", file=sys.stderr)
  for warning in warnings:
    print(f" - {warning}", file=sys.stderr)

if errors:
  print("Dependency version mismatch detected:", file=sys.stderr)
  for error in errors:
    print(f" - {error}", file=sys.stderr)
  sys.exit(1)
PY
then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Installed dependency versions do not match the configured bootstrap pins.${C_RESET}" >&2
  echo "${C_WARN}       Remove ${VENV_DIR} and retry so the container can rebuild a clean environment.${C_RESET}" >&2
  exit 1
fi

# ── Auth argument construction ────────────────────────────────────────────────
# AUTH_ARGS accumulates --gradio-auth-path and/or --api-auth flags that get
# appended to COMMANDLINE_ARGS right before launch. USING_WEBUI_AUTH_FILE
# tracks whether we're sourcing auth from the managed file (vs. the user
# providing their own --gradio-auth in COMMANDLINE_ARGS).
AUTH_ARGS=()
USING_WEBUI_AUTH_FILE=0

# extract_auth_file_csv: Read an auth file and return all username:password
# pairs as a single comma-separated string. Ignores comments (#) and blank
# lines. Used both for --api-auth (which needs CSV format) and for validation.
extract_auth_file_csv() {
  local auth_file_path="$1"
  python3 - <<'PY' "${auth_file_path}"
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
}

# write_runtime_auth_file: Build a sanitized copy of the auth file with one
# username:password entry per line (no comments, no blank lines). Gradio's
# --gradio-auth-path parser is strict and will crash on anything unexpected.
write_runtime_auth_file() {
  local source_auth_file="$1"
  local runtime_auth_file="$2"
  python3 - <<'PY' "${source_auth_file}" "${runtime_auth_file}"
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
entries = []

for raw_line in src.read_text(encoding='utf-8').splitlines():
  line = raw_line.strip()
  if not line or line.startswith('#'):
    continue
  for cred in line.split(','):
    cred = cred.strip()
    if cred:
      entries.append(cred)

dst.write_text("\n".join(entries) + "\n", encoding='utf-8')
PY
}

if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth([=[:space:]]|$) ]]; then
  echo "${C_INFO}WebUI authentication is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
elif [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth-path([=[:space:]]|$) ]]; then
  echo "${C_INFO}WebUI authentication file is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
else
  # Seed the default auth file on first launch if it does not exist yet.
  if [[ ! -f "${WEBUI_AUTH_FILE}" && -f "${WEBUI_AUTH_SAMPLE_FILE}" ]]; then
    # Create the seeded auth file with restrictive permissions from the start
    # so credentials are never world-readable, even briefly (umask 077 → 600).
    ( umask 077; cp "${WEBUI_AUTH_SAMPLE_FILE}" "${WEBUI_AUTH_FILE}" )
    echo "${C_WARN}Seeded default auth file at ${WEBUI_AUTH_FILE}.${C_RESET}" >&2
  fi

  if [[ ! -f "${WEBUI_AUTH_FILE}" ]]; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file is missing: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_CRIT}         Create the auth file or mount it from the host. Recommended path: /config/auth/webui-auth.txt${C_RESET}" >&2
    exit 1
  fi
  if [[ ! -s "${WEBUI_AUTH_FILE}" ]]; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file is empty: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    exit 1
  fi

  auth_file_csv="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
  if [[ -z "${auth_file_csv}" ]]; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file has no usable credentials: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_CRIT}         Add at least one entry in username:password format.${C_RESET}" >&2
    exit 1
  fi

  # Validate credential formatting up front so malformed entries fail fast
  # with a clear message instead of later crashing inside Gradio auth parsing.
  # The awk check ensures every entry has a non-empty username AND password
  # separated by a colon. Entries like ":password", "user:", or "nocolon" fail.
  if echo "${auth_file_csv}" | tr ',' '\n' | awk -F: '($1=="" || $2=="" || NF<2){bad=1} END{exit bad?0:1}'; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file contains malformed credential entries: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_CRIT}         Expected format is username:password (one per line or comma-separated).${C_RESET}" >&2
    echo "${C_CRIT}         Remove trailing commas and ensure every entry includes both username and password.${C_RESET}" >&2
    exit 1
  fi

  # Gradio auth-path parsing is strict and can crash on comments/blank lines.
  # Build a sanitized runtime auth file with only username:password entries.
  # umask 077 ensures the file is created as mode 600 if it does not yet exist,
  # eliminating the race window between creation and a subsequent chmod.
  # The explicit chmod 600 afterward handles the upgrade case where the file
  # already exists from a previous run with looser permissions (e.g. 644 from
  # an older version of this script that used cp-then-chmod ordering).
  ( umask 077; write_runtime_auth_file "${WEBUI_AUTH_FILE}" "${WEBUI_AUTH_RUNTIME_FILE}" )
  chmod 600 "${WEBUI_AUTH_RUNTIME_FILE}" 2>/dev/null || true

  AUTH_ARGS+=("--gradio-auth-path" "${WEBUI_AUTH_RUNTIME_FILE}")
  USING_WEBUI_AUTH_FILE=1
  echo "${C_INFO}WebUI authentication file is enabled via WEBUI_AUTH_FILE.${C_RESET}" >&2
fi

API_ENABLED=0
if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api([=[:space:]]|$) ]]; then
  API_ENABLED=1
  echo "${C_INFO}API is explicitly enabled via COMMANDLINE_ARGS (--api).${C_RESET}" >&2
else
  echo "${C_ACCENT}API is disabled by default. Add --api to COMMANDLINE_ARGS to enable it.${C_RESET}" >&2
fi

if [[ "${API_ENABLED}" == "1" ]]; then
  if [[ "${USING_WEBUI_AUTH_FILE}" == "1" ]]; then
    if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
      echo "${C_INFO}API authentication is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
    elif [[ "${API_AUTH_FILE_MODE}" == "mirror-webui-file" ]]; then
      api_auth_value="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
      if [[ -z "${api_auth_value}" ]]; then
        echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} WEBUI_AUTH_FILE is set but no usable credentials were found in ${WEBUI_AUTH_FILE}${C_RESET}" >&2
        exit 1
      fi
      AUTH_ARGS+=("--api-auth" "${api_auth_value}")
      echo "${C_INFO}API authentication is mirrored from WEBUI_AUTH_FILE.${C_RESET}" >&2
    elif [[ "${API_AUTH_FILE_MODE}" == "disabled" ]]; then
      echo "${C_ACCENT}API auth mirroring from WEBUI_AUTH_FILE disabled via API_AUTH_FILE_MODE=disabled.${C_RESET}" >&2
    else
      echo "${C_WARN}[WARNING] Unrecognized API_AUTH_FILE_MODE=${API_AUTH_FILE_MODE}. Expected mirror-webui-file or disabled. Falling back to mirror-webui-file." >&2
      api_auth_value="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
      if [[ -z "${api_auth_value}" ]]; then
        echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} WEBUI_AUTH_FILE is set but no usable credentials were found in ${WEBUI_AUTH_FILE}${C_RESET}" >&2
        exit 1
      fi
      AUTH_ARGS+=("--api-auth" "${api_auth_value}")
      echo "${C_INFO}API authentication is mirrored from WEBUI_AUTH_FILE.${C_RESET}" >&2
    fi
  else
    echo "${C_ACCENT}API auth mirroring skipped because auth is not sourced from WEBUI_AUTH_FILE.${C_RESET}" >&2
  fi
else
  if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
    echo "${C_WARN}[WARNING] --api-auth was provided but --api is not enabled. API auth flags will be ignored unless --api is set.${C_RESET}" >&2
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Startup output helpers
# ─────────────────────────────────────────────────────────────────────────────

# print_launch_notice: print a friendly pre-launch summary so users know what
# to expect before WebUI output starts scrolling. Covers first-run scenarios,
# missing models, and a table of known harmless warnings.
print_launch_notice() {
  local model_count=0
  if [[ -d "/data/models/Stable-diffusion" ]]; then
    model_count="$(find /data/models/Stable-diffusion -maxdepth 1 \( -name '*.safetensors' -o -name '*.ckpt' \) 2>/dev/null | wc -l | tr -d ' ')"
  fi

  local ACCENT="${C_ACCENT}" INFO="${C_INFO}" WARN="${C_WARN}" RESET="${C_RESET}" BOLD="${C_BOLD}"

  echo ""
  echo "${ACCENT}┌─────────────────────────────────────────────────────────────────────┐${RESET}"
  echo "${ACCENT}│${RESET}  ${BOLD}${INFO}AUTOMATIC1111 Stable Diffusion WebUI${RESET}${ACCENT}                               │${RESET}"
  echo "${ACCENT}└─────────────────────────────────────────────────────────────────────┘${RESET}"
  echo ""

  if [[ ! -f "${BOOTSTRAP_STAMP}" ]]; then
    echo "  ${WARN}${BOLD}► FIRST RUN:${RESET}${WARN} Installing Python dependencies under /data/venv.${RESET}"
    echo "  ${WARN}  This can take several minutes. Subsequent starts will be much faster.${RESET}"
    echo ""
  fi

  if [[ "${model_count}" -eq 0 ]]; then
    echo "  ${WARN}⚠  No model checkpoints found in /data/models/Stable-diffusion/${RESET}"
    echo "  ${WARN}   You will see a 'No checkpoints found' warning below — this is expected${RESET}"
    echo "  ${WARN}   until you add a model. The WebUI will still start.${RESET}"
    echo "  ${WARN}   Fix: add a .safetensors or .ckpt file to:${RESET}"
    echo "  ${WARN}          /data/models/Stable-diffusion/${RESET}"
    echo "  ${WARN}        then restart the container or use Settings → Refresh in the UI.${RESET}"
  else
    echo "  ${INFO}✓  Found ${model_count} checkpoint(s) in /data/models/Stable-diffusion/${RESET}"
  fi

  echo ""
  echo "  ${ACCENT}Known harmless messages you may see in the log below:${RESET}"
  echo "  ${ACCENT}▸ 'FutureWarning: Importing from timm.models.layers'${RESET}"
  echo "    ${INFO}→ Upstream library deprecation notice. Safe to ignore.${RESET}"
  echo "  ${ACCENT}▸ 'UserWarning: TypedStorage is deprecated'${RESET}"
  echo "    ${INFO}→ Internal PyTorch notice. Safe to ignore.${RESET}"
  echo "  ${ACCENT}▸ 'Stable diffusion model failed to load' (only when no checkpoint exists)${RESET}"
  echo "    ${WARN}→ Expected until a model is placed in /data/models/Stable-diffusion/.${RESET}"
  echo ""
  echo "  ${INFO}Inline notes marked [NOTE] or [KNOWN WARNING] are added by this container${RESET}"
  echo "  ${INFO}and are not part of the upstream WebUI output.${RESET}"
  echo ""
  echo "  ${INFO}WebUI will be available at: ${BOLD}${ACCENT}http://<your-unraid-ip>:7860${RESET}"
  echo "  ${ACCENT}(Use your Unraid hostname or IP and the port you mapped in the template)${RESET}"
  echo ""
  echo "${ACCENT}─────────────────────────────────────────────────────────────────────────${RESET}"
  echo ""
}

# monitor_webui_output: pass all WebUI stdout/stderr through unchanged, and
# emit inline notes after recognised noisy lines so users are not alarmed.
# Runs in a subshell reading from the WebUI output pipe.
monitor_webui_output() {
  local _saw_timm=0 _saw_storage=0 _saw_checkpoint=0

  while IFS= read -r line; do
    printf '%s\n' "${line}"

    # timm FutureWarning — appears on every start, always harmless
    if [[ $_saw_timm -eq 0 && "${line}" == *"Importing from timm.models.layers is deprecated"* ]]; then
      _saw_timm=1
      echo "  ${C_INFO}[NOTE] ↑ Harmless upstream deprecation warning from the timm library. Safe to ignore.${C_RESET}"
    fi

    # PyTorch TypedStorage deprecation — common internal notice, harmless
    if [[ $_saw_storage -eq 0 && "${line}" == *"TypedStorage is deprecated"* ]]; then
      _saw_storage=1
      echo "  ${C_INFO}[NOTE] ↑ Harmless internal PyTorch deprecation notice. Safe to ignore.${C_RESET}"
    fi

    # No checkpoints found — needs action if user intends to generate images
    if [[ $_saw_checkpoint -eq 0 && "${line}" == *"No checkpoints found"* ]]; then
      _saw_checkpoint=1
      echo ""
      echo "  ${C_WARN}┌─ [KNOWN WARNING] ───────────────────────────────────────────────────┐${C_RESET}"
      echo "  ${C_WARN}│  No model checkpoint was found. This is expected on a fresh install │${C_RESET}"
      echo "  ${C_WARN}│  or if /data/models/ was cleared. The WebUI will still start.       │${C_RESET}"
      echo "  ${C_WARN}│                                                                     │${C_RESET}"
      echo "  ${C_WARN}│  Fix: add a .safetensors or .ckpt file to:                          │${C_RESET}"
      echo "  ${C_WARN}│         /data/models/Stable-diffusion/                              │${C_RESET}"
      echo "  ${C_WARN}│  then restart the container, or use Settings → Refresh in the UI.   │${C_RESET}"
      echo "  ${C_WARN}└─────────────────────────────────────────────────────────────────────┘${C_RESET}"
      echo ""
    fi

    # CUDA out of memory — actionable GPU issue
    if [[ "${line}" == *"CUDA out of memory"* ]]; then
      echo ""
      echo "  ${C_CRIT}┌─ [GPU MEMORY ERROR] ────────────────────────────────────────────────┐${C_RESET}"
      echo "  ${C_CRIT}│  Your GPU ran out of VRAM during this operation.                    │${C_RESET}"
      echo "  ${C_CRIT}│  Tips:                                                              │${C_RESET}"
      echo "  ${C_CRIT}│    • Reduce image resolution or batch size                          │${C_RESET}"
      echo "  ${C_CRIT}│    • Enable xformers (--xformers in COMMANDLINE_ARGS)               │${C_RESET}"
      echo "  ${C_CRIT}│    • Try a smaller or lower-precision model                         │${C_RESET}"
      echo "  ${C_CRIT}└─────────────────────────────────────────────────────────────────────┘${C_RESET}"
      echo ""
    fi

    # GPU not visible to PyTorch — likely missing --runtime=nvidia or NVIDIA plugin issue
    if [[ "${line}" == *"torch.cuda.is_available() = False"* || "${line}" == *"Torch is not able to use GPU"* ]]; then
      echo ""
      echo "  ${C_CRIT}┌─ [GPU NOT DETECTED] ────────────────────────────────────────────────┐${C_RESET}"
      echo "  ${C_CRIT}│  PyTorch cannot see a CUDA-capable GPU.                             │${C_RESET}"
      echo "  ${C_CRIT}│  Check:                                                             │${C_RESET}"
      echo "  ${C_CRIT}│    • --runtime=nvidia is present in Extra Parameters in the template│${C_RESET}"
      echo "  ${C_CRIT}│    • The Unraid NVIDIA plugin is installed and working              │${C_RESET}"
      echo "  ${C_CRIT}│    • Run on the host to verify:                                     │${C_RESET}"
      echo "  ${C_CRIT}│        docker run --rm --runtime=nvidia ubuntu nvidia-smi           │${C_RESET}"
      echo "  ${C_CRIT}└─────────────────────────────────────────────────────────────────────┘${C_RESET}"
      echo ""
    fi

  done
}

# _poll_for_ready: independent background poller that prints the READY banner
# once the WebUI port is confirmed accepting TCP connections.
# Runs completely outside the log monitor so it is not affected by log content
# or Gradio version changes. Uses bash's built-in /dev/tcp — no external tools.
_poll_for_ready() {
  local _port="7860"
  # Extract --port value from COMMANDLINE_ARGS if the user overrode the default
  if [[ "${COMMANDLINE_ARGS:-}" =~ --port[[:space:]]+([0-9]+) ]]; then
    _port="${BASH_REMATCH[1]}"
  fi

  # Determine the URL host — checked in order:
  #   1. WEBUI_HOST_IP env var (explicit override; required in bridge/NAT mode)
  #   2. Container's own outbound IP if it is a real LAN address
  #      (macvlan / Unraid br0 / --network=host — container IP is directly reachable)
  #   3. Placeholder with hint to set WEBUI_HOST_IP
  local _host_ip=""
  if [[ -n "${WEBUI_HOST_IP:-}" ]]; then
    _host_ip="${WEBUI_HOST_IP}"
  else
    # Python3 is always available (it runs A1111). The UDP connect() resolves the
    # source address without actually sending any data to 8.8.8.8.
    local _own_ip
    _own_ip="$(python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(("8.8.8.8",80)); print(s.getsockname()[0]); s.close()' 2>/dev/null || true)"
    # Docker allocates bridge subnets from 172.16.0.0/12 (172.16–172.31.x.x).
    # If the container's IP is outside that range it has a real LAN address and
    # IS directly reachable by browsers — use it.  In bridge/NAT mode the container
    # only sees a 172.x.x.x address; the host's real LAN IP is not discoverable
    # from inside the container without WEBUI_HOST_IP being set.
    if [[ -n "${_own_ip}" && ! "${_own_ip}" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
      _host_ip="${_own_ip}"
    fi
  fi

  local _timeout=600   # Give up after 10 min (matches HEALTHCHECK start-period)
  local _interval=5    # Poll every 5 s
  local _elapsed=0

  while [[ $_elapsed -lt $_timeout ]]; do
    sleep "${_interval}"
    _elapsed=$(( _elapsed + _interval ))
    # /dev/tcp is a bash built-in — opens a TCP connection without any external binary
    # shellcheck disable=SC2188
    if (: < /dev/tcp/127.0.0.1/"${_port}") 2>/dev/null; then
      local _url
      if [[ -n "${_host_ip}" ]]; then
        _url="http://${_host_ip}:${_port}/"
      else
        _url="http://<your-unraid-ip>:${_port}/"
      fi
      echo ""
      echo "  ${C_ACCENT}${C_BOLD}┌─ [READY] ───────────────────────────────────────────────────────────┐${C_RESET}"
      echo "  ${C_ACCENT}${C_BOLD}│  WebUI is LIVE — open it in your browser:                           │${C_RESET}"
      printf  "  ${C_ACCENT}${C_BOLD}│  %-67s│${C_RESET}\n" "${_url}"
      echo "  ${C_ACCENT}${C_BOLD}└─────────────────────────────────────────────────────────────────────┘${C_RESET}"
      echo ""
      return 0
    fi
  done
  # Timed out without confirming — silently give up (HEALTHCHECK will flag unhealthy)
}

# is_truthy: Accepts common boolean-like env var values (1, true, yes, on)
# and returns 0 (success); anything else returns 1 (failure).
is_truthy() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Build final COMMANDLINE_ARGS with auth flags appended, then launch.
#
# Note: --api-auth credentials are appended here as a plain string because
# A1111 has no file-based equivalent for API auth. This means credentials
# are visible via docker inspect / /proc/<pid>/environ. See README for
# the full discussion and mitigation options.
# ─────────────────────────────────────────────────────────────────────────────
if [[ ${#AUTH_ARGS[@]} -gt 0 ]]; then
  quoted_auth_args=()
  for arg in "${AUTH_ARGS[@]}"; do
    quoted_auth_args+=("$(printf '%q' "${arg}")")
  done
  export COMMANDLINE_ARGS="${COMMANDLINE_ARGS:-} ${quoted_auth_args[*]}"
fi

if [[ -n "${COMMANDLINE_ARGS:-}" ]]; then
  echo "${C_ACCENT}Starting WebUI (COMMANDLINE_ARGS set).${C_RESET}"
else
  echo "${C_ACCENT}Starting WebUI (no COMMANDLINE_ARGS provided).${C_RESET}"
fi

print_launch_notice

# ── Launch with output monitoring ────────────────────────────────────────────
#
# Architecture: named-pipe pattern
#   WebUI (stdout+stderr) → named pipe → monitor_webui_output → user terminal
#
#   This lets us inject inline [NOTE] / [KNOWN WARNING] annotations after
#   recognised log lines without buffering or modifying the WebUI process.
#
# Signal handling:
#   Docker stop/kill sends SIGTERM to PID 1 (entrypoint). The trap below
#   forwards it to the WebUI process so it can shut down gracefully. The EXIT
#   trap cleans up the temp directory holding the named pipe.
#
_MONITOR_DIR="$(mktemp -d /tmp/a1111-monitor.XXXXXX)"
_LOG_PIPE="${_MONITOR_DIR}/webui.log.pipe"
mkfifo "${_LOG_PIPE}"

_WEBUI_PID=""
_POLLER_PID=""

# shellcheck disable=SC2317 # These are invoked by trap, not direct calls.
_cleanup_monitor() {
  [[ -n "${_POLLER_PID}" ]] && kill "${_POLLER_PID}" 2>/dev/null || true
  rm -rf "${_MONITOR_DIR}"
}
# shellcheck disable=SC2317
_forward_signal()  { [[ -n "${_WEBUI_PID}" ]] && kill -TERM "${_WEBUI_PID}" 2>/dev/null; true; }

trap '_cleanup_monitor' EXIT
trap '_forward_signal' TERM INT

# Start the output monitor first — the reader must open the pipe before the
# writer, otherwise the writer blocks indefinitely waiting for a reader.
monitor_webui_output < "${_LOG_PIPE}" &
_MONITOR_PID=$!

# Launch the WebUI. Both stdout and stderr go through the pipe so
# monitor_webui_output sees all output (Python warnings go to stderr).
"${VENV_PYTHON}" launch.py > "${_LOG_PIPE}" 2>&1 &
_WEBUI_PID=$!

# Start the background poller — runs independently, prints READY banner when
# port is confirmed live. Killed on container stop via _cleanup_monitor.
_poll_for_ready &
_POLLER_PID=$!

# Wait for the WebUI to exit and capture its exit code.
_WEBUI_EXIT=0
wait "${_WEBUI_PID}" || _WEBUI_EXIT=$?

# Let the monitor drain any remaining buffered output before we exit.
wait "${_MONITOR_PID}" 2>/dev/null || true

exit "${_WEBUI_EXIT}"
