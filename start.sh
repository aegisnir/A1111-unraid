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
# Violet  → informational / safe-to-ignore messages
# Orange  → caution / warnings that need attention but are not fatal
# Scarlet → critical errors requiring user action
# Silver  → structural chrome (borders, labels, dim text)
# Only emit color sequences when stderr is a terminal; stay plain in log files.
if [[ -t 2 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_SILVER=$'\e[37m'
  C_VIOLET=$'\e[95m'; C_ORANGE=$'\e[93m'; C_SCARLET=$'\e[91m'
else
  C_RESET='' C_BOLD='' C_SILVER='' C_VIOLET='' C_ORANGE='' C_SCARLET=''
fi

# Set HOME for the non-root user to /data for consistent config/cache locations
export HOME=/data

# Use persistent temp storage in /data so large downloads (for example torch wheels)
# do not exhaust the container's limited writable temp space.
export TMPDIR=/data/tmp

# Use persistent pip cache in /data for faster rebuilds
export PIP_CACHE_DIR=/data/pip-cache

if [[ "$(id -u)" == "0" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} Refusing to run as root. Please use a non-root user (UID 99 recommended for Unraid).${C_RESET}" >&2
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
WEBUI_AUTH_FILE_DEFAULT="/data/auth/webui-auth.txt"
WEBUI_AUTH_FILE="${WEBUI_AUTH_FILE:-${WEBUI_AUTH_FILE_DEFAULT}}"
API_AUTH_FILE_MODE="${API_AUTH_FILE_MODE:-mirror-webui-file}"
UMASK="${UMASK:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_AUTH_SAMPLE_FILE="${SCRIPT_DIR}/webui-auth.txt"
EXTENSIONS_BOOTSTRAP_FILE="${EXTENSIONS_BOOTSTRAP_FILE:-/data/extensions-bootstrap.txt}"
EXTENSIONS_BOOTSTRAP_FORCE="${EXTENSIONS_BOOTSTRAP_FORCE:-false}"
EXTENSIONS_DIR_DEFAULT="/data/extensions"
EXTENSIONS_BOOTSTRAP_STATE_DIR="/data/.state"
EXTENSIONS_BOOTSTRAP_MARKER="${EXTENSIONS_BOOTSTRAP_STATE_DIR}/extensions-bootstrap-v1.done"
EXTENSIONS_BOOTSTRAP_SAMPLE_FILE="${SCRIPT_DIR}/extensions-bootstrap.txt"
export PIP_NO_BUILD_ISOLATION="${PIP_NO_BUILD_ISOLATION:-1}"

if [[ -n "${UMASK}" ]]; then
  if [[ ! "${UMASK}" =~ ^[0-7]{3,4}$ ]]; then
    echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} UMASK must be a 3- or 4-digit octal value (for example 027 or 0027).${C_RESET}" >&2
    exit 1
  fi
  umask "${UMASK}"
  echo "${C_SILVER}Using UMASK=${UMASK}${C_RESET}" >&2
fi

if [[ ! -d "${WEBUI_DIR}" && -d "${LOCAL_WEBUI_DIR}" ]]; then
  echo "${C_ORANGE}Container WebUI directory not found; falling back to local workspace path: ${LOCAL_WEBUI_DIR}${C_RESET}" >&2
  WEBUI_DIR="${LOCAL_WEBUI_DIR}"
fi

# Basic sanity checks to make failures easier to diagnose.
# These are here mostly to fail fast with clearer messages instead of producing
# a less helpful Python or file-not-found error later in startup.
if [[ ! -d "${WEBUI_DIR}" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} Expected WebUI directory not found: ${WEBUI_DIR}${C_RESET}" >&2
  echo "${C_SCARLET}       The image build may have failed or WEBUI_DIR may be incorrect.${C_RESET}" >&2
  exit 1
fi

if [[ ! -f "${WEBUI_DIR}/launch.py" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} launch.py not found in: ${WEBUI_DIR}${C_RESET}" >&2
  echo "${C_SCARLET}       The repository contents may be incomplete or not checked out as expected.${C_RESET}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} python3 is not available in PATH.${C_RESET}" >&2
  echo "${C_SCARLET}       The base image or dependency installation may be incomplete.${C_RESET}" >&2
  exit 1
fi

if [[ ! -d "/data" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} Expected mapped data directory not found at /data${C_RESET}" >&2
  echo "${C_SCARLET}       Map /data to a writable host path before starting the container.${C_RESET}" >&2
  exit 1
fi

if [[ ! -w "/data" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} /data exists but is not writable by the current user (uid=$(id -u)).${C_RESET}" >&2
  echo "${C_SCARLET}       The container entrypoint attempted to correct this automatically but could not.${C_RESET}" >&2
  echo "${C_SCARLET}       This can happen with NFS root squash, unusual host permissions, or SELinux policies.${C_RESET}" >&2
  echo "" >&2
  echo "${C_ORANGE}       To fix manually, run the following on the Unraid host (as root) and then restart${C_RESET}" >&2
  echo "${C_ORANGE}       the container:${C_RESET}" >&2
  echo "" >&2
  echo "${C_SILVER}         chown nobody:users /mnt/user/ai/data${C_RESET}" >&2
  echo "${C_SILVER}         chmod 775 /mnt/user/ai/data${C_RESET}" >&2
  echo "" >&2
  echo "${C_ORANGE}       Adjust the path above if your Unraid share path is different.${C_RESET}" >&2
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
mkdir -p /data/auth

available_kb="$(df -Pk /data | awk 'NR==2 {print $4}')"
if [[ -z "${available_kb}" || ! "${available_kb}" =~ ^[0-9]+$ ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} Unable to determine free space for /data.${C_RESET}" >&2
  echo "${C_SCARLET}       Verify that /data is mounted and writable before starting the container.${C_RESET}" >&2
  exit 1
fi

if [[ -e "${WEBUI_DIR}/config_states" && ! -L "${WEBUI_DIR}/config_states" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} ${WEBUI_DIR}/config_states exists and is not a symlink.${C_RESET}" >&2
  echo "${C_SCARLET}       On a read-only container filesystem, start.sh cannot replace it at runtime.${C_RESET}" >&2
  echo "${C_ORANGE}       Rebuild the image without that path, or remove it before enabling --read-only.${C_RESET}" >&2
  exit 1
fi

if [[ -L "${WEBUI_DIR}/config_states" ]]; then
  existing_target="$(readlink "${WEBUI_DIR}/config_states")"
  if [[ "${existing_target}" != "${RUNTIME_CONFIG_STATES_DIR}" ]]; then
    echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} ${WEBUI_DIR}/config_states points to ${existing_target}, expected ${RUNTIME_CONFIG_STATES_DIR}.${C_RESET}" >&2
    echo "${C_ORANGE}       Rebuild the image so the config_states symlink matches the persistent runtime path.${C_RESET}" >&2
    exit 1
  fi
else
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} ${WEBUI_DIR}/config_states symlink is missing.${C_RESET}" >&2
  echo "${C_ORANGE}       This image now expects that symlink to be created at build time so startup works with --read-only.${C_RESET}" >&2
  exit 1
fi

available_mb="$(( available_kb / 1024 ))"
echo "${C_SILVER}Detected free space in /data: ${available_mb} MiB${C_RESET}"

required_kb="$(( MIN_BOOTSTRAP_FREE_MB * 1024 ))"
if [[ ! -f "${BOOTSTRAP_STAMP}" && "${available_kb}" -lt "${required_kb}" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} Not enough free space in /data for first-run dependency bootstrap.${C_RESET}" >&2
  echo "${C_SCARLET}       Available: ${available_mb} MiB${C_RESET}" >&2
  echo "${C_SCARLET}       Recommended minimum: ${MIN_BOOTSTRAP_FREE_MB} MiB${C_RESET}" >&2
  echo "${C_ORANGE}       Torch, torchvision, xformers, and pip temp files can require several GB on first startup.${C_RESET}" >&2
  echo "${C_ORANGE}       Free additional space in the mapped /data path, or set MIN_BOOTSTRAP_FREE_MB if you intentionally want a different threshold.${C_RESET}" >&2
  exit 1
fi

if [[ -e "${WEBUI_DIR}/repositories" && ! -L "${WEBUI_DIR}/repositories" ]]; then
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} ${WEBUI_DIR}/repositories exists and is not a symlink.${C_RESET}" >&2
  echo "${C_SCARLET}       On a read-only container filesystem, start.sh cannot replace it at runtime.${C_RESET}" >&2
  echo "${C_ORANGE}       Rebuild the image with the symlink baked in, or remove that path before enabling --read-only.${C_RESET}" >&2
  exit 1
fi

if [[ -L "${WEBUI_DIR}/repositories" ]]; then
  existing_target="$(readlink "${WEBUI_DIR}/repositories")"
  if [[ "${existing_target}" != "${RUNTIME_REPOS_DIR}" ]]; then
    echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} ${WEBUI_DIR}/repositories points to ${existing_target}, expected ${RUNTIME_REPOS_DIR}.${C_RESET}" >&2
    echo "${C_ORANGE}       Rebuild the image so the repositories symlink matches the persistent runtime path.${C_RESET}" >&2
    exit 1
  fi
else
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} ${WEBUI_DIR}/repositories symlink is missing.${C_RESET}" >&2
  echo "${C_ORANGE}       This image now expects that symlink to be created at build time so startup works with --read-only.${C_RESET}" >&2
  exit 1
fi

# Extension bootstrap destination compatibility:
# Newer images symlink ${WEBUI_DIR}/extensions -> /data/extensions so no
# unsupported launch.py flags are needed. On older images without that symlink,
# fall back to the in-tree extensions path.
if [[ -L "${WEBUI_DIR}/extensions" ]]; then
  ext_target="$(readlink "${WEBUI_DIR}/extensions")"
  if [[ "${ext_target}" != "/data/extensions" ]]; then
    echo "${C_ORANGE}[WARNING] ${WEBUI_DIR}/extensions points to ${ext_target}; expected /data/extensions. Using ${WEBUI_DIR}/extensions for bootstrap.${C_RESET}" >&2
    EXTENSIONS_DIR_DEFAULT="${WEBUI_DIR}/extensions"
  fi
elif [[ -d "${WEBUI_DIR}/extensions" ]]; then
  echo "${C_ORANGE}[WARNING] ${WEBUI_DIR}/extensions is not symlinked to /data/extensions. Using legacy in-tree extensions directory for this image.${C_RESET}" >&2
  EXTENSIONS_DIR_DEFAULT="${WEBUI_DIR}/extensions"
else
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} Expected extensions directory not found at ${WEBUI_DIR}/extensions.${C_RESET}" >&2
  exit 1
fi

if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "${C_VIOLET}Creating persistent Python virtual environment in ${VENV_DIR}${C_RESET}" >&2
  python3 -m venv "${VENV_DIR}"
fi

if [[ ! -f "${BOOTSTRAP_STAMP}" ]]; then
  echo "${C_ORANGE}Installing first-start Python dependencies (this may take a while)...${C_RESET}" >&2
  echo "${C_SILVER}Bootstrap dependency targets: torch=${TORCH_VERSION}, torchvision=${TORCHVISION_VERSION}, xformers=${XFORMERS_VERSION}${C_RESET}" >&2
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
  echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} Installed dependency versions do not match the configured bootstrap pins.${C_RESET}" >&2
  echo "${C_ORANGE}       Remove ${VENV_DIR} and retry so the container can rebuild a clean environment.${C_RESET}" >&2
  exit 1
fi

AUTH_ARGS=()
USING_WEBUI_AUTH_FILE=0

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

if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth([=[:space:]]|$) ]]; then
  echo "${C_VIOLET}WebUI authentication is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
