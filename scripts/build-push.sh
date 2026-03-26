#!/usr/bin/env bash
#
# scripts/build-push.sh
#
# Builds the Docker image from the current repo state and pushes it to GHCR.
#
# Branch behaviour:
#   main  → pushes :latest and :<version>
#   dev   → pushes :dev   and :<version>
#   other → pushes :dev   and :<version>  (fallback)
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
#   docker inspect ghcr.io/aegisnir/a1111-webui-aegisnir:latest \
#     --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
#   Expected output: v1.0.3

set -euo pipefail

IMAGE="ghcr.io/aegisnir/a1111-webui-aegisnir"
VERSION="v1.0.3"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [[ "${BRANCH}" == "main" ]]; then
  ROLLING_TAG="latest"
else
  ROLLING_TAG="dev"
fi

echo "Branch: ${BRANCH} — pushing ${IMAGE}:${ROLLING_TAG} and ${IMAGE}:${VERSION} ..."

docker buildx build \
  --platform linux/amd64 \
  --build-arg IMAGE_VERSION="${VERSION}" \
  --tag "${IMAGE}:${ROLLING_TAG}" \
  --tag "${IMAGE}:${VERSION}" \
  --push \
  .

echo ""
echo "Done. Verifying version label on pushed image..."
docker pull "${IMAGE}:${ROLLING_TAG}" --quiet
docker inspect "${IMAGE}:${ROLLING_TAG}" \
  --format "Pushed image version: {{index .Config.Labels \"org.opencontainers.image.version\"}}"
