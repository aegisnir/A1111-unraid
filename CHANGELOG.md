# Changelog

This file is here to keep a simple record of notable changes.

I am keeping this intentionally lightweight. This is a personal, AI-assisted hobby project, so the goal is to make changes easier to follow, not to pretend there is a full formal release process behind every update.


## [Unreleased]

- Pin `torch` 2.11.0→2.10.0 and `torchvision` 0.26.0→0.25.0: `xformers` 0.0.35's cu130
  wheel was compiled against PyTorch 2.10.0; mismatched versions prevent CUDA extensions
  from loading and disable memory-efficient attention

---

## [v1.0.2] - 2026-03-25

- Upgrade CUDA base image from `nvidia/cuda:12.9.1-runtime-ubuntu22.04` to `13.0.2`;
  update PyTorch index URL from `cu128` to `cu130`; bump pinned dependency versions:
  `torch` 2.7.0→2.11.0, `torchvision` 0.22.0→0.26.0, `xformers` 0.0.30→0.0.35
  - Requires host driver ≥ 570 (confirmed compatible with driver 595.45.04)
  - `cu130` wheels are the highest available for both PyTorch 2.10 and 2.11
  - xformers 0.0.34+ uses stable PyTorch ABI — binary built for 2.10 runs on 2.11+
  - CUDA 13.0.2 is 5+ months old and battle-tested; chosen over 13.2.0 (8 days old, zero driver headroom at ≥595)

- CI: extended static analysis added to push/PR workflow: `hadolint` (Dockerfile lint),
  `bandit` (Python security scan), `yamllint` (YAML validation), `trivy config`
  (Dockerfile misconfiguration scan), `gitleaks` (secret detection across git history)
  - `.hadolint.yaml`: suppresses DL3008 (apt version pins) — impractical for system packages
  - `.gitleaks.toml`: allowlists `webui-auth.txt` as an intentional default-credentials placeholder
  - `.trivyignore`: allowlists DS002 (run as root) — container uses entrypoint privilege-drop pattern
  - `.yamllint.yml`: relaxes line-length to 120 and removes document-start requirement
- CI: add `trivy-image.yml` — weekly scheduled CVE scan of the published `:dev` image;
  filters to fixable HIGH/CRITICAL findings only to reduce base-image noise
- Add `.github/dependabot.yml` — automated version-bump PRs for GitHub Actions and
  Docker base image (weekly cadence)

---

## [v1.0.1] - 2026-03-24

- Fix: SC2015 shellcheck warnings in `_cleanup_monitor` — `A && B || true` pattern
  rewritten as explicit `if/fi`; logic was correct but non-idiomatic and caused the
  automated security baseline to fail
- Fix: `--port=NNNN` equals-separated form ignored by `_poll_for_ready` — was silently
  falling back to port 7860; now handles both `--port 7861` and `--port=7861` forms
- Fix: inverted awk exit codes in auth credential format validation — logic was correct
  but coded as `bad?0:1` with a plain `if`, which is counter-intuitive and risky for
  maintainers; corrected to `bad?1:0` with matching `if !` guard
- Add: `extensions` symlink startup validation — validates presence and correct target,
  consistent with the existing `repositories` and `config_states` checks
- Add: `/data/tmp` purged on startup to prevent partial pip downloads and extracted
  archives from accumulating silently across restarts and crashes
- Dockerfile: OCI image labels added (`org.opencontainers.image.*`) — links the GHCR
  package to the source repository, exposes license metadata, and gives vulnerability
  scanners the source context they need
- Dockerfile: `IMAGE_VERSION` build ARG added; pass `--build-arg IMAGE_VERSION=v1.0.1`
  at build time to embed the version in the `org.opencontainers.image.version` label
- Dockerfile: HEALTHCHECK section now documents the known hardcoded-port limitation
  (Docker HEALTHCHECK CMD cannot read runtime env vars; port 7860 is baked in)