elif [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth-path([=[:space:]]|$) ]]; then
  echo "${C_VIOLET}WebUI authentication file is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
else
  if [[ ! -f "${WEBUI_AUTH_FILE}" && -f "${WEBUI_AUTH_SAMPLE_FILE}" ]]; then
    cp "${WEBUI_AUTH_SAMPLE_FILE}" "${WEBUI_AUTH_FILE}"
    chmod 600 "${WEBUI_AUTH_FILE}" 2>/dev/null || true
    echo "${C_ORANGE}Seeded default auth file at ${WEBUI_AUTH_FILE}.${C_RESET}" >&2
  fi
fi

if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth([=[:space:]]|$) ]]; then
  echo "${C_VIOLET}WebUI authentication is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
elif [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth-path([=[:space:]]|$) ]]; then
  echo "${C_VIOLET}WebUI authentication file is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
else
  if [[ ! -f "${WEBUI_AUTH_FILE}" ]]; then
    echo "${C_SCARLET}${C_BOLD}CRITICAL:${C_RESET}${C_SCARLET} WebUI auth file is missing: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_SCARLET}         Create the auth file or mount it from the host. Recommended path: /data/auth/webui-auth.txt${C_RESET}" >&2
    exit 1
  fi
  if [[ ! -s "${WEBUI_AUTH_FILE}" ]]; then
    echo "${C_SCARLET}${C_BOLD}CRITICAL:${C_RESET}${C_SCARLET} WebUI auth file is empty: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    exit 1
  fi

  auth_file_csv="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
  if [[ -z "${auth_file_csv}" ]]; then
    echo "${C_SCARLET}${C_BOLD}CRITICAL:${C_RESET}${C_SCARLET} WebUI auth file has no usable credentials: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_SCARLET}         Add at least one entry in username:password format.${C_RESET}" >&2
    exit 1
  fi

  AUTH_ARGS+=("--gradio-auth-path" "${WEBUI_AUTH_FILE}")
  USING_WEBUI_AUTH_FILE=1
  echo "${C_VIOLET}WebUI authentication file is enabled via WEBUI_AUTH_FILE.${C_RESET}" >&2
