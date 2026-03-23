#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$1"
}

check_runtime_defaults() {
  local extra_params privileged

  extra_params="$(python3 - <<'PY'
import xml.etree.ElementTree as ET
root = ET.parse('template.xml').getroot()
node = root.find('ExtraParams')
print((node.text or '').strip())
PY
)"

  privileged="$(python3 - <<'PY'
import xml.etree.ElementTree as ET
root = ET.parse('template.xml').getroot()
node = root.find('Privileged')
print((node.text or '').strip().lower())
PY
)"

  if [[ "${privileged}" == "false" ]]; then
    pass "template.xml Privileged=false"
  else
    fail "template.xml Privileged is not false (found: ${privileged})"
  fi

  local required_flags=(
    "--read-only"
    "--tmpfs /tmp:rw,noexec,nosuid,size=2g"
    "--security-opt no-new-privileges:true"
    "--cap-drop=ALL"
    "--cap-add=CHOWN"
    "--cap-add=FOWNER"
    "--cap-add=SETUID"
    "--cap-add=SETGID"
    "--pids-limit=2048"
  )

  local missing=0
  for flag in "${required_flags[@]}"; do
    if [[ " ${extra_params} " == *" ${flag} "* ]]; then
      pass "ExtraParams contains ${flag}"
    else
      fail "ExtraParams missing ${flag}"
      missing=1
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    pass "Runtime hardening flags match baseline"
  fi
}

check_startup_privilege_model() {
  # shellcheck disable=SC2016 # Grepping for literal $(id -u) text, not expanding it.
  if grep -q '\$(id -u)' start.sh && grep -q 'Refusing to run as root' start.sh; then
    pass "start.sh refuses to run application as root"
  else
    fail "start.sh root refusal check missing"
  fi

  # shellcheck disable=SC2016 # Grepping for literal \${EXPECTED_UID} text, not expanding it.
  if grep -q 'setpriv --reuid="\${EXPECTED_UID}" --regid="\${EXPECTED_GID}" --clear-groups /start.sh' entrypoint.sh; then
    pass "entrypoint.sh drops privileges with setpriv before launch"
  else
    fail "entrypoint.sh setpriv privilege-drop call missing"
  fi

  if grep -q 'NoNewPrivs=' entrypoint.sh && grep -q 'CapEff=' entrypoint.sh; then
    pass "entrypoint.sh runtime diagnostics include NoNewPrivs and CapEff"
  else
    fail "entrypoint.sh runtime diagnostics missing required fields"
  fi
}

check_auth_guardrails() {
  # Auth is file-based only. Check that first-launch auth-file seeding is present.
  if grep -q 'WEBUI_AUTH_SAMPLE_FILE' start.sh && grep -q 'cp.*WEBUI_AUTH_SAMPLE_FILE.*WEBUI_AUTH_FILE' start.sh; then
    pass "Auth-file first-launch seeding is present"
  else
    fail "Auth-file first-launch seeding missing"
  fi

  # Check that auth-file presence/content validation is still enforced.
  if grep -q 'auth file is missing' start.sh && grep -q 'auth file is empty' start.sh && grep -q 'no usable credentials' start.sh; then
    pass "Auth-file presence and parseability guards are present"
  else
    fail "Auth-file presence/parseability guards missing"
  fi

  if grep -q 'WEBUI_AUTH_FILE' start.sh && grep -q 'WEBUI_AUTH_FILE' README.md; then
    pass "WEBUI_AUTH_FILE support and docs are present"
  else
    fail "WEBUI_AUTH_FILE support/docs check failed"
  fi

  if grep -q -- '--api-auth' start.sh; then
    pass "API auth handling is present in startup flow"
  else
    fail "API auth handling not found in startup flow"
  fi
}

check_syntax_and_template() {
  if bash -n entrypoint.sh && bash -n start.sh; then
    pass "Bash syntax checks passed (entrypoint.sh, start.sh)"
  else
    fail "Bash syntax check failed"
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s bash entrypoint.sh start.sh >/dev/null 2>&1; then
      pass "shellcheck passed (entrypoint.sh, start.sh)"
    else
      fail "shellcheck reported issues in startup scripts"
    fi
  else
    printf '[SKIP] shellcheck not installed\n'
  fi

  if python3 - <<'PY'
import xml.etree.ElementTree as ET
ET.parse('template.xml')
PY
  then
    pass "template.xml parses successfully"
  else
    fail "template.xml parse failed"
  fi

  if grep -RIn "mktemp -u" start.sh entrypoint.sh >/dev/null 2>&1; then
    fail "Unsafe mktemp -u usage detected in startup scripts"
  else
    pass "No unsafe mktemp -u usage in startup scripts"
  fi
}

check_build_hardening() {
  # HEALTHCHECK must be present with a start-period of at least 300s.
  if grep -q 'HEALTHCHECK' Dockerfile; then
    local start_period
    start_period="$(grep 'start-period' Dockerfile | grep -oP '\d+(?=s)' | head -1)"
    if [[ -n "${start_period}" && "${start_period}" -ge 300 ]]; then
      pass "Dockerfile HEALTHCHECK present with start-period=${start_period}s (>= 300s)"
    else
      fail "Dockerfile HEALTHCHECK start-period too short or not found (found: ${start_period:-none})"
    fi
  else
    fail "Dockerfile HEALTHCHECK instruction missing"
  fi

  # SUID/SGID bits should be stripped at build time.
  if grep -q 'chmod a-s' Dockerfile; then
    pass "Dockerfile strips SUID/SGID bits at build time"
  else
    fail "Dockerfile SUID/SGID strip not found"
  fi

  # launch.py must contain the credential redaction function.
  if grep -q '_redact_cli_args' WebUI/launch.py; then
    pass "launch.py contains credential redaction logic"
  else
    fail "launch.py credential redaction (_redact_cli_args) not found"
  fi
}

check_credential_handling() {
  # Auth file writes must use umask 077 to avoid permission race.
  if grep -q 'umask 077' start.sh; then
    pass "Auth file writes use restrictive umask (077)"
  else
    fail "Auth file writes missing umask 077 protection"
  fi

  # Extension bootstrap must require HTTPS (not HTTP).
  # The URL validation regex in start.sh should match ^https:// only, not ^https?://.
  if grep -q '\^https://' start.sh && ! grep -q 'https?://' start.sh; then
    pass "Extension bootstrap requires HTTPS-only URLs"
  else
    fail "Extension bootstrap may accept plain HTTP URLs"
  fi
}

printf 'Running security baseline checks in %s\n\n' "${ROOT_DIR}"

check_runtime_defaults
check_startup_privilege_model
check_auth_guardrails
check_syntax_and_template
check_build_hardening
check_credential_handling

printf '\nSummary: %d passed, %d failed\n' "${PASS_COUNT}" "${FAIL_COUNT}"

if [[ ${FAIL_COUNT} -ne 0 ]]; then
  exit 1
fi
