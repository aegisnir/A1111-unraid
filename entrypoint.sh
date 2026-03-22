#!/usr/bin/env bash
#
# entrypoint.sh - Root-level container entry point.
#
# Purpose:
#   Run as root just long enough to self-heal /data ownership if needed, then
#   drop privileges and exec start.sh as the application user (sdwebui / UID 99).
#
# This is the standard "init as root, drop to unprivileged user" pattern used by
# many production container images (postgres, nginx, redis, etc.). The attack
# surface of this script is intentionally minimal: stat, chown, chmod, exec.
#
# The /data bind-mount can end up owned by root when:
#   - The host directory was deleted and Docker transparently recreated it.
#   - The Unraid share path changed or was remapped.
#   - The host directory was created by a root process outside Docker.
#
# In any of those cases this script corrects ownership automatically so the
# container can start without any manual intervention from the user.
#

set -euo pipefail

# ── Color palette ────────────────────────────────────────────────────────────
# Mirror start.sh color conventions. Only emit sequences to a terminal.
if [[ -t 2 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'
  C_SILVER=$'\e[37m'; C_VIOLET=$'\e[95m'; C_ORANGE=$'\e[93m'; C_SCARLET=$'\e[91m'
else
  C_RESET='' C_BOLD='' C_SILVER='' C_VIOLET='' C_ORANGE='' C_SCARLET=''
fi

DATA_DIR="/data"
EXPECTED_UID=99
EXPECTED_GID=100

warn_repair_blocked() {
  echo "${C_SCARLET}[entrypoint] Automatic /data repair was blocked by the host filesystem or mount policy.${C_RESET}" >&2
  echo "${C_ORANGE}[entrypoint] Continuing startup so start.sh can print the final remediation steps.${C_RESET}" >&2
}

exec_as_app_user() {
  exec setpriv --reuid="${EXPECTED_UID}" --regid="${EXPECTED_GID}" --clear-groups /start.sh
}

if [[ -d "${DATA_DIR}" ]]; then
  data_owner_uid="$(stat -c '%u' "${DATA_DIR}")"
  if [[ "${data_owner_uid}" != "${EXPECTED_UID}" ]]; then
    echo "${C_ORANGE}[entrypoint] /data is owned by uid=${data_owner_uid}, expected uid=${EXPECTED_UID}.${C_RESET}" >&2
    echo "${C_ORANGE}[entrypoint] Correcting ownership and permissions under /data...${C_RESET}" >&2
    # Fix ownership on top-level dir first so the app user can write immediately.
    if ! chown "${EXPECTED_UID}:${EXPECTED_GID}" "${DATA_DIR}"; then
      warn_repair_blocked
      exec_as_app_user
    fi
    if ! chmod 775 "${DATA_DIR}"; then
      warn_repair_blocked
      exec_as_app_user
    fi
    # Correct ownership on all children that ended up under wrong ownership.
    # find limits the walk to only misowned entries so this is fast on a healthy volume.
    find "${DATA_DIR}" ! -user "${EXPECTED_UID}" -exec chown "${EXPECTED_UID}:${EXPECTED_GID}" {} + 2>/dev/null || true
    # Restore sane permission modes. Stomped permissions (e.g. chmod -R 700 on the host)
    # leave files inaccessible to the app user even with correct ownership.
    # Directories need execute bits to be traversable; files need to be readable.
    # This only runs in the degraded-ownership path, never on a healthy startup.
    find "${DATA_DIR}" -type d ! -perm -u+rwx -exec chmod u+rwx {} + 2>/dev/null || true
    find "${DATA_DIR}" -type f ! -perm -u+r   -exec chmod u+r   {} + 2>/dev/null || true
    echo "${C_VIOLET}[entrypoint] /data ownership and permissions corrected. Continuing startup.${C_RESET}" >&2
  elif [[ ! -w "${DATA_DIR}" || ! -x "${DATA_DIR}" ]]; then
    # Ownership is correct but the top-level mode was stomped (e.g. chmod 000 or chmod 700
    # on the host while the directory was already owned by uid 99).
    echo "${C_ORANGE}[entrypoint] /data is owned by the correct user but is not writable/traversable.${C_RESET}" >&2
    echo "${C_ORANGE}[entrypoint] Restoring mode 775 and fixing permission modes under /data...${C_RESET}" >&2
    if ! chmod 775 "${DATA_DIR}"; then
      warn_repair_blocked
      exec_as_app_user
    fi
    find "${DATA_DIR}" -type d ! -perm -u+rwx -exec chmod u+rwx {} + 2>/dev/null || true
    find "${DATA_DIR}" -type f ! -perm -u+r   -exec chmod u+r   {} + 2>/dev/null || true
    echo "${C_VIOLET}[entrypoint] /data permissions restored. Continuing startup.${C_RESET}" >&2
  fi
fi

# Drop privileges and exec start.sh as the application user.
# Using exec preserves the PID so Docker signals (stop/kill) reach start.sh correctly.
exec_as_app_user
