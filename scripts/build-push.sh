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
#   Expected output: the git tag (e.g. v1.0.3) or "dev" if no tags exist

set -euo pipefail

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Working directory is dirty. Commit or stash changes before building." >&2
  exit 1
fi

IMAGE="ghcr.io/aegisnir/a1111-webui-aegisnir"
VERSION="$(git describe --tags --always 2>/dev/null || echo 'dev')"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [[ "${BRANCH}" == "main" ]]; then
  ROLLING_TAG="latest"
else
  ROLLING_TAG="dev"
fi

echo "Branch: ${BRANCH} -- pushing ${IMAGE}:${ROLLING_TAG} and ${IMAGE}:${VERSION} ..."

docker buildx build \
  --platform linux/amd64 \
  --build-arg IMAGE_VERSION="${VERSION}" \
  --tag "${IMAGE}:${ROLLING_TAG}" \
  --tag "${IMAGE}:${VERSION}" \
  --sbom=true \
  --provenance=true \
  --load \
  .

echo ""
echo "Scanning image before push..."
if command -v trivy >/dev/null 2>&1; then
  trivy image --severity HIGH,CRITICAL --exit-code 1 "${IMAGE}:${ROLLING_TAG}" || {
    echo "ERROR: Trivy found HIGH/CRITICAL vulnerabilities. Fix before pushing." >&2
    exit 1
  }
  echo "Trivy scan passed."
else
  echo "WARNING: trivy not installed. Skipping pre-push scan."
fi

echo ""
echo "Pushing images..."
docker push "${IMAGE}:${ROLLING_TAG}"
docker push "${IMAGE}:${VERSION}"

echo ""
echo "Done. Verifying version label on pushed image..."
docker pull "${IMAGE}:${ROLLING_TAG}" --quiet
docker inspect "${IMAGE}:${ROLLING_TAG}" \
  --format "Pushed image version: {{index .Config.Labels \"org.opencontainers.image.version\"}}"
