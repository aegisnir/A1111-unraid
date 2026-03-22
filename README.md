
# ⚠️⚠️⚠️ WORK IN PROGRESS ⚠️⚠️⚠️

Do not use this yet unless the work-in-progress notice is removed.

# Stable Diffusion WebUI (AUTOMATIC1111) for Unraid

This repository packages AUTOMATIC1111 Stable Diffusion WebUI for Unraid with NVIDIA GPU support in mind. The goal is to keep it practical, reasonably lightweight, and more security-conscious than a throwaway personal build.

This is a personal hobby project. It is heavily AI-assisted, and it is also a learning experience for me. I care a lot about security and I am trying to make thoughtful choices, but I am not a programmer or security expert, so mistakes and weak assumptions are possible. If you notice something I could do better, I welcome constructive feedback.

**Important:** As of March 2026, new installs require the `dev` branch of AUTOMATIC1111 due to a missing dependency repository. The main branch will fail to start. See below for updated instructions.

> ⚠️ Public internet exposure is **not** the intended use case.
> If you expose this beyond a trusted network, the risk profile changes significantly and you should make those decisions carefully for your own environment.

## Performance and Security Notes

- For best performance, use SSD storage for your `/data` directory. This speeds up model loading, image generation, and cache operations.
- Keep your Unraid host OS and NVIDIA drivers up to date for maximum compatibility, performance, and security.
- Only install extensions and models from trusted sources. Third-party code can compromise the security of your system.

## Quick start

These are the defaults I would start with on a trusted LAN.

1. Install the template from the Unraid CA app flow (or import `template.xml`).
2. For local testing, confirm the image repository is set to `a1111-webui-aegisnir:local`.
	For a published-image workflow, set it to `ghcr.io/aegisnir/a1111-webui-aegisnir:latest`.
3. Use **Bridge** networking.
4. Map container port `7860` to a host port of your choice.
5. Make sure NVIDIA GPU access works on the Unraid host.
6. Set required template variables (especially replacing the default password placeholder).
7. Start the container and access the WebUI from a trusted device on your LAN or through a VPN.

If you build your own image, the Dockerfile tracks upstream `AUTOMATIC1111` `dev` by default via `WEBUI_REF=dev`.
`WEBUI_REF` is a build-time setting for image maintainers, not a runtime template variable for CA end users.

By default, this container now includes `--no-download-sd-model` so it does **not** silently pull the default Stable Diffusion 1.5 checkpoint on first startup. In practice, you should place your own checkpoint(s) under `/data/models/Stable-diffusion` or intentionally override that behavior in `COMMANDLINE_ARGS` if you really want automatic model download.

On first startup, the container creates a Python virtual environment under `/data/venv` and installs the heavyweight core Python dependencies there, including `torch` and `torchvision`. That initial launch can take a while.

On every startup, the container also automatically creates the standard directory layout under `/data` (`models/Stable-diffusion`, `models/VAE`, `models/Lora`, `outputs`) if it does not already exist. This means a fresh, restored, or accidentally deleted data volume self-heals its structure on next start without any manual setup. If `/data` itself ends up owned by root, the container also corrects that automatically before dropping to the unprivileged app user.

The bootstrap currently pins `torch`, `torchvision`, and `xformers` as a tested set so the startup environment stays consistent. These values are meant to track the current expectations of the upstream `AUTOMATIC1111` `dev` branch rather than floating to whatever pip resolves that day. If you decide to change them, treat them as a tested group rather than bumping one package at a time.

The included `template.xml` is set up for a local test image by default:

- Repository: `a1111-webui-aegisnir:local`
- Extra Parameters: `--runtime=nvidia`

If you publish an image, switch the template repository to:

- `ghcr.io/aegisnir/a1111-webui-aegisnir:latest`

Once the container is running, the WebUI is typically available at:

`http://tower.local:7860`

Replace `tower.local` with your Unraid hostname or IP if needed.

## GPU sanity check

On the Unraid host, a quick way to confirm Docker can see the GPU is:

```bash
docker run --rm --gpus all nvidia/cuda:12.9.1-runtime-ubuntu22.04 nvidia-smi
```

If that fails, troubleshoot the host NVIDIA setup before troubleshooting this container.

The included Unraid template also sets this runtime flag by default:

```bash
--runtime=nvidia
```

That gives the container access to the NVIDIA runtime when the NVIDIA Container Toolkit / Unraid integration is set up correctly on the host.