- CI: added `.github/workflows/ci.yml` — runs `scripts/security-check.sh` on every
  push and pull request to `dev` and `main`; installs shellcheck as a prerequisite

---

## [v1.0.0] - 2026-03-24

> First pre-release. Published on the `dev` branch/tag. Not yet promoted to `main` or `:latest` — pending real-world validation.

- Automatic WebUI restart loop:
	- container now automatically restarts the WebUI process when it exits, instead of letting the container stop
	- distinguishes deliberate stops (SIGTERM from Docker stop/Unraid) from crashes or clean exits ("Apply and quit")
	- SIGTERM sets a flag that suppresses restart and lets the container exit cleanly
	- clean exit (code 0, e.g. "Apply and quit"): flat delay before restart (`RESTART_DELAY`, default 5 s), resets crash backoff counter
	- crash (non-zero exit code): exponential backoff starting at `RESTART_DELAY`, doubling each attempt up to `RESTART_DELAY_MAX` (default 60 s)
	- new env vars: `RESTART_ON_EXIT` (default `1`), `RESTART_DELAY` (default `5`), `RESTART_DELAY_MAX` (default `60`), `RESTART_MAX_ATTEMPTS` (default `0` = unlimited)
	- startup banner only printed on first start; subsequent restarts print a compact restart notice with attempt count and delay
- Appdata split extended — A1111 user config files moved to `/config/a1111/` (appdata):
	- `config.json` — all Settings tab values, including settings added by extensions via the A1111 opts API
	- `ui-config.json` — UI component defaults (slider ranges, textbox sizes)
	- `styles.csv` — saved prompt styles
	- `config_states/` — extension enable/disable snapshots
	- Symlinks are created at startup so A1111 finds everything at its expected paths under `/data`
	- Automatic migration: any existing files/directories at the old `/data/` locations are moved on first start with the new image; appdata copy wins if both exist
	- Extension-specific standalone state files (e.g. civitai browser favourites/ban lists) remain under `/data/extensions/<name>/` — covered by `/data` persistence, not appdata backup
	- Combined with the existing auth file split, the full `/data` volume can now be wiped and the container rebuilt without losing any settings; only models need to be re-downloaded

- Image: added `build-essential` and `python3-dev` to the base image apt packages so that Python extensions requiring C/C++ compilation (e.g. `hnswlib` used by `sd-webui-infinite-image-browsing`) build successfully without needing `IIB_SKIP_OPTIONAL_DEPS=1`

