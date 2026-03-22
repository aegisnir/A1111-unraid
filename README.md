# ⚠️⚠️⚠️ WORK IN PROGRESS ⚠️⚠️⚠️

Do not use this yet unless the work-in-progress notice is removed.

This is a personal hobby project. It is heavily AI-assisted, and it is also a learning experience for me. I care a lot about security and I am trying to make thoughtful choices, but I am not a programmer or a security expert, so mistakes and weak assumptions are possible. If you notice something I could do better, I am open to constructive feedback and recommendations.

---

# Stable Diffusion WebUI (AUTOMATIC1111) for Unraid


This repository packages AUTOMATIC1111 Stable Diffusion WebUI for Unraid with NVIDIA GPU support in mind. My goal is to keep it practical, reasonably lightweight, and more thoughtful about security than a throwaway personal build.

**Important:** As of March 2026, new installs require the `dev` branch of AUTOMATIC1111 due to a missing dependency repository. The main branch will fail to start. See below for updated instructions.

> ⚠️ Public internet exposure is **not** the intended use case.
> If you expose this beyond a trusted network, the risk profile changes significantly and you should make those decisions carefully for your own environment.

## Quick start

These are the defaults I would personally start with on a trusted LAN.

1. Clone the AUTOMATIC1111 repository and switch to the `dev` branch:
	```bash
	git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
	cd stable-diffusion-webui
	git switch dev
	git pull
	```
2. Build the image on your Unraid host with the tag `a1111-webui-aegisnir:latest`.
2. Use **Bridge** networking.
3. Map container port `7860` to a host port of your choice.
4. Make sure NVIDIA GPU access works on the Unraid host.
5. Create the container from the included Unraid template.
6. Access the WebUI from a trusted device on your LAN or through a VPN.

On the very first startup, the container now creates a Python virtual environment under `/data/venv` and installs the heavyweight core Python dependencies there (such as torch and torchvision). That first launch can take a while.

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

If that fails, I would troubleshoot the host NVIDIA setup before troubleshooting this container.

The included Unraid template also sets this runtime flag by default:

```bash
--runtime=nvidia
```

That gives the container access to the NVIDIA runtime on hosts where the NVIDIA Container Toolkit / Unraid integration is set up correctly.

## Configuration


### `COMMANDLINE_ARGS`

`COMMANDLINE_ARGS` is passed directly to `launch.py`.

**Default:**

- `--listen --port 7860 --data-dir /data --xformers`

The `--xformers` flag enables memory-efficient attention and faster image generation on supported GPUs (such as NVIDIA 4090). This is now enabled by default for best performance. If you experience issues, you can remove `--xformers` from the arguments.

If you change these arguments, keep in mind that some flags can affect the security posture of the container. Be especially careful with anything that increases exposure or enables public sharing behavior.

### `--data-dir`

I recommend using Automatic1111's `--data-dir` so the large, fast-growing working set lives on a host path you choose.

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

You can absolutely use `appdata` if that fits your setup better. I just would not make it my default recommendation.

For this repo/template, the default host path is:

- `/mnt/user/ai/data/`

That gives the data directory a more sensible starting point on Unraid without pushing users into `appdata` by default.

The `/data` mapping now also stores the persistent Python environment used by the container at:

- `/data/venv`

It also stores the runtime-cloned AUTOMATIC1111 support repositories at:

- `/data/repositories`

That means you do not need to redownload the heavy Python packages every time you recreate the container, as long as you keep the same host data path.


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

If you use `--read-only`, expect to provide explicit writable mounts for things like models, outputs, and extensions (e.g., `/data`).

### Additional Security Measures

- The container will refuse to start as root (UID 0) for safety.
- All SUID/SGID bits are removed from binaries at build time to prevent privilege escalation via legacy system tools.

## Storage and permissions

If you use `--data-dir /data`, most of the large writable content should live under `/data` instead of being scattered under the application directory.

That is one of the main reasons I prefer the `--data-dir` approach for Unraid.

This image is currently set up with Unraid-friendly defaults:
- UID `99`
- GID `100`

Make sure your mapped host paths are writable by that UID/GID strategy, or adjust the container settings to match your environment.

## A few important notes

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
- If Automatic1111 fails with a message like `Torch is not able to use GPU`, you can temporarily add `--skip-torch-cuda-test` to `COMMANDLINE_ARGS` for troubleshooting. I do not recommend making that your long-term default, because it can hide a real GPU passthrough problem.
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

Due to the removal of the original Stable Diffusion repository, you **must** use the `dev` branch of AUTOMATIC1111 for new installs. The `dev` branch includes a fix to use a maintained fork for required dependencies. If you use the `main` branch, the container will fail to start.

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