## Configuration

### Authentication defaults

This container now enables the AUTOMATIC1111 login page by default.

Default login configuration:

- username: `admin`
- password: `changeme-now`

The container will refuse to start while the password is still set to `changeme-now`. Treat that value as a placeholder only and replace it in the container configuration before first normal startup.

Set your real login values in the container configuration with:

- `WEBUI_USERNAME`
- `WEBUI_PASSWORD`

Use `WEBUI_PASSWORD` for convenience/testing. For live deployments, prefer `WEBUI_AUTH_FILE` so credentials are managed from a mounted file instead of template variables.

The container also mirrors those credentials to `--api-auth` by default so the API is not left unauthenticated while the UI is protected.

If you prefer not to store credentials directly in template variables, mount an auth file and set:

- `WEBUI_AUTH_FILE`

The file format matches AUTOMATIC1111's auth-file format:

- one credential per line as `username:password`
- or multiple comma-delimited entries on one line

Example:

```text
admin:correct horse battery staple
viewer:another-password
```

When `WEBUI_AUTH_FILE` is set, it takes precedence over `WEBUI_USERNAME` and `WEBUI_PASSWORD` unless you explicitly provide your own `--gradio-auth` or `--gradio-auth-path` in `COMMANDLINE_ARGS`.

By default, the container also mirrors auth-file credentials into API auth. You can control that with:

- `API_AUTH_FILE_MODE=mirror-webui-file`
- `API_AUTH_FILE_MODE=disabled`

Important security note: upstream AUTOMATIC1111 parses auth from command-line flags internally. This repo masks those values from the startup log, but command-line style auth should still be treated as sensitive and avoided in screenshots, copied logs, or shared diagnostics.

Operational warning: in some startup paths, credentials provided via `WEBUI_PASSWORD` may still appear in logs (for example as part of generated launch arguments). Treat container logs as sensitive and rotate credentials if they were exposed. Using `WEBUI_AUTH_FILE` is strongly recommended for non-test deployments.

If you want to manage authentication manually, you can still pass your own auth flags in `COMMANDLINE_ARGS`:

- `--gradio-auth username:password`
- `--gradio-auth-path /path/to/auth-file`
- `--api-auth username:password`

If you provide your own auth flags in `COMMANDLINE_ARGS`, the container will not add duplicate auth arguments.

### `COMMANDLINE_ARGS`

`COMMANDLINE_ARGS` is passed directly to `launch.py`.

**Default:**

- `--listen --port 7860 --data-dir /data --xformers --no-download-sd-model`

The `--xformers` flag enables memory-efficient attention and faster image generation on supported GPUs such as the NVIDIA 4090. It is enabled by default for better performance. If you run into issues, you can remove `--xformers` from the arguments.

The `--no-download-sd-model` flag is enabled by default so first startup does not automatically download a multi-gigabyte checkpoint into your data directory. That makes container behavior more predictable on Unraid and avoids unexpected bandwidth and storage use.

To make troubleshooting easier, the startup logs now report both the target bootstrap versions and the installed versions for `torch`, `torchvision`, and `xformers` during first-run setup.

If you change these arguments, keep in mind that some flags can weaken the container's security posture. Be especially careful with anything that increases exposure or enables public sharing behavior.

### HTTPS / TLS options

By default, AUTOMATIC1111 serves over HTTP, not HTTPS.

AUTOMATIC1111 does support direct TLS flags:

- `--tls-certfile /path/to/cert.pem`
- `--tls-keyfile /path/to/key.pem`

That means HTTPS can be enabled directly in the application, but doing it safely by default inside this container has tradeoffs:

- you need to provide certificates and keys securely
- certificate renewal is easier to manage outside the app
- reverse proxies usually handle TLS, redirects, and hostname routing better than the WebUI itself

My recommended approach for most Unraid users is:

1. Keep the container on a trusted local network.
2. Leave the container itself on HTTP internally.
3. Put HTTPS in front of it with a reverse proxy such as Nginx Proxy Manager, Traefik, Caddy, or another TLS-terminating proxy.
4. Restrict exposure with a VPN, access controls, or both if you need remote access.

If you want direct HTTPS from AUTOMATIC1111 itself, you can do it by mounting certificate files into the container and adding the TLS flags to `COMMANDLINE_ARGS`. I do not currently recommend making that the default in this repo because certificate management is highly environment-specific and easy to get wrong.

### `--data-dir`

