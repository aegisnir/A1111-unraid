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
- Pre-release security audit: all findings fixed (26/26 checks pass)
- Release posture decided:
  - `v1.0.0` pre-release on `dev` branch
  - `main` and `:latest` frozen pending real-world validation

## In Progress

- Real-world validation of `v1.0.0` pre-release by users on Aether and beyond.

## Remaining

- Confirm `dev` pre-release is stable before promoting to `main` / `:latest`.
- CA App Store submission (deferred until `:latest` is ready).

## Notes

- Published image: `ghcr.io/aegisnir/a1111-webui-aegisnir:dev` and `:v1.0.0`
- For production-style deployments, use `WEBUI_AUTH_FILE` when possible and treat logs as sensitive.

- Container/runtime hardening implemented and documented:
  - read-only root filesystem
  - tmpfs for `/tmp`
  - `no-new-privileges`
  - `cap-drop=ALL` + minimal `cap-add` set (`CHOWN`, `FOWNER`, `SETUID`, `SETGID`)
  - default `--pids-limit=2048` with tuning guidance
- Startup/bootstrap flow hardened:
  - persistent `/data/venv`
  - persistent `/data/repositories`
  - read-only-safe symlink validation
  - free-space checks and clearer startup errors
- Authentication flow improved:
  - default WebUI login enabled
  - auth-file seeded on first launch (`admin:changeme`); startup does not block the default
  - `WEBUI_AUTH_FILE` support
  - API auth mirroring behavior controls
  - runtime auth-file sanitizer prevents Gradio crash on comments/blank lines
  - credential format validation with clear error messages
- Documentation and template alignment:
  - local test image default set to `a1111-webui-aegisnir:local`
  - README and template guidance updated for Unraid local-build workflow
  - explicit notes for expected `No checkpoints found` behavior with `--no-download-sd-model`
  - explicit recommendation to prefer `WEBUI_AUTH_FILE` for live deployments
- Licensing/docs added:
  - MIT repo license
  - AGPL copy and third-party notices included
- Icon/template updates:
  - template now uses `icon.png`
  - local-only folders (`.venv`, `.tmp-data`) cleaned up and ignored
- Log credential redaction:
  - custom `launch.py` wrapper redacts `--gradio-auth`, `--gradio-auth-path`, and `--api-auth` values from startup log output (values appear as `<redacted>`)
- Docker healthcheck:
  - `HEALTHCHECK` instruction with conservative timers tuned for A1111 workloads (10 min start grace, 2 min interval, 30 s timeout, 5 retries)
  - requires ~12 min of total unresponsiveness to flag unhealthy; avoids false positives from model loading, extension installs, etc.
  - documented in Dockerfile, README, and template.xml
- Console output:
  - semantic color palette: `C_INFO` (violet), `C_WARN` (orange), `C_CRIT` (scarlet), `C_ACCENT` (cyan)
  - variable names describe intent, not color — code is self-documenting
  - pre-launch banner with model count, first-run notice, known-warnings table, and access URL
  - inline annotations for known noisy messages (`[NOTE]`, `[KNOWN WARNING]`, `[READY]`, etc.)
- Code quality:
  - both shell scripts pass `shellcheck` cleanly
  - removed dead code (`_original_start` in launch.py, unused `C_BOLD` in entrypoint.sh)
- Pre-release security audit:
  - fixed auth file permission race: seed and runtime auth files written under `umask 077` + belt-and-suspenders `chmod 600` for upgrade safety
  - fixed stale "via runuser" comments in Dockerfile (code uses `setpriv`)
  - fixed syntax error in SECURITY.md python3 verification command
  - `scripts/security-check.sh` expanded from 17 to 26 automated checks (added: shellcheck, HEALTHCHECK presence, SUID strip, log redaction, HTTPS-only URLs, umask protection)
  - cleaned up stale variable names and clarified superseded items in CHANGELOG

## In Progress

- End-to-end Unraid validation cycle (fresh install, restart, recreate, upgrade simulation).

## Remaining

- Complete and record full Unraid test pass/fail results:
  - first-start bootstrap
  - model load + generation
  - recreate/persistence
  - rebuild/upgrade simulation
- Decide release posture:
  - continue local-image workflow, or
  - publish image/tag and re-point template repository for broader distribution.
- Potential future improvements:
  - template.xml audit against Unraid CA App Store requirements