# ⚠️⚠️⚠️ WORK IN PROGRESS ⚠️⚠️⚠️ 
DO NOT USE UNTIL WORK IN PROGRESS STATUS IS REMOVED

I’m not a programmer, just a curious hobbyist building personal projects for fun.  I openly use AI to help me make things, so please expect mistakes as I learn!

---

# Stable Diffusion WebUI (AUTOMATIC1111) – Docker for Unraid (Security‑Focused)

![CUDA](https://img.shields.io/badge/CUDA-12.9.1-76B900?logo=nvidia&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA-GPU-76B900?logo=nvidia&logoColor=white)
![Unraid](https://img.shields.io/badge/Unraid-Docker-F15A2C?logo=docker&logoColor=white)
![Security](https://img.shields.io/badge/Security-Focused-2f6feb?logo=shield&logoColor=white)
![Network](https://img.shields.io/badge/Network-Avoid%20Public%20Exposure-critical?logo=lock&logoColor=white)

This repository contains a Docker build that is **intended** to run AUTOMATIC1111 Stable Diffusion WebUI on **Unraid** with **NVIDIA GPU acceleration**, with a configuration that **aims to reduce risk** through sensible defaults and explicit hardening options.

> ⚠️ **Public internet exposure is not the intended use case.**  
> If you expose this service beyond a trusted network, the deployment **may not be as secure as originally intended** and the risk profile changes significantly.

---

## Quick Start (Recommended / “Safe Defaults”)

These defaults are intended to be a practical baseline for most home-lab / trusted-LAN setups.

### 1) Networking: use **Bridge**
Unraid describes Bridge as the safest

- Network mode: **Bridge**
- Port mapping: map container port **7860** to a host port of your choice (commonly 7860)

### 2) Access the WebUI
After starting the container, open: 
http://tower.local:7860
Replace tower.local with your unraid server IP address or hostname.

**Access notes (important):**
- Anyone who can reach this port may be able to interact with the WebUI.
- Consider restricting access to trusted devices/networks (LAN/VPN).

### 3) GPU: confirm passthrough works
Docker’s documented GPU access uses the `--gpus` flag.
NVIDIA’s container toolkit documentation also uses an `nvidia-smi` container run as a verification pattern.

On the Unraid host, you can sanity-check GPU access with:


docker run --rm --gpus all nvidia/cuda:12.9.1-runtime-ubuntu22.04 nvidia-smi

---

## Configuration (What You Can Change)

### Key environment variables
- `COMMANDLINE_ARGS` – arguments passed to `launch.py` (example defaults include `--listen --port 7860`)

> ⚠️ Avoid using “public sharing” style options. If you enable sharing or public exposure, the deployment may become easier to discover and attack.

---

## Hardening Recommendations (Unraid)

These suggestions are optional, but they are commonly used to **reduce container blast radius** and make persistence harder.

### Unraid “Extra Parameters” (recommended baseline)

Paste into **Unraid → Docker → Extra Parameters**:


--read-only
--tmpfs /tmp:rw,noexec,nosuid,size=2g
--security-opt no-new-privileges:true
--cap-drop=ALL
--pids-limit=512

What these do (high level):
- `--read-only` helps reduce persistence by making the container filesystem read-only.
- `--tmpfs /tmp:...` provides a writable temp location without making the whole filesystem writable.
- `noexec,nosuid` on `/tmp` helps reduce common payload execution/escalation paths.
- `no-new-privileges:true` helps prevent privilege escalation inside the container.
- `--cap-drop=ALL` removes Linux capabilities to reduce privileged operations.
- `--pids-limit` helps mitigate runaway process spawning.

> If you apply `--read-only`, the application may require explicit writable mounts for models, outputs, extensions, etc. (see below). If you skip `--read-only`, the system may be less constrained than originally intended.

---

## Storage (Volumes & Permissions)

If you use a read-only root filesystem, the WebUI will typically need writable locations. Consider mapping host folders to these container paths:

Suggested container paths:
- `/opt/stable-diffusion-webui/models` (models)
- `/opt/stable-diffusion-webui/outputs` (generated images)
- `/opt/stable-diffusion-webui/extensions` (extensions)
- `/opt/stable-diffusion-webui/logs` (optional logs)

### Permissions (Unraid-friendly defaults)
This image is commonly run with:
- UID `99`
- GID `100`

Make sure your host paths are writable by the configured UID/GID.

---

## Safe Defaults vs Power‑User Overrides

### Safe Defaults (recommended)
These choices are intended to be a reasonable security baseline:
- **Bridge** networking (LAN-only)
- Explicit port mappings (no host networking)
- Non-root runtime user
- Read-only root filesystem (with explicit writable mounts)
- Dropped capabilities and no privilege escalation

### Power‑User Overrides (use with caution)
Advanced configurations may be useful, but they can change the security posture:

- **Host networking**: may expose more services/ports than intended and reduces isolation.
- **Public exposure** (port forwarding / public reverse proxy / “share” features): may significantly increase attack surface.
- **Disabling read-only filesystem**: may allow more persistence than intended.
- **Allowing arbitrary extensions/scripts**: may increase supply-chain and code-execution risk.

If you choose these overrides, the system may not be as constrained as originally intended, and you may want additional controls (auth, VPN, IP allow-lists, monitoring, etc.).

---

## Threat Model (High Level)

This section is a **best-effort summary** of assumptions and boundaries; it is not exhaustive.

### Intended use
- Trusted LAN / private network deployments
- A user who controls their Unraid host and Docker configuration

### What this setup generally tries to reduce
- Container-level privilege escalation (least privilege, dropped capabilities)
- Persistence in the container filesystem (read-only root + explicit writable mounts)
- Accidental overexposure (Bridge networking + explicit port mapping)

### What may remain out of scope
- Host compromise (if the Unraid host is compromised, containers may be affected)
- Malicious models, malicious extensions, or untrusted scripts
- Users intentionally exposing the WebUI to the public internet
- Advanced GPU/driver-level threats

Models and extensions should be treated as potentially untrusted inputs.

---

## Common Issues & Things to Try

### WebUI doesn’t load
- Check Unraid container logs for startup errors.
- Confirm port mapping is correct (host port → container port 7860).
- Confirm the container is healthy/running.

### GPU not being used / slow performance
- Re-run the host GPU validation command:

docker run --rm --gpus all nvidia/cuda:12.9.1-runtime-ubuntu22.04 nvidia-smi

- Ensure the container is started with GPU access enabled in Unraid.
- Confirm your NVIDIA driver/plugin is loaded and working on the host.

### Permission errors with volumes
- Ensure the host folders you mounted are writable by the container’s UID/GID.
- If using `--read-only`, ensure required writable folders are mounted explicitly.

### Container becomes “unhealthy”
- Healthchecks typically detect a failure to bind or accept connections on the configured port.
- Confirm the internal port is still 7860 or adjust accordingly if you change it.

---

## Maintenance Guidance (Security & Stability)

Docker images are snapshots; rebuilding periodically is a common way to pick up updated dependencies and security fixes. 

- Rebuild / republish images periodically to pick up upstream fixes.
- Keep the Unraid host and NVIDIA drivers updated.
- Treat extensions and models as untrusted inputs; add them intentionally.

---

## Optional: Supply‑Chain Extras (CI/CD)

If you publish images, you may consider:
- SBOM and provenance attestations for auditability.
Docker’s build/push action supports these; note that build arguments can appear in provenance, so avoid passing secrets via build args.

---

## Disclaimer

This repository and its contents are provided **as-is**.  
No guarantees are made regarding security, fitness for a particular purpose, or absence of vulnerabilities.  
Users are responsible for evaluating their own risk, configuration choices, and compliance obligations.
