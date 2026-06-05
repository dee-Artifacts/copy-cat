#!/bin/bash
# Builds Copy Cat and packages it as a distributable DMG.
# Usage: bash scripts/make-dmg.sh
set -euo pipefail

APP_NAME="Copy Cat"
VERSION="2.6.1"
DMG_NAME="CopyCat-${VERSION}.dmg"
DERIVED_DATA="build/DerivedData"
BUILD_DIR="${DERIVED_DATA}/Build/Products/Release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
# Stable self-signed identity. Reusing the SAME cert for every release keeps the
# app's code fingerprint constant, so users' Accessibility grant persists across
# updates. Falls back to ad-hoc ("-") if the cert isn't present on this machine.
SIGN_IDENTITY="Copy Cat Developer"

echo "→ Building ${APP_NAME} ${VERSION}..."
xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "^(error:|warning: |Build succeeded|\*\* BUILD)"

if [ ! -d "$APP_PATH" ]; then
  echo "✗ Build failed — ${APP_PATH} not found"
  exit 1
fi

if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "→ Signing ${APP_NAME} with stable identity: ${SIGN_IDENTITY}..."
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  echo "⚠ Stable cert '${SIGN_IDENTITY}' not found — falling back to ad-hoc (Accessibility will NOT persist across updates)."
  codesign --force --deep --sign - "$APP_PATH"
fi
codesign --verify --verbose "$APP_PATH" 2>&1 | tail -1 || true

echo "→ Staging..."
STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "→ Creating DMG..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDBZ \
  "${DMG_NAME}"

rm -rf "$STAGING"
echo ""
echo "✓ Done: ${DMG_NAME}"
echo "  Attach to a GitHub release at: https://github.com/deepakkrishnar1618-svg/copy-cat/releases"