- Console output revisions:
	- Color detection changed from `[[ -t 2 ]]` tty guard to always-on ANSI; suppress with `NO_COLOR=1` or `TERM=dumb` (the tty check returned false in Docker when no TTY is attached, which is the normal case in Unraid's log viewer — all colors were being stripped silently)
	- `C_INFO` changed from `\e[95m` (bright magenta, rendered poorly or invisibly in some terminals) to `\e[35m` (regular magenta/violet, reliably visible)
	- All annotation boxes fully closed: content lines are now padded to exact inner width and have a right-side `│` border; previous implementation left the right side open
	- READY banner replaced log-line match on `Running on local URL` with an independent background poller (`_poll_for_ready`) that uses bash's `/dev/tcp` built-in to probe the port every 5 seconds; the log-line approach was silently failing across Gradio versions
	- READY banner now auto-detects the container's own outbound LAN IP (works in macvlan / Unraid br0 / `--network=host`); shows `http://<your-unraid-ip>:<port>/` placeholder in standard Docker bridge/NAT mode where the host's IP is not discoverable from inside the container

- Authentication behavior update:
	- removed startup hard-stop for auth files containing password `changeme`
	- startup now allows first-launch default login `admin:changeme` and logs continue normally
	- updated README/template/security metadata to document default end-user login behavior and recommended password change after first login
- Fixes:
	- fixes startup failure where `WEBUI_AUTH_FILE` could not be auto-seeded because the sample file was missing from the image
	- removed unsupported `--extensions-dir` launch argument injection (newer A1111 no longer accepts this flag)
	- added auth-file credential format validation in startup to fail fast with a clear CRITICAL error instead of Gradio `IndexError` on malformed entries
	- startup now writes a sanitized runtime auth file (comments/blank lines removed) before passing `--gradio-auth-path`, preventing Gradio `IndexError` from commented auth templates
- Security audit and documentation hardening:
	- updated `scripts/security-check.sh` `check_auth_guardrails` to test current auth-file changeme guard instead of the removed `WEBUI_PASSWORD` variable (previous check always failed after auth refactor)
	- updated `SECURITY.md` checklist to reference `changeme` auth-file guard instead of stale `changeme-now` WEBUI_PASSWORD reference; updated verification grep command to match
	- removed "WORK IN PROGRESS" banner from README top (was blocking CA App Store readiness)
	- added explicit security warning in README about `--api-auth` credentials being exposed in `COMMANDLINE_ARGS` env var when API mirroring is active (known upstream A1111 limitation)
	- cleaned up duplicate intro sentence in README auth section
- Authentication defaults and hardening:
        - switched startup to auth-file-first workflow using `WEBUI_AUTH_FILE` (default `/config/auth/webui-auth.txt`)
        - added first-run auth-file seeding from repository template `webui-auth.txt` when target file is missing
        - removed `WEBUI_USERNAME` / `WEBUI_PASSWORD` template fields to avoid credential leakage from variable-based auth paths
        - updated README/template metadata with explicit auth-file path, format, and safety-guard guidance
- API/default behavior clarification:
	- startup now treats API as explicitly opt-in: API auth injection runs only when `--api` is present in `COMMANDLINE_ARGS`
	- added startup note that API is disabled by default unless `--api` is set
	- added warning when users pass `--api-auth` without enabling `--api`
	- updated README/template docs to clarify API-off-by-default behavior and when `API_AUTH_FILE_MODE` applies
	- documented extension-access tradeoff: omitting `--enable-insecure-extension-access` does not block existing extension runtime; it mainly limits install/update/management from the WebUI
	- enabled `--enable-insecure-extension-access` by default in template and Dockerfile fallback args for this personal project workflow
	- added explicit README risk callouts for insecure extension access and documented what `--allow-code` enables vs what leaving it unset prevents
- Security review workflow:
	- added a reusable "Security baseline regression checklist" section to `SECURITY.md` with pass/fail gates for runtime hardening defaults, privilege-drop model, auth guardrails, and docs consistency
	- added quick verification commands for template flags, startup scripts, auth behavior, bash syntax, and XML parsing
	- added a README pointer to the checklist so it can be used as a standard pre-release/pre-merge safety check
	- added `scripts/security-check.sh` as a one-command automated runner for the checklist checks (runtime flags, privilege model, auth guardrails, bash syntax, and XML parse)
	- hardened startup pipe handling in `start.sh` by replacing `mktemp -u` with secure `mktemp -d` + `mkfifo` path creation
	- added an automated gate in `scripts/security-check.sh` to fail if unsafe `mktemp -u` usage appears in startup scripts
- Startup permission-repair fallback:
	- `entrypoint.sh` no longer aborts immediately if host policy blocks `chown` or `chmod` on `/data`
	- when automatic repair is denied (`Operation not permitted`), entrypoint now prints a clear host-filesystem warning and continues into `start.sh`
	- the container now fails through the existing `start.sh` remediation path instead of crashing early on the raw `chmod` error
	- privilege drop now uses `setpriv --reuid=99 --regid=100 --clear-groups` instead of `runuser`, avoiding `runuser: cannot set groups: Operation not permitted` on restricted runtimes
	- `entrypoint.sh` now preflights `setpriv` before launching `start.sh`; if setuid/setgid is blocked (`setresuid failed` class), it prints explicit host-side remediation and exits cleanly
	- added a concise entrypoint runtime diagnostics line (`NoNewPrivs`, `Seccomp`, `CapEff`) plus likely-cause hints when permission repair or privilege-drop operations are blocked
	- diagnostics now explicitly flag `CapEff=000...0` as "all capabilities dropped" and suggest adjusting capability flags
	- template defaults were corrected to keep least-privilege hardening while preserving required startup operations: `--cap-drop=ALL` plus `--cap-add=CHOWN,FOWNER,SETUID,SETGID`
- Console color palette:
	- added ANSI color output to `start.sh` and `entrypoint.sh` for terminal sessions (plain in log files via `[[ -t 2 ]]` guard)
	- color scheme: **violet** (`\e[95m`) for informational; **orange** (`\e[93m`) for caution/warnings; **scarlet** (`\e[91m`) for critical errors; **cyan** (`\e[96m`) for accent/highlights (URLs, borders, structural chrome)
	- color variables use semantic names (`C_INFO`, `C_WARN`, `C_CRIT`, `C_ACCENT`) so code intent is self-documenting regardless of actual ANSI color
	- applied consistently: ERROR lines → C_CRIT+bold label; WARNING lines → C_WARN; auth/ready/venv notices → C_INFO; borders, URLs, highlights → C_ACCENT
	- `print_launch_notice` banner and all inline annotation boxes (`[NOTE]`, `[KNOWN WARNING]`, `[GPU MEMORY ERROR]`, `[GPU NOT DETECTED]`, `[READY]`) are fully color-coded
	- `entrypoint.sh` uses the same palette for its ownership/permission repair notices
- Console output improvements:
	- added pre-launch banner (`print_launch_notice`) showing: model checkpoint count, first-run bootstrap notice, known-harmless warnings table, and access URL reminder
	- added inline output monitor (`monitor_webui_output`) that annotates known noisy lines in real time:
		- `timm.models.layers` FutureWarning → `[NOTE] ↑ Harmless upstream deprecation. Safe to ignore.`
		- `TypedStorage is deprecated` → `[NOTE] ↑ Harmless internal PyTorch notice. Safe to ignore.`
		- `No checkpoints found` → `[KNOWN WARNING]` box with fix instructions
		- `CUDA out of memory` → `[GPU MEMORY ERROR]` box with tuning tips
		- `torch.cuda.is_available() = False` / `Torch is not able to use GPU` → `[GPU NOT DETECTED]` box with host-side check steps
		- `Running on local URL` → `[READY]` box confirming WebUI is accepting connections
	- WebUI is now launched via a named pipe with signal forwarding so Docker `stop`/`kill` reaches the Python process cleanly while monitoring is active
- Self-healing startup:
	- added `entrypoint.sh` as a root-level container entrypoint that automatically corrects `/data` ownership before dropping to the unprivileged app user (`sdwebui` / UID 99)
	- uses the standard "init as root, drop privileges" pattern (same as postgres, nginx, redis)
	- handles two distinct degraded states independently:
		1. **Wrong ownership** (e.g. Docker recreated `/data` as root): `chown` top-level + `find`-based ownership repair on all children + mode restoration for any that lost traversal/read bits
		2. **Correct ownership but stomped modes** (e.g. `chmod -R 000` on the host while already owned by UID 99): `chmod 775` top-level + `find`-based permission repair restoring `u+rwx` on directories and `u+r` on files
	- the `find` walks are filtered to only process entries that actually need fixing, so they are fast on healthy volumes and no-ops when everything is correct
	- `start.sh` still has a fallback hard-error for cases that cannot be auto-fixed (NFS root squash, SELinux, or `chown` silently failing)
	- `start.sh` now auto-creates standard `/data` subdirectories (`models/Stable-diffusion`, `models/VAE`, `models/Lora`, `outputs`) on every startup so a bare or restored volume gets the expected layout without user action
- Startup/bootstrap hardening:
	- fixed the `start.sh` shebang/entrypoint format issue
	- made `/repositories` handling compatible with read-only container filesystems
	- redirected pip temp/cache usage into `/data`
	- added a `/data` free-space preflight and startup diagnostic
	- added optional `UMASK` support via template variable (not enforced by default)
	- hardened auth arg injection quoting to better handle spaces/special characters
- Dependency management:
	- aligned bootstrap dependency targets with upstream `AUTOMATIC1111` `dev` expectations
	- pinned `torch`, `torchvision`, and `xformers` as an explicit tested set
	- added installed-version logging and a dependency sanity check
- Docker healthcheck:
	- added `HEALTHCHECK` instruction to Dockerfile with conservative timers tuned for A1111 workloads
	- 10 min start-period grace for first-run bootstrap, 2 min interval, 30 s timeout, 5 retries
	- requires ~12 min of total unresponsiveness to flag unhealthy — avoids false positives from model loading, extension installs, image browser, etc.
	- healthcheck is informational only; Docker/Unraid will not auto-restart the container
- Code quality:
	- both shell scripts pass `shellcheck` cleanly (fixed SC2295 quoting bug, suppressed SC2317 false positives on trap callbacks, fixed SC2015 `A && B || C` pattern)
	- removed unused `_original_start` variable from `launch.py`
	- updated template.xml and README to document healthcheck behavior and tuning rationale
	- relaxed the sanity check to accept valid CUDA local version suffixes such as `+cu126`
	- made `xformers` truly optional in sanity checks so startup does not fail when it is unavailable
- Pre-release security audit:
	- fixed auth file permission race: auth file seed and runtime auth file are now written under `umask 077` so credentials are never world-readable even briefly
	- fixed stale "via runuser" references in Dockerfile (code uses `setpriv`)
	- fixed missing closing quote in SECURITY.md python3 verification command
	- expanded `scripts/security-check.sh` with checks for: shellcheck, HEALTHCHECK presence, SUID bit strip, log redaction, HTTPS-only extension URLs, and auth file permission hardening
	- cleaned up stale variable names in CHANGELOG (`API_AUTH_MODE` → `API_AUTH_FILE_MODE`, clarified superseded `WEBUI_USERNAME`/`WEBUI_PASSWORD`)
	- updated `COMMANDLINE_ARGS` code comment to honestly describe the `--api-auth` env var exposure tradeoff
- Authentication/security defaults:
	- enabled WebUI login by default
	- mirrored credentials to API auth by default
	- *(superseded)* early iterations used `WEBUI_USERNAME` / `WEBUI_PASSWORD` template variables; these were removed in favor of auth-file workflow (`WEBUI_AUTH_FILE`) to avoid credential leakage via env vars
	- blocked startup when the placeholder password is unchanged unless auth is managed explicitly
	- made startup auth log redaction patch read-only-safe by patching in memory
- Documentation/template updates:
	- refreshed `README.md` structure and security guidance
	- documented authentication defaults and HTTPS/TLS options
	- updated `template.xml` to reflect current hardening and auth behavior
	- synchronized current defaults across docs, template, and scripts
	- added third-party licensing notices (`THIRD_PARTY_NOTICES.md`, AGPL copy)
	- switched template/runtime naming to `a1111-webui-aegisnir` for local Unraid testing consistency
	- added default `--pids-limit=2048` and documented how to tune PID limits in Unraid Extra Parameters
	- added template links to the GitHub README for quick user access
	- documented that `No checkpoints found` is expected with `--no-download-sd-model` until a model is added
	- added stronger guidance to prefer `WEBUI_AUTH_FILE` for live deployments and treat `WEBUI_PASSWORD` as convenience/testing
	- added warnings that credentials may appear in logs in some startup paths when password-based auth is used

## Notes

When practical, future entries may include:
- what changed
- why it changed
- anything that may affect setup, upgrades, or security posture
- the upstream AUTOMATIC1111 source state if it feels useful to record
