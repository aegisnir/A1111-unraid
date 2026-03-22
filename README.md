
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

1. Clone the AUTOMATIC1111 repository and switch to the `dev` branch:
	```bash
	git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
	cd stable-diffusion-webui
	git switch dev
	git pull
	```
2. Build the image on your Unraid host with the tag `a1111-webui-aegisnir:latest`.
3. Use **Bridge** networking.
4. Map container port `7860` to a host port of your choice.
5. Make sure NVIDIA GPU access works on the Unraid host.
6. Create the container from the included Unraid template.
7. Access the WebUI from a trusted device on your LAN or through a VPN.

On first startup, the container creates a Python virtual environment under `/data/venv` and installs the heavyweight core Python dependencies there, including `torch` and `torchvision`. That initial launch can take a while.

The bootstrap currently pins `torch`, `torchvision`, and `xformers` as a tested set so the startup environment stays consistent. These values are meant to track the current expectations of the upstream `AUTOMATIC1111` `dev` branch rather than floating to whatever pip resolves that day. If you decide to change them, treat them as a tested group rather than bumping one package at a time.

The included `template.xml` is set up for a locally built image:

- Repository: `a1111-webui-aegisnir:latest`
- Extra Parameters: `--runtime=nvidia`

It is not currently configured to pull a published image from Docker Hub.

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

### `COMMANDLINE_ARGS`

`COMMANDLINE_ARGS` is passed directly to `launch.py`.

**Default:**

- `--listen --port 7860 --data-dir /data --xformers`

The `--xformers` flag enables memory-efficient attention and faster image generation on supported GPUs such as the NVIDIA 4090. It is enabled by default for better performance. If you run into issues, you can remove `--xformers` from the arguments.

To make troubleshooting easier, the startup logs now report both the target bootstrap versions and the installed versions for `torch`, `torchvision`, and `xformers` during first-run setup.

If you change these arguments, keep in mind that some flags can weaken the container's security posture. Be especially careful with anything that increases exposure or enables public sharing behavior.

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

By default, this container does not set a restrictive `umask`, so files in `/data` remain accessible from outside the container. This is intentional and makes host-side access easier.

**If you want stricter file permissions:**
Add `umask 0027` near the top of `start.sh` (after the root check). This makes files and directories created in `/data` non-world-readable and non-world-writable. For example:

```bash
umask 0027
```

This results in files with permissions like `rw-r-----` and directories with `rwxr-x---`.

## Security Hardening Defaults

This container now uses the following security options by default (see Unraid template or Extra Parameters):

```bash
--read-only
--tmpfs /tmp:rw,noexec,nosuid,size=2g
--security-opt no-new-privileges:true
--cap-drop=ALL
--pids-limit=512
```

**What these do:**
- `--read-only`: Reduces write access to the container filesystem, limiting persistence for attackers.
- `--tmpfs /tmp:...`: Provides a safe, writable /tmp for runtime needs.
- `no-new-privileges:true`: Prevents processes from gaining new privileges, reducing escalation risk.
- `--cap-drop=ALL`: Removes all Linux capabilities not required by the base image, reducing attack surface.
- `--pids-limit=512`: Contains runaway process spawning.

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
- Check the container logs.
- Confirm the port mapping is correct.
- Confirm the container is still running.
- On first launch, allow extra time for the Python environment bootstrap under `/data/venv`.

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
- If using `--read-only`, make sure required writable paths are explicitly mounted.

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

## Disclaimer

This repository is shared as-is.

I am trying to make it useful and reasonably security-conscious, but I am learning as I go and I will make mistakes. Nothing here should be treated as a guarantee of security, stability, or suitability for your environment. Please validate everything against your own needs, threat model, and risk tolerance.
