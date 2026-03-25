# CA Preflight Report

Date: 2026-03-25
Repository: aegisnir/A1111-unraid
Branch: dev

Scope note: This report covers the pre-release (`:dev` / `v1.0.3`) path. `:latest` is not yet published and is deferred until `dev` proves stable in the wild.

## Gate Summary

- PASS: `entrypoint.sh` shell syntax validation (`bash -n entrypoint.sh`)
- PASS: `start.sh` shell syntax validation (`bash -n start.sh`)
- PASS: `scripts/security-check.sh` shell syntax validation (`bash -n scripts/security-check.sh`)
- PASS: `template.xml` XML parse validation
- PASS: all GitHub Actions workflow YAML files parse cleanly (`yamllint`)
- PASS: security baseline (`bash scripts/security-check.sh`) — 26/26 checks
- PASS: Dockerfile lint (`hadolint`) — no actionable warnings
- PASS: Python security scan (`bandit`) — no findings
- PASS: Dockerfile misconfiguration scan (`trivy config`) — no actionable findings
- PASS: secret detection across git history (`gitleaks`) — no findings
	- optional `UMASK` variable in template and README guidance
	- `WEBUI_REF` build-time behavior documented
	- auth/log-redaction references present
- PASS: Licensing artifacts present:
	- `LICENSE`
	- `THIRD_PARTY_NOTICES.md`
	- `LICENSES/AGPL-3.0.txt`
- PASS: published image pullability check for `ghcr.io/aegisnir/a1111-webui-aegisnir:dev`

## Blocking Issues

None at this time for the `:dev` / `v1.0.3` pre-release tag.

The `:latest` tag (`ghcr.io/aegisnir/a1111-webui-aegisnir:latest`) is intentionally not yet published.
Release strategy: `dev` branch / `:dev` tag is the pre-release used for real-world testing.
`main` branch and `:latest` tag will be promoted only after `dev` proves stable.

## Required Before Broad CA Submission (`:latest` / `main` promotion)

1. Confirm `dev` pre-release is stable after real-world testing.
2. Merge `dev` → `main`, push `:latest` image to GHCR, and verify pull works.
3. Re-run an Unraid template-only fresh install test against `:latest`.
4. Re-run container recreate/upgrade persistence test for `/data`.
5. Re-run read-only runtime smoke test on real Unraid.
6. Submit `template.xml` URL to Unraid CA repository.

## Suggested Verification Commands

```bash
docker pull ghcr.io/aegisnir/a1111-webui-aegisnir:dev
bash -n entrypoint.sh && bash -n start.sh
shellcheck -s bash entrypoint.sh start.sh scripts/security-check.sh
python3 -c "import xml.etree.ElementTree as ET; ET.parse('template.xml')"
bash scripts/security-check.sh
```
