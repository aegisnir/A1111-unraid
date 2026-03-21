# syntax=docker/dockerfile:1
#
# Dockerfile - Security-focused AUTOMATIC1111 Stable Diffusion WebUI image (Unraid-friendly)
#
# Security goals:
#   - Reduce attack surface (minimal packages, no dev toolchains)
#   - Least privilege (run as non-root)
#   - Reproducibility / supply-chain integrity (pin base image by digest)
#   - Clear defaults and easy overrides (COMMANDLINE_ARGS)
#
# Docker guidance highlights:
#   - Choose a trusted base and keep it small
#   - Rebuild images often to pick up security patches
# [1](https://docs.docker.com/build/building/best-practices/)

# ------------------------------------------------------------------------------
# Base image: NVIDIA CUDA runtime (Ubuntu 22.04) pinned by digest for immutability.
# Why digest pinning?
#   - Tags can be updated/repointed; digests are immutable.
#   - This helps prevent supply-chain surprises and makes builds reproducible.
# ------------------------------------------------------------------------------
FROM nvidia/cuda:12.9.1-runtime-ubuntu22.04@sha256:d90541b92124899904e0860a4ac1955606b3bc45ad6cc9dab16567fd1111e326

# ------------------------------------------------------------------------------
# Use bash with pipefail for safer RUN pipelines.
# ------------------------------------------------------------------------------
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ------------------------------------------------------------------------------
# Build-time configuration
# ------------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive

# Pin A1111 to a specific branch/tag/commit for stability.
# SECURITY NOTE:
#   - For maximum safety, use a specific commit SHA and update intentionally.
ARG WEBUI_REF=master

# Unraid-friendly defaults (nobody/users). You can change these if needed.
ARG APP_UID=99
ARG APP_GID=100

# ------------------------------------------------------------------------------
# Runtime defaults
# SECURITY NOTE:
#   - --listen binds to all interfaces. Safe on LAN if you do NOT expose it to the internet.
#   - Do NOT use --share (public exposure risk).
# ------------------------------------------------------------------------------
ENV COMMANDLINE_ARGS="--listen --port 7860"
ENV WEBUI_DIR="/opt/stable-diffusion-webui"

# ------------------------------------------------------------------------------
# Install minimal dependencies.
# We intentionally avoid large toolchains and keep packages minimal.
#
# Why minimal packages?
#   - Fewer packages = smaller attack surface and fewer CVEs to manage.
# [1](https://docs.docker.com/build/building/best-practices/)[2](https://dockerbuild.com/blog/security-best-practices)
#
# NOTE about git:
#   - A1111 can use git for extensions / updates.
#   - If you want maximum hardening, you can remove git after clone,
#     but you’ll lose “install extension from git” convenience.
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

# ------------------------------------------------------------------------------
# Create a dedicated non-root user.
# Why?
#   - Running as root increases impact if the app is compromised.
# [2](https://dockerbuild.com/blog/security-best-practices)
# ------------------------------------------------------------------------------
RUN groupadd --gid "${APP_GID}" app \
 && useradd  --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash app

# ------------------------------------------------------------------------------
# Fetch A1111 source code
# SECURITY NOTE:
#   - Pin WEBUI_REF to a commit SHA for strongest reproducibility.
# ------------------------------------------------------------------------------
WORKDIR /opt
RUN git clone --depth 1 https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "${WEBUI_DIR}" \
 && cd "${WEBUI_DIR}" \
 && git fetch --depth 1 origin "${WEBUI_REF}" \
 && git checkout "${WEBUI_REF}" \
 && chown -R app:app "${WEBUI_DIR}"

# ------------------------------------------------------------------------------
# Copy entrypoint script (already committed in your repo)
# ------------------------------------------------------------------------------
COPY start.sh /start.sh
RUN chmod 0755 /start.sh \
 && chown app:app /start.sh

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
EXPOSE 7860

# ------------------------------------------------------------------------------
# Healthcheck
# Purpose:
#   - Detect "container is up but app is dead" situations.
# NOTE:
#   - This checks if something is listening on localhost:7860.
# ------------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 7860)); s.close()" || exit 1

# ------------------------------------------------------------------------------
# Drop privileges at runtime
# ------------------------------------------------------------------------------
USER app:app

ENTRYPOINT ["/start.sh"]