I recommend using AUTOMATIC1111's `--data-dir` so the large, fast-growing working set lives on a host path you choose.

Recommended container path:

- `/data`

Recommended Unraid behavior:

- default host path: `/mnt/user/ai/data/`
- prefer a path outside `appdata` if possible

Why I recommend that:

- this directory can grow very large very quickly
- it may contain models, outputs, extensions, caches, and other data
- if you store it in `appdata`, it may fill that area much faster than expected
- if your Docker-related storage is limited, this can become painful in a hurry

You can absolutely use `appdata` if that fits your setup better. I just would not make it the default recommendation here.

For this repo/template, the default host path is:

- `/mnt/user/ai/data/`

That gives the data directory a more sensible starting point on Unraid without pushing users into `appdata` by default.

The `/data` mapping now also stores the persistent Python environment used by the container at:

- `/data/venv`

It also stores the runtime-cloned AUTOMATIC1111 support repositories at:

- `/data/repositories`

That means you do not need to redownload the heavy Python packages every time you recreate the container, as long as you keep the same host data path.

## Storage and permissions

If you use `--data-dir /data`, most of the large writable content should live under `/data` instead of being scattered under the application directory.

That is one of the main reasons I prefer the `--data-dir` approach for Unraid.

This image is currently set up with Unraid-friendly defaults:

- UID `99`
- GID `100`

Make sure your mapped host paths are writable by that UID/GID strategy, or adjust the container settings to match your environment.

### File Permissions and umask

By default, this container does not set a restrictive `UMASK`, so files in `/data` remain easier to access from outside the container.

If you want stricter file permissions for security, set the template variable `UMASK` in Unraid (advanced view), for example:

- `UMASK=0027`

This results in files with permissions like `rw-r-----` and directories with `rwxr-x---`.

## Security Hardening Defaults

This container now uses the following security options by default (see Unraid template or Extra Parameters):

```bash
--read-only
--tmpfs /tmp:rw,noexec,nosuid,size=2g
--security-opt no-new-privileges:true
--cap-drop=ALL
--pids-limit=2048
```

**What these do:**
- `--read-only`: Reduces write access to the container filesystem, limiting persistence for attackers.
- `--tmpfs /tmp:...`: Provides a safe, writable /tmp for runtime needs.
- `no-new-privileges:true`: Prevents processes from gaining new privileges, reducing escalation risk.
- `--cap-drop=ALL`: Removes all Linux capabilities not required by the base image, reducing attack surface.
- `--pids-limit=2048`: A practical default to contain runaway process spawning without being overly restrictive.

PID limit defaults to `2048` in this template and can be tuned per host in Unraid.

To change it in Unraid (works across versions):

1. Open the container in Unraid and switch to advanced view.
2. In Extra Parameters, add `--pids-limit=<value>`.
3. Apply the update.

Examples:

- `--pids-limit=512`
- `--pids-limit=1024`
- `--pids-limit=2048`

If you use `--read-only`, expect to provide explicit writable mounts for anything that needs to persist, such as models, outputs, and extensions under `/data`.

### Additional Security Measures

- The container will refuse to start as root (UID 0) for safety.
- All SUID/SGID bits are removed from binaries at build time to prevent privilege escalation via legacy system tools.

## Operational notes

- Anyone who can reach the WebUI port may be able to interact with it.
- Host networking, public exposure, and relaxed runtime settings all change the risk profile.
- Models, extensions, and other third-party content should be treated as untrusted inputs.
- A healthy container only means the service responded on the expected port. It does **not** prove the application is safe or fully working.

## Troubleshooting

### The WebUI does not load
- Check the container logs — the container now prints a pre-launch summary and annotates known harmless warnings inline, so look past those to find real errors.
- Confirm the port mapping is correct.
- Confirm the container is still running.
- On first launch, allow extra time for the Python environment bootstrap under `/data/venv`.
- Make sure you have provided a model checkpoint under `/data/models/Stable-diffusion` if you keep the default `--no-download-sd-model` behavior enabled.

### Error: "No checkpoints found"
- This is expected if you keep the default `--no-download-sd-model` flag and have not placed a model yet.
- Fix: place at least one `.safetensors` or `.ckpt` file in `/data/models/Stable-diffusion` (host default: `/mnt/user/ai/data/models/Stable-diffusion`).
- Restart the container (or refresh models in the UI) and select the checkpoint.

