#!/usr/bin/env bash
#
# scripts/build-push.sh
#
# Builds the Docker image from the current repo state and pushes it to GHCR
# under both the :dev rolling tag and the explicit :v1.0.3 version tag.
#
# Usage:
#   bash scripts/build-push.sh
#
# Prerequisites:
#   - Run from the root of this repository
#   - Already logged in to GHCR:
#       docker login ghcr.io -u aegisnir
#
# After pushing, verify the version label landed correctly:
#   docker inspect ghcr.io/aegisnir/a1111-webui-aegisnir:dev \
#     --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
#   Expected output: v1.0.3

set -euo pipefail

IMAGE="ghcr.io/aegisnir/a1111-webui-aegisnir"
VERSION="v1.0.3"

echo "Building and pushing ${IMAGE}:dev and ${IMAGE}:${VERSION} ..."

docker buildx build \
  --platform linux/amd64 \
  --build-arg IMAGE_VERSION="${VERSION}" \
  --tag "${IMAGE}:dev" \
  --tag "${IMAGE}:${VERSION}" \
  --push \
  .

echo ""
echo "Done. Verifying version label on pushed image..."
docker pull "${IMAGE}:dev" --quiet
docker inspect "${IMAGE}:dev" \
  --format 'Pushed image version: {{index .Config.Labels "org.opencontainers.image.version"}}'
