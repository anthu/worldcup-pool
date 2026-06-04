#!/usr/bin/env bash
#
# Build and push the World Cup Pool container image to Snowflake Image Repository.
#
# Usage:
#   ./scripts/build_and_push_image.sh [--tag TAG]
#
# Prerequisites:
#   - Docker installed and running
#   - Authenticated to Snowflake image registry:
#     docker login <orgname>-<acctname>.registry.snowflakecomputing.com \
#       -u <user> --password-stdin <<< "$(snow connection generate-token)"
#
# Environment variables:
#   SNOWFLAKE_REGISTRY  - Registry URL (e.g., orgname-acctname.registry.snowflakecomputing.com)
#   IMAGE_REPO_PATH     - Repository path (e.g., worldcup_pool_provider/app/image_repo)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
TAG="${1:-latest}"
IMAGE_NAME="worldcup-pool"

# Required environment
: "${SNOWFLAKE_REGISTRY:?Set SNOWFLAKE_REGISTRY to your Snowflake image registry URL}"
: "${IMAGE_REPO_PATH:?Set IMAGE_REPO_PATH to the image repository path (e.g., db/schema/repo)}"

FULL_IMAGE_URI="${SNOWFLAKE_REGISTRY}/${IMAGE_REPO_PATH}/${IMAGE_NAME}:${TAG}"

echo "==> Building Docker image: ${IMAGE_NAME}:${TAG}"
docker build \
  -t "${IMAGE_NAME}:${TAG}" \
  -f "${PROJECT_ROOT}/app/container/Dockerfile" \
  "${PROJECT_ROOT}/app/container"

echo "==> Tagging for Snowflake registry: ${FULL_IMAGE_URI}"
docker tag "${IMAGE_NAME}:${TAG}" "${FULL_IMAGE_URI}"

echo "==> Pushing to Snowflake registry..."
docker push "${FULL_IMAGE_URI}"

echo "==> Done. Image available at: ${FULL_IMAGE_URI}"
echo ""
echo "To use in the Native App manifest, reference:"
echo "  /${IMAGE_REPO_PATH}/${IMAGE_NAME}:${TAG}"
