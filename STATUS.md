# Project Status

> For change history and last updated date, see [git log](../../commits/dev).

## Completed

- Container/runtime hardening implemented and documented:
  - read-only root filesystem
  - tmpfs for `/tmp`
  - `no-new-privileges`
  - `cap-drop=ALL` + minimal `cap-add` set (`CHOWN`, `FOWNER`, `SETUID`, `SETGID`)
  - default `--pids-limit=2048` with tuning guidance
- Automatic WebUI restart loop:
  - container restarts the WebUI process automatically on crash or clean exit ("Apply and quit")
  - SIGTERM from Docker stop/Unraid exits the container cleanly without restart
  - crash (non-zero exit): exponential backoff up to `RESTART_DELAY_MAX`
  - clean exit (code 0): flat `RESTART_DELAY` before restart
  - configurable via: `RESTART_ON_EXIT`, `RESTART_DELAY`, `RESTART_DELAY_MAX`, `RESTART_MAX_ATTEMPTS`
- Appdata/data split:
  - `/config/a1111/` holds A1111 config files (config.json, ui-config.json, styles.csv, config_states) — backed up with appdata
  - `/data/` holds models, outputs, venv, extensions — large working set, outside appdata
  - auth file at `/config/auth/webui-auth.txt`
  - symlinks created at startup so A1111 finds everything at expected paths
  - automatic migration from old `/data/` paths on first start with new image
- Startup/bootstrap flow hardened:
  - persistent `/data/venv` and `/data/repositories`
  - read-only-safe symlink validation
  - free-space checks and clearer startup errors
  - `build-essential` + `python3-dev` in base image so C extension builds (e.g. hnswlib) work without workarounds
- Authentication flow improved:
  - default WebUI login enabled; auth-file seeded on first launch (`admin:changeme`)
  - `WEBUI_AUTH_FILE` support
  - API auth mirroring behavior controls
  - runtime auth-file sanitizer prevents Gradio crash on comments/blank lines
  - credential format validation with clear error messages
- Documentation and template:
  - template defaults to `ghcr.io/aegisnir/a1111-webui-aegisnir:dev`
  - README Quick Start updated with manual template import instructions (not yet in CA)
  - all `blob/main/` links in template.xml corrected to `blob/dev/`
  - explicit notes for expected `No checkpoints found` behavior with `--no-download-sd-model`
- Licensing/docs added:
  - MIT repo license
  - AGPL copy and third-party notices included
- Log credential redaction:
  - custom `launch.py` wrapper redacts sensitive auth flag values from log output
- Docker healthcheck:
  - `HEALTHCHECK` with conservative timers (10 min start grace, 2 min interval, 30 s timeout, 5 retries)
- Console output:
  - semantic color palette, pre-launch banner, inline annotations for known noisy messages
  - independent background port poller for `[READY]` banner
- Code quality:
  - both shell scripts pass `shellcheck` cleanly
- GitHub Actions CI:
  - automated shellcheck + security baseline checks run on push/PR to `dev` and `main`
  - extended with: `hadolint` (Dockerfile lint), `bandit` (Python security scan),
    `yamllint` (YAML validation), `trivy config` (Dockerfile misconfiguration scan),
    `gitleaks` (secret detection across git history)
  - `trivy-image.yml`: weekly scheduled CVE scan of the published GHCR image (fixable HIGH/CRITICAL only)
  - `.github/dependabot.yml`: automated version-bump PRs for GitHub Actions and Docker base image (weekly)
- Pre-release security audit: all findings fixed (29/29 checks pass)
- CUDA base upgraded from `nvidia/cuda:12.9.1-runtime-ubuntu22.04` to `13.0.2`;
  PyTorch index updated from `cu128` to `cu130`; pinned versions bumped:
  `torch` 2.7.0→2.10.0, `torchvision` 0.22.0→0.25.0, `xformers` 0.0.30→0.0.35
- xformers 0.0.35 CUDA extension fix: `torch` pinned back from 2.11.0→2.10.0 and
  `torchvision` from 0.26.0→0.25.0 — the cu130 wheel was compiled against 2.10.0;
  mismatched versions silently disabled memory-efficient attention
- xformers pip install fix: added `--extra-index-url` to the xformers install in `start.sh`
  so pip resolves the cu130 wheel from the PyTorch index instead of the cu128 wheel from PyPI;
  without this flag the correct torch version alone is not enough — CUDA extensions still fail
- Real-world validation of v1.0.3 completed on RTX 4090 hardware:
  - `torch=2.10.0+cu130`, `torchvision=0.25.0+cu130`, `xformers=0.0.35` all confirmed loading
  - xformers CUDA extensions confirmed: no `xFormers can't load C++/CUDA extensions` warning
  - `[READY]` banner confirmed firing; WebUI confirmed reachable
- Log/monitor improvements (all from real-hardware validation findings):
  - `scripts/build-push.sh` added — repeatable build+push helper for both `:dev` and `:v1.0.3` tags
  - pre-launch known-harmless table expanded: `resume_download` FutureWarning, CivitAI Shortcut
    `[ERROR]` schema notice, CivitAI Browser+ Basemodel fetch error
  - `[XFORMERS MISMATCH]` inline handler added: fires when stale cu128 wheel is detected,
    shows explicit venv-delete remediation
  - `[GPU MEMORY ERROR]` box updated with `PYTORCH_ALLOC_CONF=expandable_segments:True` as lead tip,
    Hires. fix callout, `--medvram` fallback; stale xformers tip replaced
  - Startup pause notice added after banner (gap lasts several minutes; prevents premature restarts)
  - All annotation box colors fixed: color set once on `┌` line, reset once on `└` line
- Release posture decided:
  - `v1.0.3` pre-release on `dev` branch (supersedes broken `v1.0.2`)
  - `main` and `:latest` frozen pending real-world validation

## In Progress

- Merging `dev` → `main` via PR #6. All CI checks pass. Blocked by branch protection:
  unresolved Copilot review conversations must be dismissed before PR can be merged.
  Required approving review count set to 0. Resolve open threads in PR #6 Files view, then merge.

## Remaining

- Resolve open conversations on PR #6 and complete the merge.
- Build and push `:latest` + `:v1.0.3` from `main` on Aether (`git pull && bash scripts/build-push.sh`).
- Re-run fresh install, persistence, and read-only smoke tests against `:latest`.
- CA App Store submission (deferred until `:latest` is ready).
- Close remaining Dependabot PRs (#1, #2, #4).

## Session 13 Changes (dev → main promotion prep)

- `template.xml`: all `dev` branch refs updated to `main`/`latest`
  (`<Repository>`, `<Icon>`, Description image tag, Overview image/README links, `<Changelog>`, `<TemplateURL>`)
- `scripts/build-push.sh`: now branch-aware — pushes `:latest` + `:<version>` on `main`, `:dev` + `:<version>` on dev
- PR #6 opened: dev → main, all CI checks pass

## Notes

- Published image: `ghcr.io/aegisnir/a1111-webui-aegisnir:dev` and `:v1.0.3` (`:v1.0.2` superseded — broken xformers)
- For production-style deployments, use `WEBUI_AUTH_FILE` when possible and treat logs as sensitive.
