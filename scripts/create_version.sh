#!/usr/bin/env bash
#
# Upload app files to stage and create/patch a version on the Application Package.
#
# Usage:
#   ./scripts/create_version.sh [--version VERSION] [--patch]
#
# Options:
#   --version VERSION  Version label (default: v1_0)
#   --patch            Add a patch to existing version instead of creating new version
#
# Prerequisites:
#   - snow CLI installed and configured
#   - ACCOUNTADMIN role (or role with ownership on the application package)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
VERSION="v1_0"
PATCH_MODE=false
PACKAGE_NAME="WORLDCUP_POOL_PKG"
STAGE_PATH="@${PACKAGE_NAME}.STAGE.APP_CODE"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --patch)
      PATCH_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "==> Uploading app files to ${STAGE_PATH}"

# Upload core files
snow stage copy "${PROJECT_ROOT}/app/manifest.yml" "${STAGE_PATH}/" --overwrite --connection default
snow stage copy "${PROJECT_ROOT}/app/setup_script.sql" "${STAGE_PATH}/" --overwrite --connection default
snow stage copy "${PROJECT_ROOT}/app/readme.md" "${STAGE_PATH}/" --overwrite --connection default

# Upload procedures
if [ -d "${PROJECT_ROOT}/app/procedures" ]; then
  echo "==> Uploading procedures/"
  snow stage copy "${PROJECT_ROOT}/app/procedures/" "${STAGE_PATH}/procedures/" --overwrite --connection default
fi

# Upload data files
if [ -d "${PROJECT_ROOT}/app/data" ]; then
  echo "==> Uploading data/"
  snow stage copy "${PROJECT_ROOT}/app/data/" "${STAGE_PATH}/data/" --overwrite --connection default
fi

echo "==> Files uploaded successfully"
echo ""

# Create or patch version
if [ "$PATCH_MODE" = true ]; then
  echo "==> Adding patch to version ${VERSION}"
  snow sql -q "ALTER APPLICATION PACKAGE ${PACKAGE_NAME} ADD PATCH FOR VERSION ${VERSION} USING '${STAGE_PATH}';" --connection default
else
  echo "==> Creating version ${VERSION}"
  snow sql -q "ALTER APPLICATION PACKAGE ${PACKAGE_NAME} ADD VERSION ${VERSION} USING '${STAGE_PATH}';" --connection default

  echo "==> Setting default release directive to ${VERSION} PATCH 0"
  snow sql -q "ALTER APPLICATION PACKAGE ${PACKAGE_NAME} SET DEFAULT RELEASE DIRECTIVE VERSION = ${VERSION} PATCH = 0;" --connection default
fi

echo ""
echo "==> Done. Version status:"
snow sql -q "SHOW VERSIONS IN APPLICATION PACKAGE ${PACKAGE_NAME};" --connection default
