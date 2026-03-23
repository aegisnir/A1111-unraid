# Project Status

Last updated: 2026-03-23

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
  - custom `launch.py` wrapper redacts `--gradio-auth` and `--api-auth` values from startup log output

## In Progress

- Final documentation polish and consistency checks across README/template/changelog wording.
- End-to-end Unraid validation cycle (fresh install, restart, recreate, upgrade simulation).

## Remaining

- Complete and record full Unraid test pass/fail results:
  - first-start bootstrap
  - model load + generation
  - recreate/persistence
  - rebuild/upgrade simulation
- Commit pending local documentation/template edits after final review.
- Decide release posture:
  - continue local-image workflow, or
  - publish image/tag and re-point template repository for broader distribution.

## Notes

- Current local testing assumes users build on Unraid with:
  - image: `a1111-webui-aegisnir:local`
- For production-style deployments, use `WEBUI_AUTH_FILE` when possible and treat logs as sensitive.
