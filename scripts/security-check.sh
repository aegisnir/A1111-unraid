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
  if grep -q '\$(id -u)' start.sh && grep -q 'Refusing to run as root' start.sh; then
    pass "start.sh refuses to run application as root"
  else
    fail "start.sh root refusal check missing"
  fi

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
  if grep -q 'WEBUI_PASSWORD="\${WEBUI_PASSWORD:-changeme-now}"' start.sh && grep -q 'WEBUI_PASSWORD is still set to the insecure default value' start.sh; then
    pass "Placeholder WEBUI password is blocked at startup"
  else
    fail "Placeholder WEBUI password guardrail missing"
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

printf 'Running security baseline checks in %s\n\n' "${ROOT_DIR}"

check_runtime_defaults
check_startup_privilege_model
check_auth_guardrails
check_syntax_and_template

printf '\nSummary: %d passed, %d failed\n' "${PASS_COUNT}" "${FAIL_COUNT}"

if [[ ${FAIL_COUNT} -ne 0 ]]; then
  exit 1
fi
