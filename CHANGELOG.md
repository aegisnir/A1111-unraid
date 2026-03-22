# Changelog

This file is here to keep a simple record of notable changes.

I am keeping this intentionally lightweight. This is a personal, AI-assisted hobby project, so the goal is to make changes easier to follow, not to pretend there is a full formal release process behind every update.


## [Unreleased]

- Startup/bootstrap hardening:
	- fixed the `start.sh` shebang/entrypoint format issue
	- made `/repositories` handling compatible with read-only container filesystems
	- redirected pip temp/cache usage into `/data`
	- added a `/data` free-space preflight and startup diagnostic
- Dependency management:
	- aligned bootstrap dependency targets with upstream `AUTOMATIC1111` `dev` expectations
	- pinned `torch`, `torchvision`, and `xformers` as an explicit tested set
	- added installed-version logging and a dependency sanity check
	- relaxed the sanity check to accept valid CUDA local version suffixes such as `+cu126`
- Authentication/security defaults:
	- enabled WebUI login by default
	- mirrored credentials to API auth by default
	- added template variables for `WEBUI_USERNAME`, `WEBUI_PASSWORD`, and `API_AUTH_MODE`
	- blocked startup when the placeholder password is unchanged unless auth is managed explicitly
- Documentation/template updates:
	- refreshed `README.md` structure and security guidance
	- documented authentication defaults and HTTPS/TLS options
	- updated `template.xml` to reflect current hardening and auth behavior
	- synchronized current defaults across docs, template, and scripts

## Notes

When practical, future entries may include:
- what changed
- why it changed
- anything that may affect setup, upgrades, or security posture
- the upstream AUTOMATIC1111 source state if it feels useful to record