fi

API_ENABLED=0
if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api([=[:space:]]|$) ]]; then
  API_ENABLED=1
  echo "${C_VIOLET}API is explicitly enabled via COMMANDLINE_ARGS (--api).${C_RESET}" >&2
else
  echo "${C_SILVER}API is disabled by default. Add --api to COMMANDLINE_ARGS to enable it.${C_RESET}" >&2
fi

if [[ "${API_ENABLED}" == "1" ]]; then
  if [[ "${USING_WEBUI_AUTH_FILE}" == "1" ]]; then
    if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
      echo "${C_VIOLET}API authentication is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
    elif [[ "${API_AUTH_FILE_MODE}" == "mirror-webui-file" ]]; then
      api_auth_value="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
      if [[ -z "${api_auth_value}" ]]; then
        echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} WEBUI_AUTH_FILE is set but no usable credentials were found in ${WEBUI_AUTH_FILE}${C_RESET}" >&2
        exit 1
      fi
      AUTH_ARGS+=("--api-auth" "${api_auth_value}")
      echo "${C_VIOLET}API authentication is mirrored from WEBUI_AUTH_FILE.${C_RESET}" >&2
    elif [[ "${API_AUTH_FILE_MODE}" == "disabled" ]]; then
      echo "${C_SILVER}API auth mirroring from WEBUI_AUTH_FILE disabled via API_AUTH_FILE_MODE=disabled.${C_RESET}" >&2
    else
      echo "${C_ORANGE}[WARNING] Unrecognized API_AUTH_FILE_MODE=${API_AUTH_FILE_MODE}. Expected mirror-webui-file or disabled. Falling back to mirror-webui-file." >&2
      api_auth_value="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
      if [[ -z "${api_auth_value}" ]]; then
        echo "${C_SCARLET}${C_BOLD}ERROR:${C_RESET}${C_SCARLET} WEBUI_AUTH_FILE is set but no usable credentials were found in ${WEBUI_AUTH_FILE}${C_RESET}" >&2
        exit 1
      fi
      AUTH_ARGS+=("--api-auth" "${api_auth_value}")
      echo "${C_VIOLET}API authentication is mirrored from WEBUI_AUTH_FILE.${C_RESET}" >&2
    fi
  else
    echo "${C_SILVER}API auth mirroring skipped because auth is not sourced from WEBUI_AUTH_FILE.${C_RESET}" >&2
  fi
