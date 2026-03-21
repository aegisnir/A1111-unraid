# Stable Diffusion WebUI (AUTOMATIC1111) – Secure Docker Deployment for Unraid

![CUDA](https://img.shields.io/badge/CUDA-12.9.1-76B900?logo=nvidia&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA-GPU-76B900?logo=nvidia&logoColor=white)
![Unraid](https://img.shields.io/badge/Unraid-Docker-F15A2C?logo=docker&logoColor=white)
![Security](https://img.shields.io/badge/Security-Hardened-2f6feb?logo=shield&logoColor=white)
![Network](https://img.shields.io/badge/Network-No%20Internet%20Exposure-critical?logo=lock&logoColor=white)

This repository provides a **security‑hardened Docker image** for running  
**AUTOMATIC1111 Stable Diffusion WebUI** with **NVIDIA GPU acceleration**, designed specifically for **Unraid**.

The intent is to provide a configuration that is:

- Secure by default
- High‑performance on modern NVIDIA GPUs
- Explicit and auditable
- Suitable for long‑running LAN‑only workloads
- Safe to publish publicly without encouraging unsafe defaults

---

## Platform & Compatibility

**Tested environment**

- Host OS: **Unraid**
- GPU: **NVIDIA RTX‑class (tested with RTX 4090)**
- NVIDIA Driver: **595.x or newer**
- CUDA Runtime (container): **12.9.1**
- CUDA Driver Capability (host): **13.x (backward compatible)**

This setup relies on NVIDIA’s documented CUDA backward‑compatibility model, where newer drivers safely run older CUDA user‑space libraries inside containers.

---

## Security Model (Read This First)

This image is designed around the following security principles:

### Least Privilege
- The container **does not run as root**
- All Linux capabilities are dropped
- Privilege escalation is explicitly blocked

### Reduced Attack Surface
- Uses the **CUDA runtime** image only (no development toolchains)
- Installs only minimal OS dependencies
- Supports a **read‑only root filesystem**

### Explicit Trust Boundaries
- GPU access must be explicitly granted
- Network exposure is opt‑in
- Writable paths must be mounted as volumes

### Supply‑Chain Awareness
- Base image is **pinned by digest**, not just by tag
- Optional pinning of upstream source commits is supported

---

## Base Image & CUDA Behavior

The image is built on:
nvidia/cuda:12.9.1-runtime-ubuntu22.04

Pinned by **digest** for reproducibility and supply‑chain safety.

You may see the host driver report a newer CUDA version (e.g. 13.x).  
This is **expected behavior** and indicates the maximum CUDA version supported by the driver — not what is installed inside the container.

---

## Networking (Unraid)

### Recommended Network Mode: **Bridge**

Use **Bridge** mode in Unraid.

Bridge mode provides:
- Network isolation via Docker NAT
- Explicit port exposure only
- Reduced risk of accidental LAN‑wide or host‑level exposure

**Avoid `Host` mode unless absolutely required.**

### Port Mapping

| Container Port | Host Port | Purpose |
|--------------|-----------|--------|
| 7860 | 7860 | Stable Diffusion WebUI |

Access the UI at:
http://unraidIP:7860

---

## ⚠️ Internet Exposure Warning

AUTOMATIC1111 is **not designed to be internet‑facing**.

Do **NOT**:
- Expose the container directly to the public internet
- Use `--share`
- Forward ports on your router
- Run behind a public reverse proxy without authentication

If remote access is required, use:
- VPN (WireGuard, Tailscale)
- Authenticated reverse proxy with strict IP allow‑listing

---

## Recommended Unraid Hardening Flags

Add the following to **Unraid → Docker → Extra Parameters**:
--read-only
--tmpfs /tmp:rw,noexec,nosuid,size=2g
--security-opt no-new-privileges:true
--cap-drop=ALL
--pids-limit=512

### What These Flags Do

| Flag | Purpose |
|----|--------|
| `--read-only` | Prevents writes to the container filesystem |
| `--tmpfs /tmp` | Allows temporary files without persistent writes |
| `noexec` | Prevents execution from `/tmp` |
| `nosuid` | Blocks SUID‑based privilege escalation |
| `no-new-privileges` | Prevents privilege escalation even if compromised |
| `--cap-drop=ALL` | Removes all Linux kernel capabilities |
| `--pids-limit` | Prevents fork bombs and runaway processes |

These settings **do not reduce GPU performance**.

---

## Volume Mappings (Required)

When running with a read‑only filesystem, all writable paths must be mounted explicitly.

### Minimum Recommended Volumes

| Container Path | Purpose |
|--------------|--------|
| `/opt/stable-diffusion-webui/models` | Model storage |
| `/opt/stable-diffusion-webui/outputs` | Generated images |
| `/opt/stable-diffusion-webui/extensions` | Extensions |
| `/opt/stable-diffusion-webui/logs` | Logs (optional) |

### Permissions

The container runs as:
UID: 99
GID: 100

This matches Unraid’s default `nobody:users` model.  
Ensure mounted paths are writable by this UID/GID.

---

## GPU Configuration

GPU access is handled by Unraid’s Docker template.

Internally, Docker uses:
--gpus all

### GPU Validation (Host)

Run this on the Unraid host to verify GPU passthrough:
docker run --rm --gpus all nvidia/cuda:12.9.1-runtime-ubuntu22.04 nvidia-smi

If this command succeeds, GPU access is correctly configured.

---

## Healthcheck

The container includes a healthcheck that verifies:

- The WebUI process is running
- Port `7860` is accepting connections

This helps detect situations where the container is running but the application has crashed.

---

## Common Issues & Troubleshooting

### Container exits immediately
- Check container logs in Unraid
- Verify required volumes exist
- Ensure `start.sh` is present and executable

### GPU not detected
- Confirm NVIDIA plugin is installed
- Reboot after driver updates
- Run the `nvidia-smi` validation container

### Permission errors
- Ensure volumes are owned by `nobody:users`
- Do not mount required write paths as read‑only

### WebUI runs on CPU only
- Confirm GPU is assigned in the Unraid template
- Ensure no conflicting `CUDA_VISIBLE_DEVICES` variables
- Verify NVIDIA driver is loaded on the host

---

## Optional Advanced Hardening

For higher‑security environments:

- Pin AUTOMATIC1111 to a **specific Git commit**
- Disable extension installation from the UI
- Remove `git` after build (less flexibility, smaller attack surface)
- Use `Network: none` for offline/batch workloads

---

## Maintenance Guidance

- Rebuild images periodically to receive OS security patches
- Track NVIDIA driver updates on Unraid
- Treat models and extensions as untrusted input
- Avoid blind auto‑updates in production environments

---

## Threat Model

This section describes the security assumptions, protections, and limitations of this deployment.

### Security Goals

This configuration is designed to:

- Reduce the impact of a compromised WebUI process
- Prevent privilege escalation inside the container
- Limit filesystem persistence and lateral movement
- Avoid accidental exposure to untrusted networks
- Provide clear, auditable security boundaries

### In Scope (What This Setup Protects Against)

The following threats are explicitly considered:

- **Remote code execution within the WebUI**
  - Container runs as a non‑root user
  - All Linux capabilities are dropped
  - Privilege escalation is blocked (`no-new-privileges`)

- **Persistence after compromise**
  - Read‑only root filesystem
  - Writable paths are limited to explicit volumes
  - Temporary files are stored in memory (`tmpfs`)

- **Accidental network exposure**
  - Bridge networking by default
  - No automatic internet exposure
  - Explicit warning against public deployment

- **Runaway or abusive processes**
  - PID limits prevent fork bombs and resource exhaustion

### Out of Scope (What This Setup Does NOT Protect Against)

The following are **not** mitigated by this container alone:

- **Malicious or backdoored models**
- **Malicious extensions or custom scripts**
- **Prompt‑level data exfiltration**
- **Users intentionally exposing the service to the internet**
- **Host‑level compromise**
- **GPU‑level side‑channel attacks**

Models, extensions, and user‑provided inputs should be treated as **untrusted code**.

### Trust Assumptions

This deployment assumes:

- The Unraid host OS is trusted and properly maintained
- NVIDIA drivers are installed from trusted sources
- Docker and the NVIDIA Container Toolkit are correctly configured
- Access to the WebUI is restricted to trusted users or networks

### Summary

This threat model prioritizes **containment and damage reduction** over absolute prevention.

The goal is not to make exploitation impossible, but to:
- Reduce blast radius
- Prevent privilege escalation
- Make misconfiguration obvious
- Encourage safe deployment practices

It is intended for **LAN‑only Stable Diffusion deployments** where stability and security matter.

---

## Disclaimer

This project is provided as‑is.  
Users are responsible for securing their own environments and complying with all applicable licenses.
