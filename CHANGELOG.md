# Changelog

This file is here to keep a simple record of notable changes.

I am keeping this intentionally lightweight. This is a personal, AI-assisted hobby project, so the goal is to make changes easier to follow, not to pretend there is a full formal release process behind every update.


## [Unreleased]

- API/default behavior clarification:
	- startup now treats API as explicitly opt-in: API auth injection runs only when `--api` is present in `COMMANDLINE_ARGS`
	- added startup note that API is disabled by default unless `--api` is set
	- added warning when users pass `--api-auth` without enabling `--api`
	- updated README/template docs to clarify API-off-by-default behavior and when `API_AUTH_MODE` / `API_AUTH_FILE_MODE` apply
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
	- color scheme: **violet** (`\e[95m`) for informational/safe-to-ignore messages; **orange** (`\e[93m`) for caution/warnings; **scarlet** (`\e[91m`) for critical errors; **silver** (`\e[37m`) for structural chrome (borders, labels, dim text)
	- applied consistently: ERROR lines → scarlet+bold label; WARNING lines → orange; auth/ready/venv notices → violet; borders, free-space, UMASK → silver
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
	- relaxed the sanity check to accept valid CUDA local version suffixes such as `+cu126`
	- made `xformers` truly optional in sanity checks so startup does not fail when it is unavailable
- Authentication/security defaults:
	- enabled WebUI login by default
	- mirrored credentials to API auth by default
	- added template variables for `WEBUI_USERNAME`, `WEBUI_PASSWORD`, and `API_AUTH_MODE`
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
