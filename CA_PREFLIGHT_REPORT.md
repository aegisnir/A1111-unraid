# CA Preflight Report

Date: 2026-03-25
Repository: aegisnir/A1111-unraid
Branch: main

Scope note: This report covers the stable release (`:latest` / `v1.0.3`) path on the `main` branch. The `:dev` tag continues to track pre-release development on the `dev` branch.

## Gate Summary

- PASS: `entrypoint.sh` shell syntax validation (`bash -n entrypoint.sh`)
- PASS: `start.sh` shell syntax validation (`bash -n start.sh`)
- PASS: `scripts/security-check.sh` shell syntax validation (`bash -n scripts/security-check.sh`)
- PASS: `template.xml` XML parse validation
- PASS: all GitHub Actions workflow YAML files parse cleanly (`yamllint`)
- PASS: security baseline (`bash scripts/security-check.sh`): 29/29 checks
- PASS: Dockerfile lint (`hadolint`): no actionable warnings
- PASS: Python security scan (`bandit`): no findings
- PASS: Dockerfile misconfiguration scan (`trivy config`): no actionable findings
- PASS: secret detection across git history (`gitleaks`): no findings
	- optional `UMASK` variable in template and README guidance
	- `WEBUI_REF` build-time behavior documented
	- auth/log-redaction references present
- PASS: Licensing artifacts present:
	- `LICENSE`
	- `THIRD_PARTY_NOTICES.md`
	- `LICENSES/AGPL-3.0.txt`
- PENDING: published image pullability check for `ghcr.io/aegisnir/a1111-webui-aegisnir:latest` (image not yet pushed)

## Blocking Issues

1. `:latest` image has not yet been pushed to GHCR. Run `bash scripts/build-push.sh` from the `main` branch to publish.

## Remaining Before CA Submission

1. Push `:latest` image to GHCR and verify pull works.
2. Re-run an Unraid template-only fresh install test against `:latest`.
3. Re-run container recreate/upgrade persistence test for `/data`.
4. Re-run read-only runtime smoke test on real Unraid.
5. Submit `template.xml` URL to Unraid CA repository.

## Suggested Verification Commands

```bash
docker pull ghcr.io/aegisnir/a1111-webui-aegisnir:latest
bash -n entrypoint.sh && bash -n start.sh
shellcheck -s bash entrypoint.sh start.sh scripts/security-check.sh
python3 -c "import xml.etree.ElementTree as ET; ET.parse('template.xml')"
bash scripts/security-check.sh
```
