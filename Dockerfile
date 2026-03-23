# syntax=docker/dockerfile:1
#
# Dockerfile - AUTOMATIC1111 Stable Diffusion WebUI (Unraid-friendly)
#
# Design intent:
#   - Keep the runtime image reasonably small (avoid dev toolchains where possible)
#   - Run as a non-root user where practical
#   - Pin the CUDA base image by digest for reproducibility
#   - Track upstream WebUI from a configurable ref (WEBUI_REF, default: dev)
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
#    - The WebUI source tracks a configurable ref via WEBUI_REF (default: dev).
#      The default behavior follows a moving upstream branch, so behavior can
#      change over time when you rebuild.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Base image: NVIDIA CUDA runtime (Ubuntu 22.04), pinned by digest.
# Update this digest intentionally whenever you choose to refresh the base image.
# ------------------------------------------------------------------------------
FROM nvidia/cuda:12.9.1-runtime-ubuntu22.04@sha256:d90541b92124899904e0860a4ac1955606b3bc45ad6cc9dab16567fd1111e326

# Use bash with pipefail for safer RUN pipelines.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ------------------------------------------------------------------------------
# Build-time configuration
# ------------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive


# Select the WebUI ref to clone. Default is the moving dev branch.
# For new installs, dev is required due to upstream dependency changes.
#
# Security note:
# Avoid passing secrets through build arguments. Industry guidance generally
# treats build args as poor places for sensitive values because they may show up
# in build metadata, layer history, logs, or external attestations depending on
# how and where the image is built.
ARG WEBUI_REF=dev

# Unraid-friendly defaults (nobody/users). Adjust if you use a different strategy.
ARG APP_UID=99
ARG APP_GID=100
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128