else
  if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
    echo "${C_ORANGE}[WARNING] --api-auth was provided but --api is not enabled. API auth flags will be ignored unless --api is set.${C_RESET}" >&2
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

  local S="${C_SILVER}" V="${C_VIOLET}" O="${C_ORANGE}" R="${C_RESET}" B="${C_BOLD}"

  echo ""
  echo "${S}┌─────────────────────────────────────────────────────────────────────┐${R}"
  echo "${S}│${R}  ${B}${V}AUTOMATIC1111 Stable Diffusion WebUI${R}${S}                               │${R}"
  echo "${S}└─────────────────────────────────────────────────────────────────────┘${R}"
  echo ""

  if [[ ! -f "${BOOTSTRAP_STAMP}" ]]; then
    echo "  ${O}${B}► FIRST RUN:${R}${O} Installing Python dependencies under /data/venv.${R}"
    echo "  ${O}  This can take several minutes. Subsequent starts will be much faster.${R}"
    echo ""
  fi

  if [[ "${model_count}" -eq 0 ]]; then
    echo "  ${O}⚠  No model checkpoints found in /data/models/Stable-diffusion/${R}"
    echo "  ${O}   You will see a 'No checkpoints found' warning below — this is expected${R}"
    echo "  ${O}   until you add a model. The WebUI will still start.${R}"
    echo "  ${O}   Fix: add a .safetensors or .ckpt file to:${R}"
    echo "  ${O}          /data/models/Stable-diffusion/${R}"
    echo "  ${O}        then restart the container or use Settings → Refresh in the UI.${R}"
  else
    echo "  ${V}✓  Found ${model_count} checkpoint(s) in /data/models/Stable-diffusion/${R}"
  fi

  echo ""
  echo "  ${S}Known harmless messages you may see in the log below:${R}"
  echo "  ${S}▸ 'FutureWarning: Importing from timm.models.layers'${R}"
  echo "    ${V}→ Upstream library deprecation notice. Safe to ignore.${R}"
  echo "  ${S}▸ 'UserWarning: TypedStorage is deprecated'${R}"
  echo "    ${V}→ Internal PyTorch notice. Safe to ignore.${R}"
  echo "  ${S}▸ 'Stable diffusion model failed to load' (only when no checkpoint exists)${R}"
  echo "    ${O}→ Expected until a model is placed in /data/models/Stable-diffusion/.${R}"
  echo ""
  echo "  ${V}Inline notes marked [NOTE] or [KNOWN WARNING] are added by this container${R}"
  echo "  ${V}and are not part of the upstream WebUI output.${R}"
  echo ""
  echo "  ${V}WebUI will be available at: ${B}http://<your-unraid-ip>:7860${R}"
  echo "  ${S}(Use your Unraid hostname or IP and the port you mapped in the template)${R}"
  echo ""
  echo "${S}─────────────────────────────────────────────────────────────────────────${R}"
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
      echo "  ${C_VIOLET}[NOTE] ↑ Harmless upstream deprecation warning from the timm library. Safe to ignore.${C_RESET}"
    fi

    # PyTorch TypedStorage deprecation — common internal notice, harmless
    if [[ $_saw_storage -eq 0 && "${line}" == *"TypedStorage is deprecated"* ]]; then
      _saw_storage=1
      echo "  ${C_VIOLET}[NOTE] ↑ Harmless internal PyTorch deprecation notice. Safe to ignore.${C_RESET}"
    fi

    # No checkpoints found — needs action if user intends to generate images
    if [[ $_saw_checkpoint -eq 0 && "${line}" == *"No checkpoints found"* ]]; then
      _saw_checkpoint=1
      echo ""
      echo "  ${C_ORANGE}┌─ ${C_BOLD}[KNOWN WARNING]${C_RESET}${C_ORANGE} ───────────────────────────────────────────────────${C_RESET}"
      echo "  ${C_ORANGE}│  No model checkpoint was found. This is expected on a fresh install${C_RESET}"
      echo "  ${C_ORANGE}│  or if /data/models/ was cleared. The WebUI will still start.${C_RESET}"
      echo "  ${C_ORANGE}│${C_RESET}"
      echo "  ${C_ORANGE}│  Fix: add a .safetensors or .ckpt file to:${C_RESET}"
      echo "  ${C_ORANGE}│         /data/models/Stable-diffusion/${C_RESET}"
      echo "  ${C_ORANGE}│  then restart the container, or use Settings → Refresh in the UI.${C_RESET}"
      echo "  ${C_ORANGE}└─────────────────────────────────────────────────────────────────────${C_RESET}"
      echo ""
    fi

    # CUDA out of memory — actionable GPU issue
    if [[ "${line}" == *"CUDA out of memory"* ]]; then
      echo ""
      echo "  ${C_SCARLET}┌─ ${C_BOLD}[GPU MEMORY ERROR]${C_RESET}${C_SCARLET} ────────────────────────────────────────────────${C_RESET}"
      echo "  ${C_SCARLET}│  Your GPU ran out of VRAM during this operation.${C_RESET}"
      echo "  ${C_SCARLET}│  Tips:${C_RESET}"
      echo "  ${C_SCARLET}│    • Reduce image resolution or batch size${C_RESET}"
      echo "  ${C_SCARLET}│    • Enable xformers (--xformers in COMMANDLINE_ARGS)${C_RESET}"
      echo "  ${C_SCARLET}│    • Try a smaller or lower-precision model${C_RESET}"
      echo "  ${C_SCARLET}└─────────────────────────────────────────────────────────────────────${C_RESET}"
      echo ""
    fi

    # GPU not visible to PyTorch — likely missing --runtime=nvidia or NVIDIA plugin issue
    if [[ "${line}" == *"torch.cuda.is_available() = False"* || "${line}" == *"Torch is not able to use GPU"* ]]; then
      echo ""
      echo "  ${C_SCARLET}┌─ ${C_BOLD}[GPU NOT DETECTED]${C_RESET}${C_SCARLET} ────────────────────────────────────────────────${C_RESET}"
      echo "  ${C_SCARLET}│  PyTorch cannot see a CUDA-capable GPU.${C_RESET}"
      echo "  ${C_SCARLET}│  Check:${C_RESET}"
      echo "  ${C_SCARLET}│    • --runtime=nvidia is present in Extra Parameters in the template${C_RESET}"
      echo "  ${C_SCARLET}│    • The Unraid NVIDIA plugin is installed and working${C_RESET}"
      echo "  ${C_SCARLET}│    • Run on the host to verify:${C_RESET}"
      echo "  ${C_SCARLET}│        docker run --rm --gpus all nvidia/cuda:12.9.1-runtime-ubuntu22.04 nvidia-smi${C_RESET}"
      echo "  ${C_SCARLET}└─────────────────────────────────────────────────────────────────────${C_RESET}"
      echo ""
    fi

    # WebUI ready signal — Gradio prints this when the server is accepting connections
    if [[ "${line}" == *"Running on local URL"* ]]; then
      echo ""
      echo "  ${C_VIOLET}┌─ ${C_BOLD}[READY]${C_RESET}${C_VIOLET} ───────────────────────────────────────────────────────────${C_RESET}"
      echo "  ${C_VIOLET}│  WebUI is ready. Access it at the URL shown above.${C_RESET}"
      echo "  ${C_VIOLET}└─────────────────────────────────────────────────────────────────────${C_RESET}"
      echo ""
    fi

  done
}

