# CA Preflight Report

Date: 2026-03-23
Repository: aegisnir/A1111-unraid
Branch: dev

Scope note: This report covers the published-image (GHCR) path used for CA readiness checks. The current local testing template default may differ.

## Gate Summary

- PASS: `entrypoint.sh` shell syntax validation (`bash -n entrypoint.sh`)
- PASS: `start.sh` shell syntax validation (`bash -n start.sh`)
- PASS: `template.xml` XML parse validation
- PASS: CA/security markers present in docs and config at the time of testing:
	- published repository string documented for CA path
	- optional `UMASK` variable in template and README guidance
	- `WEBUI_REF` build-time behavior documented
	- auth/log-redaction references present
- PASS: Licensing artifacts present:
	- `LICENSE`
	- `THIRD_PARTY_NOTICES.md`
	- `LICENSES/AGPL-3.0.txt`
- PASS: published image pullability check for `ghcr.io/aegisnir/a1111-webui-aegisnir:dev`

## Blocking Issues

None at this time for the `:dev` tag.

The `:latest` tag (`ghcr.io/aegisnir/a1111-webui-aegisnir:latest`) is not yet published.
Before broad CA submission, publish a `:latest` tag and re-run this report.

## Required Before Broad CA Submission

1. Publish a valid `:latest` image/tag to GHCR and verify pull works.
2. Re-run an Unraid template-only fresh install test.
3. Re-run container recreate/upgrade persistence test for `/data`.
4. Re-run read-only runtime smoke test on real Unraid.

## Suggested Verification Commands

```bash
docker pull ghcr.io/aegisnir/a1111-webui-aegisnir:dev
bash -n entrypoint.sh
bash -n start.sh
python3 - <<'PY'
import xml.etree.ElementTree as ET
ET.parse('template.xml')
print('template.xml parse ok')
PY
```
