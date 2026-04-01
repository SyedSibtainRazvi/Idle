#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-$(grep MARKETING_VERSION project.yml | head -1 | awk '{print $2}')}"
APP_NAME="Idle"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}-${VERSION}-macOS.dmg"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

echo "==> Building ${APP_NAME} ${VERSION} Release..."

# Generate Xcode project
xcodegen generate

# Build Release
xcodebuild \
  -project Idle.xcodeproj \
  -scheme Idle \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  MARKETING_VERSION="${VERSION}" \
  build

APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
  echo "error: ${APP_NAME}.app not found at ${APP_PATH}" >&2
  exit 1
fi

echo "==> Creating DMG..."

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

cp -a "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${BUILD_DIR}/${DMG_NAME}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${BUILD_DIR}/${DMG_NAME}"

rm -rf "${STAGING_DIR}"

echo "==> Done: ${BUILD_DIR}/${DMG_NAME}"
