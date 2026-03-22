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

print_runtime_diagnostics() {
  local no_new_privs="unknown"
  local seccomp_mode="unknown"
  local cap_eff="unknown"

  if [[ -r /proc/self/status ]]; then
    no_new_privs="$(awk '/^NoNewPrivs:/ {print $2}' /proc/self/status 2>/dev/null || true)"
    seccomp_mode="$(awk '/^Seccomp:/ {print $2}' /proc/self/status 2>/dev/null || true)"
    cap_eff="$(awk '/^CapEff:/ {print $2}' /proc/self/status 2>/dev/null || true)"
    no_new_privs="${no_new_privs:-unknown}"
    seccomp_mode="${seccomp_mode:-unknown}"
    cap_eff="${cap_eff:-unknown}"
  fi

  echo "${C_SILVER}[entrypoint] Runtime diagnostics: uid=$(id -u) gid=$(id -g) NoNewPrivs=${no_new_privs} Seccomp=${seccomp_mode} CapEff=${cap_eff}${C_RESET}" >&2
  if [[ "${cap_eff}" == "0000000000000000" ]]; then
    echo "${C_ORANGE}[entrypoint] CapEff is zero (all capabilities dropped). Add required caps or remove --cap-drop=ALL.${C_RESET}" >&2
  fi
  echo "${C_ORANGE}[entrypoint] Likely causes: rootless/userns remap, no-new-privileges policy, NFS root-squash, or share ACL/mount restrictions.${C_RESET}" >&2
}

warn_repair_blocked() {
  echo "${C_SCARLET}[entrypoint] Automatic /data repair was blocked by the host filesystem or mount policy.${C_RESET}" >&2
  echo "${C_ORANGE}[entrypoint] Continuing startup so start.sh can print the final remediation steps.${C_RESET}" >&2
  print_runtime_diagnostics
}

fatal_priv_drop_blocked() {
  echo "${C_SCARLET}[entrypoint] Cannot drop privileges to uid=${EXPECTED_UID}:gid=${EXPECTED_GID}.${C_RESET}" >&2
  echo "${C_SCARLET}[entrypoint] This container runtime is blocking user/group switching (setuid/setgid).${C_RESET}" >&2
  print_runtime_diagnostics
  echo "" >&2
  echo "${C_ORANGE}[entrypoint] Host-side actions to resolve:${C_RESET}" >&2
  echo "${C_SILVER}  1) Ensure the container is not forced into a mode that strips setuid/setgid transitions.${C_RESET}" >&2
  echo "${C_SILVER}  2) Verify /data is writable by UID 99 on the host:${C_RESET}" >&2
  echo "${C_SILVER}       chown nobody:users /mnt/user/ai/data${C_RESET}" >&2
  echo "${C_SILVER}       chmod 775 /mnt/user/ai/data${C_RESET}" >&2
  echo "${C_SILVER}  3) Restart the container after applying the host fixes.${C_RESET}" >&2
  exit 1
}

exec_as_app_user() {
  # Probe first so we can print a clear remediation message rather than failing
  # with a terse setpriv error when the runtime forbids setuid/setgid operations.
  if ! setpriv --reuid="${EXPECTED_UID}" --regid="${EXPECTED_GID}" --clear-groups true >/dev/null 2>&1; then
    fatal_priv_drop_blocked
  fi
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