### The GPU is not being used
- Re-run the GPU sanity check above.
- Confirm the container still has `--runtime=nvidia` in Extra Parameters.
- Confirm Unraid is providing GPU access to the container.
- Confirm the host NVIDIA driver/plugin is working.
- If AUTOMATIC1111 fails with a message like `Torch is not able to use GPU`, you can temporarily add `--skip-torch-cuda-test` to `COMMANDLINE_ARGS` for troubleshooting. I do not recommend making that your long-term default, because it can hide a real GPU passthrough problem.
- If dependency installation fails on first startup, remove `/data/venv` and retry after updating the image so the bootstrap can rebuild a clean environment.

If you are using the template defaults, that means removing:

- `/mnt/user/ai/data/venv`
- `/mnt/user/ai/data/repositories`

### I am seeing permission errors
- Check that your mapped host folders are writable by the configured UID/GID.
- If `/data` ended up owned by root (e.g. after deleting and Docker recreating the host directory), the container now self-heals this automatically — see the section below.
- If using `--read-only`, make sure required writable paths are explicitly mounted.

### Error: `Operation not permitted` in entrypoint (`chmod`, `runuser`, or `setpriv`)
- If logs show messages like `chmod: changing permissions of '/data': Operation not permitted`, `runuser: cannot set groups`, or `setpriv: setresuid failed`, the host/runtime is denying metadata or UID/GID transitions.
- The container now prints a short runtime diagnostic line with `NoNewPrivs`, `Seccomp`, and `CapEff` values to help identify this class of restriction quickly.
- Typical causes: rootless/user-namespace remap behavior, no-new-privileges hardening, NFS root-squash exports, or share ACL/mount policy restrictions.
- Fix on host first, then restart:

```bash
chown nobody:users /mnt/user/ai/data
chmod 775 /mnt/user/ai/data
```

### The container fails to start after deleting `/data`

If you delete the host data directory (default: `/mnt/user/ai/data/`), Docker may recreate it owned by `root` on next start.

**In most cases this is fully automatic.** The container entrypoint (`entrypoint.sh`) runs as root, detects the wrong ownership, corrects it, then drops to the unprivileged app user before startup continues. You should see a log line like:

```
[entrypoint] /data is owned by uid=0, expected uid=99.
[entrypoint] Correcting ownership to 99:100 (nobody:users) and setting mode 775...
[entrypoint] /data ownership corrected. Continuing startup.
```

On the next startup after that, the container will recreate the full directory structure under `/data` (venv, models, outputs, etc.) automatically.

**If the auto-fix fails** (NFS shares with root squash, unusual SELinux policies, or other host-side restrictions), you will see:

```
ERROR: /data exists but is not writable by the current user (uid=99).
       The container entrypoint attempted to correct this automatically but could not.
```

In that case, correct ownership manually on the Unraid host (as root) and restart:

```bash
chown nobody:users /mnt/user/ai/data
chmod 775 /mnt/user/ai/data
```

### The container is unhealthy
- Check whether the application is still listening on the configured port.
- If you changed the port, make sure the healthcheck assumptions still match the runtime behavior.

## Using the dev branch

Due to the removal of the original Stable Diffusion repository, you **must** use the `dev` branch of AUTOMATIC1111 for new installs. The `dev` branch includes a fix that points to a maintained fork for required dependencies. If you use the `main` branch, the container will fail to start.

To update an existing install:

1. Enter your WebUI directory.
2. Run:
	```bash
	git switch dev
	git pull
	```

## Maintenance

This image will likely need occasional rebuilds to pick up upstream changes and dependency updates.

At a minimum, I would keep an eye on:
- upstream AUTOMATIC1111 changes
- Unraid updates
- NVIDIA driver/toolkit changes
- any extensions or models you add yourself

## Licensing and Third-Party Notices

This repository's original project files are licensed under MIT (see `LICENSE`), unless otherwise noted.

This project packages and runs upstream `AUTOMATIC1111/stable-diffusion-webui`, which is licensed under AGPL-3.0.

For third-party license details, see:

- `THIRD_PARTY_NOTICES.md`
- `LICENSES/AGPL-3.0.txt`

If you distribute images or artifacts that include AGPL-covered components, include corresponding source and license notices for those components.

## Disclaimer

This repository is shared as-is.

I am trying to make it useful and reasonably security-conscious, but I am learning as I go and I will make mistakes. Nothing here should be treated as a guarantee of security, stability, or suitability for your environment. Please validate everything against your own needs, threat model, and risk tolerance.