# ------------------------------------------------------------------------------
# Runtime defaults
# NOTE: --listen binds to all interfaces. On a trusted LAN this is often OK,
# but exposing this service beyond a trusted network may not be as safe as intended.
# If a user wants stronger exposure controls, those should usually be enforced
# by network design, reverse proxies, VPNs, access controls, and container
# runtime settings rather than trying to rely on this image alone.
# ------------------------------------------------------------------------------
ENV COMMANDLINE_ARGS="--listen --port 7860 --data-dir /data --xformers --no-download-sd-model --enable-insecure-extension-access"
ENV WEBUI_DIR="/opt/stable-diffusion-webui"
ENV A1111_VENV_DIR="/data/venv"
ENV TORCH_INDEX_URL="${TORCH_INDEX_URL}"
ENV PIP_NO_BUILD_ISOLATION=1

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
      python3-setuptools \
      python3-venv \
      python3-pip \
      python3-dev \
      build-essential \
      libglib2.0-0 \
      libsm6 \
      libxrender1 \
      libxext6 \
      libgl1 \
 && rm -rf /var/lib/apt/lists/*

# Keep the base image lean and install heavyweight Python dependencies on first
# startup into a persistent virtual environment under /data.
# This avoids long image builds and lets Unraid users persist the downloaded
# Python stack across container recreation when /data is mapped.

# ------------------------------------------------------------------------------
# Create a dedicated non-root runtime user with Unraid-friendly UID/GID defaults.
# This logic ensures the group and user are always named 'sdwebui', even if the UID/GID already exist with other names (Unraid compatibility).
RUN set -eux; \
  if getent group "${APP_GID}" > /dev/null; then \
    groupmod -n sdwebui "$(getent group "${APP_GID}" | cut -d: -f1)"; \
  else \
    groupadd --gid "${APP_GID}" sdwebui; \
  fi; \
  if id -u sdwebui > /dev/null 2>&1; then \
    usermod -u "${APP_UID}" -g "${APP_GID}" sdwebui; \
  else \
    useradd --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash sdwebui; \
  fi

# ------------------------------------------------------------------------------
# Fetch A1111 source code
# A shallow clone keeps the image build lighter and faster, which is useful for
# hobbyist maintenance and routine rebuilds. The tradeoff is that full history
# is not available inside the image, so deeper forensics or history inspection
# would need to happen outside this build context.
# ------------------------------------------------------------------------------
# Symlink mutable directories into /data so the WebUI can write to them at
# runtime even when the container filesystem is read-only. The actual
# directories are created by start.sh on first launch under the /data volume.
RUN git clone --branch "${WEBUI_REF}" --single-branch https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "${WEBUI_DIR}" \
  && rm -rf "${WEBUI_DIR}/repositories" \
  && ln -s /data/repositories "${WEBUI_DIR}/repositories" \
  && rm -rf "${WEBUI_DIR}/config_states" \
  && ln -s /data/config_states "${WEBUI_DIR}/config_states" \
  && rm -rf "${WEBUI_DIR}/extensions" \
  && ln -s /data/extensions "${WEBUI_DIR}/extensions" \
  && chown -R sdwebui:sdwebui "${WEBUI_DIR}"

# Create the /config directory that holds auth files and state.
# The actual contents are bind-mounted from the host (appdata on Unraid);
# this just ensures the mount point exists and has correct ownership in the
# image so the read-only container filesystem doesn't cause confusion.
RUN mkdir -p /config && chown sdwebui:sdwebui /config

# Overlay the custom launch.py wrapper that redacts sensitive CLI arguments
# (--gradio-auth, --gradio-auth-path, --api-auth, --api-auth-path) from
# startup log output. See WebUI/launch.py for the full redaction logic.
COPY WebUI/launch.py "${WEBUI_DIR}/launch.py"
RUN chown sdwebui:sdwebui "${WEBUI_DIR}/launch.py"

# ------------------------------------------------------------------------------
# Copy entrypoint scripts (from this repository)
#
# entrypoint.sh runs as root, self-heals /data ownership if needed, then drops
# to the unprivileged application user via setpriv before exec-ing start.sh.
# This is the standard "init as root, drop privileges" pattern used by postgres,
# nginx, redis, and many other production container images.
# ------------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
COPY start.sh /start.sh
COPY webui-auth.txt /webui-auth.txt
RUN chmod 0755 /entrypoint.sh /start.sh \
 && chmod 0644 /webui-auth.txt \
 && chown root:root /entrypoint.sh \
 && chown sdwebui:sdwebui /start.sh

# Include license and third-party notices in the image for distribution clarity.
COPY LICENSE THIRD_PARTY_NOTICES.md /usr/share/doc/a1111-webui-aegisnir/
COPY LICENSES/AGPL-3.0.txt /usr/share/doc/a1111-webui-aegisnir/LICENSES/AGPL-3.0.txt

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
EXPOSE 7860

# ------------------------------------------------------------------------------
# Healthcheck
# Probes whether the Gradio HTTP server is accepting TCP connections on :7860.
# This is a lightweight liveness signal, not a correctness check — a healthy
# status only means "something answered on the port," not that the app is
# fully functional or authenticated.
#
# Timer rationale (tuned for A1111 on Unraid):
#   --start-period 600s   First-run bootstrap installs ~4 GB of Python deps;
#                         10 min grace avoids false-unhealthy during that window.
#   --interval     120s   Check every 2 min — frequent enough to catch crashes,
#                         rare enough to not spam during model loads.
#   --timeout       30s   Model swaps and extension installs can briefly stall
#                         the event loop; 30 s absorbs transient pauses.
#   --retries        5    Requires 5 consecutive failures (~10+ min of total
#                         unresponsiveness) before marking unhealthy, which
#                         virtually eliminates false positives from normal
#                         heavy operations (model loading, image browser, etc.).
#
# Net effect: the container must be completely unresponsive for roughly
# 12–13 minutes straight before Docker/Unraid flips the status to unhealthy.
# Normal heavy workloads (ControlNet preprocessors, batch generation,
# thousands of thumbnails) do NOT block the HTTP server that long because
# Gradio handles requests in separate threads.
# ------------------------------------------------------------------------------
HEALTHCHECK --interval=120s --timeout=30s --start-period=600s --retries=5 \
  CMD python3 -c "import socket; s=socket.socket(); s.settimeout(5); s.connect(('127.0.0.1', 7860)); s.close()" || exit 1


# Strip all SUID/SGID bits from binaries so no binary in the image can
# escalate privileges if the container is compromised. Skips virtual
# filesystems (/proc, /sys, /dev) which are kernel-managed.
RUN find / -perm /6000 -type f -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' -exec chmod a-s {} + || true

# The container starts as root so entrypoint.sh can self-heal /data ownership.
# It then drops to sdwebui (UID 99) via setpriv before exec-ing start.sh.
# Runtime hardening should still be reviewed at the container runtime layer
# (for example: read-only root filesystem, dropped capabilities, no-new-
# privileges, explicit writable mounts, network exposure limits, etc.).
ENTRYPOINT ["/entrypoint.sh"]