is_truthy() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

bootstrap_extensions_once() {
  local force_mode="${EXTENSIONS_BOOTSTRAP_FORCE}"
  local installed_count=0
  local skipped_count=0
  local failed_count=0
  local line repo_url dest_name dest_path

  mkdir -p "${EXTENSIONS_BOOTSTRAP_STATE_DIR}"
  mkdir -p "${EXTENSIONS_DIR_DEFAULT}"

  if [[ -f "${EXTENSIONS_BOOTSTRAP_SAMPLE_FILE}" && ! -e "${EXTENSIONS_BOOTSTRAP_FILE}" ]]; then
    cp -f "${EXTENSIONS_BOOTSTRAP_SAMPLE_FILE}" "${EXTENSIONS_BOOTSTRAP_FILE}"
    echo "${C_VIOLET}Created extension bootstrap list at ${EXTENSIONS_BOOTSTRAP_FILE}${C_RESET}" >&2
  fi

  if [[ -f "${EXTENSIONS_BOOTSTRAP_MARKER}" ]] && ! is_truthy "${force_mode}"; then
    echo "${C_SILVER}Extension bootstrap already completed previously; skipping one-time extension install.${C_RESET}" >&2
    return 0
  fi

  if is_truthy "${force_mode}"; then
    echo "${C_ORANGE}Extension bootstrap force mode enabled (EXTENSIONS_BOOTSTRAP_FORCE=${force_mode}); processing list now.${C_RESET}" >&2
  else
    echo "${C_VIOLET}Running one-time extension bootstrap from ${EXTENSIONS_BOOTSTRAP_FILE}${C_RESET}" >&2
  fi

  if [[ ! -f "${EXTENSIONS_BOOTSTRAP_FILE}" ]]; then
    echo "${C_ORANGE}[WARNING] Extension bootstrap list not found: ${EXTENSIONS_BOOTSTRAP_FILE}${C_RESET}" >&2
    echo "${C_ORANGE}[WARNING] Continuing startup without extension bootstrap and marking bootstrap as complete.${C_RESET}" >&2
    touch "${EXTENSIONS_BOOTSTRAP_MARKER}"
    return 0
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    repo_url="${line%%#*}"
    repo_url="${repo_url%$'\r'}"
    repo_url="${repo_url%${repo_url##*[![:space:]]}}"
    repo_url="${repo_url#${repo_url%%[![:space:]]*}}"

    if [[ -z "${repo_url}" ]]; then
      continue
    fi

    if [[ ! "${repo_url}" =~ ^https?:// ]]; then
      echo "${C_ORANGE}[WARNING] Invalid extension URL in bootstrap list (must start with http/https): ${repo_url}${C_RESET}" >&2
      ((failed_count+=1))
      continue
    fi

    dest_name="$(basename "${repo_url}")"
    dest_name="${dest_name%.git}"

    if [[ -z "${dest_name}" || "${dest_name}" == "." || "${dest_name}" == ".." ]]; then
      echo "${C_ORANGE}[WARNING] Could not derive extension directory name from URL: ${repo_url}${C_RESET}" >&2
      ((failed_count+=1))
      continue
    fi

    dest_path="${EXTENSIONS_DIR_DEFAULT}/${dest_name}"

    if [[ -d "${dest_path}" ]]; then
      echo "${C_SILVER}Extension already present, skipping clone: ${dest_name}${C_RESET}" >&2
      ((skipped_count+=1))
      continue
    fi

    echo "${C_VIOLET}Installing extension: ${repo_url}${C_RESET}" >&2
    if git clone --depth 1 "${repo_url}" "${dest_path}"; then
      ((installed_count+=1))
    else
      echo "${C_ORANGE}[WARNING] Failed to install extension: ${repo_url}${C_RESET}" >&2
      echo "${C_ORANGE}[WARNING] Continuing with next extension.${C_RESET}" >&2
      rm -rf "${dest_path}" || true
      ((failed_count+=1))
    fi
  done < "${EXTENSIONS_BOOTSTRAP_FILE}"

  touch "${EXTENSIONS_BOOTSTRAP_MARKER}"

  if [[ "${failed_count}" -gt 0 ]]; then
    echo "${C_ORANGE}Extension bootstrap finished with warnings: installed=${installed_count}, skipped=${skipped_count}, failed=${failed_count}.${C_RESET}" >&2
  else
    echo "${C_VIOLET}Extension bootstrap complete: installed=${installed_count}, skipped=${skipped_count}, failed=${failed_count}.${C_RESET}" >&2
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Build final COMMANDLINE_ARGS with auth flags appended, then launch.
#
# Recommendation: avoid placing secrets in COMMANDLINE_ARGS when possible.
# Command-line arguments can appear in logs, process lists, or screenshots
# more easily than dedicated secret-management methods.
# ─────────────────────────────────────────────────────────────────────────────
if [[ ${#AUTH_ARGS[@]} -gt 0 ]]; then
  quoted_auth_args=()
  for arg in "${AUTH_ARGS[@]}"; do
    quoted_auth_args+=("$(printf '%q' "${arg}")")
  done
  export COMMANDLINE_ARGS="${COMMANDLINE_ARGS:-} ${quoted_auth_args[*]}"
fi

bootstrap_extensions_once

if [[ -n "${COMMANDLINE_ARGS:-}" ]]; then
  echo "${C_SILVER}Starting WebUI (COMMANDLINE_ARGS set).${C_RESET}"
else
  echo "${C_SILVER}Starting WebUI (no COMMANDLINE_ARGS provided).${C_RESET}"
fi

print_launch_notice

# Launch AUTOMATIC1111 with inline output monitoring.
# A named pipe routes all WebUI output through monitor_webui_output while
# signal forwarding ensures Docker stop/kill reaches the Python process cleanly.
_MONITOR_DIR="$(mktemp -d /tmp/a1111-monitor.XXXXXX)"
_LOG_PIPE="${_MONITOR_DIR}/webui.log.pipe"
mkfifo "${_LOG_PIPE}"

_WEBUI_PID=""

_cleanup_monitor() { rm -rf "${_MONITOR_DIR}"; }
_forward_signal()  { [[ -n "${_WEBUI_PID}" ]] && kill -TERM "${_WEBUI_PID}" 2>/dev/null || true; }

trap '_cleanup_monitor' EXIT
trap '_forward_signal' TERM INT

# Start the output monitor first (reader must open the pipe before writer).
monitor_webui_output < "${_LOG_PIPE}" &
_MONITOR_PID=$!

# Launch the WebUI writing to the named pipe.
"${VENV_PYTHON}" launch.py > "${_LOG_PIPE}" 2>&1 &
_WEBUI_PID=$!

# Wait for the WebUI to exit and capture its exit code.
_WEBUI_EXIT=0
wait "${_WEBUI_PID}" || _WEBUI_EXIT=$?

# Let the monitor drain any remaining output before we exit.
wait "${_MONITOR_PID}" 2>/dev/null || true

exit "${_WEBUI_EXIT}"
