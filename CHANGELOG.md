# Changelog

This file is here to keep a simple record of notable changes.

I am keeping this intentionally lightweight. This is a personal, AI-assisted hobby project, so the goal is to make changes easier to follow, not to pretend there is a full formal release process behind every update.


## [Unreleased]

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
