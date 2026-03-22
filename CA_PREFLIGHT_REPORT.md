# CA Preflight Report

Date: 2026-03-22
Repository: aegisnir/A1111-unraid
Branch: main

## Gate Summary

- PASS: `start.sh` shell syntax validation (`bash -n start.sh`)
- PASS: `template.xml` XML parse validation
- PASS: CA/security markers present in docs and config:
	- published repository string in template
	- optional `UMASK` variable in template and README guidance
	- `WEBUI_REF` build-time behavior documented
	- auth/log-redaction references present
- PASS: Licensing artifacts present:
	- `LICENSE`
	- `THIRD_PARTY_NOTICES.md`
	- `LICENSES/AGPL-3.0.txt`
- FAIL: published image pullability check for `ghcr.io/aegisnir/a1111-webui-aegisnir:latest`
	- result: `Error response from daemon: manifest unknown`

## Blocking Issue

1. The current template default image reference is not pullable at the tested tag:
	- `ghcr.io/aegisnir/a1111-webui-aegisnir:latest`
	 - Docker daemon response: `manifest unknown`

## Required Before Broad CA Submission

1. Publish a valid image/tag to GHCR and verify pull works.
2. Re-run an Unraid template-only fresh install test.
3. Re-run container recreate/upgrade persistence test for `/data`.
4. Re-run read-only runtime smoke test on real Unraid.

## Suggested Verification Commands

```bash
docker pull ghcr.io/aegisnir/a1111-webui-aegisnir:latest
bash -n start.sh
python3 - <<'PY'
import xml.etree.ElementTree as ET
ET.parse('template.xml')
print('template.xml parse ok')
PY
```
