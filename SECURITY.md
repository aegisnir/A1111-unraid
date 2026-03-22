# Security

I care a lot about security, but I want to be clear that I am learning as I go.

This is a personal, AI-assisted hobby project. I am not a security expert, and nothing in this repository should be treated as a guarantee of safety or a complete security solution.

## Intended use

This project is primarily aimed at private, self-managed setups, especially on trusted home-lab style networks.

Public internet exposure is not the intended default use case.

## What I try to do

Where practical, I try to:
- follow safer defaults
- avoid unnecessary bloat
- document important tradeoffs
- reduce obvious risk where I can
- be honest about limitations

## Security baseline regression checklist

This is a quick pass/fail checklist for validating the repository defaults after changes.
Use it as a release gate and after any edit to runtime flags, startup scripts, or auth flow.

Automated runner:

```bash
./scripts/security-check.sh
```

### Runtime hardening defaults

- [ ] PASS if `template.xml` keeps `Privileged` set to `false`.
- [ ] PASS if default `ExtraParams` includes all of the following:
	`--read-only`, `--tmpfs /tmp:rw,noexec,nosuid,size=2g`,
	`--security-opt no-new-privileges:true`, `--cap-drop=ALL`,
	`--cap-add=CHOWN`, `--cap-add=FOWNER`, `--cap-add=SETUID`, `--cap-add=SETGID`,
	and `--pids-limit=2048` (or documented equivalent).
- [ ] PASS if defaults do not require `--privileged`.

Verification command:

```bash
grep -n "<ExtraParams>\|<Privileged>" template.xml
```

### Startup privilege model

- [ ] PASS if `entrypoint.sh` performs limited root-only setup and then drops to uid 99/gid 100 before running the app.
- [ ] PASS if `start.sh` refuses to run as root (`id -u == 0` check).
- [ ] PASS if entrypoint diagnostics include runtime context for blocked host/runtime policies (NoNewPrivs, Seccomp, CapEff).

Verification command:

```bash
grep -n "id -u\|setpriv\|NoNewPrivs\|CapEff" entrypoint.sh start.sh
```

### Authentication guardrails

- [ ] PASS if startup blocks the insecure placeholder password (`changeme-now`).
- [ ] PASS if `WEBUI_AUTH_FILE` is supported and documented as preferred for non-test deployments.
- [ ] PASS if API auth is not silently left open when WebUI auth is configured (mirror behavior or explicit override required).

Verification command:

```bash
grep -n "changeme-now\|WEBUI_AUTH_FILE\|api-auth\|gradio-auth" start.sh README.md
```

### Safety checks and docs consistency

- [ ] PASS if syntax checks pass for startup scripts:
	`bash -n entrypoint.sh && bash -n start.sh`
- [ ] PASS if template XML parses:
	`python3 -c "import xml.etree.ElementTree as ET; ET.parse('template.xml')"`
- [ ] PASS if README, template, and changelog describe the same hardening defaults.

### Current baseline (as of 2026-03-22)

- Runtime hardening defaults: PASS
- Startup privilege model: PASS
- Authentication guardrails: PASS
- Safety checks/docs consistency: PASS

## What you should assume

If you choose to use anything from this repository, I recommend assuming that:
- mistakes are possible
- important security considerations may still be missing
- your environment may have different risks than mine
- you should validate the setup against your own threat model and risk tolerance

## Reporting security concerns

If you notice a security issue, risky assumption, or something that looks clearly unsafe, constructive feedback is welcome.

For now, the simplest approach is to open an issue **only if you are comfortable discussing it publicly**.

If the concern is sensitive and should not be posted publicly, please use your judgment and avoid sharing details in a way that would unnecessarily expose other users. A more formal private reporting process may be added later if this project grows enough to justify it.

## Third-party content

Models, extensions, scripts, containers, and other third-party content should be treated as untrusted inputs unless you have reviewed and trusted them yourself.

## No guarantees

This repository is shared as-is. No guarantees are made regarding security, hardening, or safety. I will try to improve things over time, but please do not rely on this project as if it has been professionally audited or maintained.
