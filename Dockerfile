# syntax=docker/dockerfile:1
#
# Dockerfile - AUTOMATIC1111 Stable Diffusion WebUI (Unraid-friendly)
#
# Design intent:
#   - Keep the runtime image reasonably small (avoid dev toolchains where possible)
#   - Run as a non-root user where practical
#   - Pin the CUDA base image by digest for reproducibility
#   - Allow controlled pinning of upstream WebUI code (WEBUI_REF)
#
# This project is maintained as a personal, AI-assisted hobby project.
# These comments try to explain the reasoning behind the current choices,
# but they should not be read as a guarantee that the result is fully hardened
# or appropriate for every environment.
#
# General Docker build guidance (reference):
# https://docs.docker.com/build/building/best-practices/

# ------------------------------------------------------------------------------
# Design Notes (Why some security/ops choices are intentionally NOT baked in)
#
# 1) Runtime hardening flags:
#    This image does not embed runtime security flags (read-only FS, cap drops,
#    no-new-privileges, tmpfs, etc.) because those controls are applied by the
#    container runtime (Unraid/Docker) and may need tuning per environment.
#    If you choose not to apply them, the deployment may be less constrained than
#    originally intended.
#
# 2) Network exposure & authentication:
#    This image starts a local web service. It does not configure TLS, auth, or
#    reverse-proxy integration by default because those are deployment concerns
#    that vary by environment. If you expose the service beyond a trusted network,
#    the resulting setup may not be as safe as originally intended.
#
# 3) GPU drivers:
#    NVIDIA kernel drivers live on the host. This image includes user-space CUDA
#    components and expects GPU access to be granted explicitly at runtime.
#
# 4) Supply chain & updates:
#    - The CUDA base image is pinned by digest to reduce unexpected upstream change.
#    - The WebUI source can be pinned via WEBUI_REF for more controlled builds.
#      If you track a moving branch (e.g., "master"), behavior and risk may change
#      over time.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Base image: NVIDIA CUDA runtime (Ubuntu 22.04), pinned by digest.
# Digest confirmed on Docker Hub layer details. https://hub.docker.com/layers/nvidia/cuda/12.9.1-runtime-ubuntu22.04/images/sha256-6553b9635f35d992cf0473f55d1e998935a2dd1e2e604d3cbfb2bf295a8faa79/
# ------------------------------------------------------------------------------
FROM nvidia/cuda:12.9.1-runtime-ubuntu22.04@sha256:d90541b92124899904e0860a4ac1955606b3bc45ad6cc9dab16567fd1111e326

# Use bash with pipefail for safer RUN pipelines.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ------------------------------------------------------------------------------
# Build-time configuration
# ------------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive

# Pin the WebUI to a branch/tag/commit. For more controlled builds,
# consider using a specific commit SHA and updating intentionally.
#
# Security note:
# Avoid passing secrets through build arguments. Industry guidance generally
# treats build args as poor places for sensitive values because they may show up
# in build metadata, layer history, logs, or external attestations depending on
# how and where the image is built.
ARG WEBUI_REF=master

# Unraid-friendly defaults (nobody/users). Adjust if you use a different strategy.
ARG APP_UID=99
ARG APP_GID=100
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121

# ------------------------------------------------------------------------------
# Runtime defaults
# NOTE: --listen binds to all interfaces. On a trusted LAN this is often OK,
# but exposing this service beyond a trusted network may not be as safe as intended.
# If a user wants stronger exposure controls, those should usually be enforced
# by network design, reverse proxies, VPNs, access controls, and container
# runtime settings rather than trying to rely on this image alone.
# ------------------------------------------------------------------------------
ENV COMMANDLINE_ARGS="--listen --port 7860"
ENV WEBUI_DIR="/opt/stable-diffusion-webui"

# ------------------------------------------------------------------------------
# Install minimal runtime dependencies.
# Docker guidance recommends keeping images small and rebuilding regularly to
# pick up updates. https://docs.docker.com/build/building/best-practices/
# ------------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      python3 \
      python3-venv \
      python3-pip \
      libglib2.0-0 \
      libsm6 \
      libxrender1 \
      libxext6 \
 && rm -rf /var/lib/apt/lists/*

# Preinstall the PyTorch stack expected by the pinned AUTOMATIC1111 version.
# Doing this at build time avoids a very large first-start download in the
# container runtime, which is especially helpful on Unraid where long-running
# init downloads can look like a broken or hung container.
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel \
 && python3 -m pip install --no-cache-dir \
   torch==2.1.2 \
   torchvision==0.16.2 \
   --extra-index-url "${TORCH_INDEX_URL}"

# ------------------------------------------------------------------------------
# Create a dedicated non-root user.
# Running as non-root can reduce impact in some failure scenarios.
# It does not make the container "secure," but it can help reduce the blast
# radius compared with running everything as root.
# ------------------------------------------------------------------------------
RUN getent group "${APP_GID}" || groupadd --gid "${APP_GID}" app \
 && useradd --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash app

# ------------------------------------------------------------------------------
# Fetch A1111 source code
# A shallow clone keeps the image build lighter and faster, which is useful for
# hobbyist maintenance and routine rebuilds. The tradeoff is that full history
# is not available inside the image, so deeper forensics or history inspection
# would need to happen outside this build context.
# ------------------------------------------------------------------------------
RUN useradd -m sdwebui \
    && git clone --depth 1 https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "${WEBUI_DIR}" \
    && cd "${WEBUI_DIR}" \
    && git fetch --depth 1 origin "${WEBUI_REF}" \
    && git checkout "${WEBUI_REF}" \
    && chown -R sdwebui:sdwebui "${WEBUI_DIR}"

# ------------------------------------------------------------------------------
# Copy entrypoint script (from this repository)
# ------------------------------------------------------------------------------
COPY start.sh /start.sh
RUN if ! id -u sdwebui > /dev/null 2>&1; then \
    groupadd -r sdwebui; \
    useradd -r -g sdwebui sdwebui; \
fi && chmod 0755 /start.sh && chown sdwebui:sdwebui /start.sh

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
EXPOSE 7860

# ------------------------------------------------------------------------------
# Healthcheck
# Checks if something is listening on localhost:7860.
# This is a lightweight signal, not a full correctness check.
# In other words, it can help detect obvious startup failures, but it should not
# be treated as proof that the application is healthy, safe, authenticated, or
# functioning correctly for every request path.
# ------------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 7860)); s.close()" || exit 1

# Drop privileges at runtime.
# Runtime hardening should still be reviewed at the container runtime layer
# (for example: read-only root filesystem, dropped capabilities, no-new-
# privileges, explicit writable mounts, network exposure limits, etc.).
USER sdwebui:sdwebui

ENTRYPOINT ["/start.sh"]
