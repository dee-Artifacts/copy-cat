#!/bin/bash
# Publishes a new Copy Cat update for Sparkle auto-update.
#
# Run this AFTER bumping the version in Xcode (both MARKETING_VERSION and
# CURRENT_PROJECT_VERSION — Sparkle compares CURRENT_PROJECT_VERSION/CFBundleVersion,
# so it MUST increase every release or no update is offered).
#
# What it does:
#   1. Builds + signs the DMG (scripts/make-dmg.sh)
#   2. Copies the DMG into updates/
#   3. Regenerates updates/appcast.xml, EdDSA-signing the DMG with the key in your
#      login keychain (the private half of SUPublicEDKey in Info.plist)
#
# Then YOU deploy the updates/ folder to Vercel so it is served at
#   https://copycat.deeproduct.org/updates/
# Installed apps pick up the new version on their next check.
#
# Usage: bash scripts/publish-update.sh
set -euo pipefail

VERSION="1.0.1"   # keep in sync with MARKETING_VERSION
DMG="CopyCat-${VERSION}-free.dmg"
UPDATES_DIR="updates"
FEED_PREFIX="https://copycat.deeproduct.org/updates/"

# Locate Sparkle's generate_appcast (works from either DerivedData location).
GA=$(find build/DerivedData "$HOME/Library/Developer/Xcode/DerivedData/Maccy-"* \
  -path "*artifacts/sparkle/Sparkle/bin/generate_appcast" 2>/dev/null | head -1)
if [ -z "${GA:-}" ]; then
  echo "✗ generate_appcast not found — build once in Xcode so Sparkle's tools resolve."
  exit 1
fi

echo "→ Building + signing DMG..."
bash scripts/make-dmg.sh

echo "→ Staging ${DMG} into ${UPDATES_DIR}/ ..."
mkdir -p "$UPDATES_DIR"
cp "$DMG" "$UPDATES_DIR/"

# Optional per-release notes: create updates/CopyCat-<version>.html and Sparkle
# will show it in the update dialog (generate_appcast links it automatically).

echo "→ Regenerating appcast (EdDSA-signing the DMG)..."
"$GA" --download-url-prefix "$FEED_PREFIX" "$UPDATES_DIR/"

echo ""
echo "✓ Done. Deploy these to Vercel (served at ${FEED_PREFIX}):"
echo "    ${UPDATES_DIR}/appcast.xml"
echo "    ${UPDATES_DIR}/${DMG}"
echo "    ${UPDATES_DIR}/CopyCat-${VERSION}-free.html   (if present)"
echo ""
echo "  Installed apps auto-update on their next check once it is live."
