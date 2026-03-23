# Project Status

> For change history and last updated date, see [git log](../../commits/dev).

## Completed

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
  - custom `launch.py` wrapper redacts `--gradio-auth`, `--gradio-auth-path`, `--api-auth`, and `--api-auth-path` values from startup log output (values appear as `<redacted>`)
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
  - GitHub Actions CI workflow for automated build/lint/security checks
  - template.xml audit against Unraid CA App Store requirements

## Notes

- Current local testing assumes users build on Unraid with:
  - image: `a1111-webui-aegisnir:local`
- For production-style deployments, use `WEBUI_AUTH_FILE` when possible and treat logs as sensitive.
