#!/bin/bash
# Helper script to resize icon-master.png into the AppIcon.appiconset.
set -euo pipefail

MASTER_ICON="assets/CopyCat - BG Logo.png"
APPICONSET_DIR="Maccy/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$MASTER_ICON" ]; then
  echo "Error: Master icon not found at $MASTER_ICON"
  exit 1
fi

echo "→ Generating AppIcon files..."

# Declare sizes and their respective output filenames
# format: "size:filename"
declare -a sizes=(
  "16:AppIcon (Big Sur)-16w.png"
  "32:AppIcon (Big Sur)-32w.png"
  "32:AppIcon (Big Sur)-32w-1.png"
  "64:AppIcon (Big Sur)-64w.png"
  "128:AppIcon (Big Sur)-128w.png"
  "256:AppIcon (Big Sur)-256w.png"
  "256:AppIcon (Big Sur)-256w-1.png"
  "512:AppIcon (Big Sur)-512w.png"
  "512:AppIcon (Big Sur)-512w-1.png"
  "1024:AppIcon (Big Sur)-1024w.png"
)

for item in "${sizes[@]}"; do
  size="${item%%:*}"
  filename="${item#*:}"
  output_path="${APPICONSET_DIR}/${filename}"

  echo "  - Generating ${filename} (${size}x${size})..."
  sips -z "$size" "$size" "$MASTER_ICON" --out "$output_path" > /dev/null
done

echo "→ Generating status bar menu icons and panel transparent logos..."
DARK_LOGO="assets/CopyCat - Dark Transparent Logo.png"
LIGHT_LOGO="assets/CopyCat - Light Transparent Logo.png"
STATUSBAR_DIR="Maccy/Assets.xcassets/StatusBarMenuImage.imageset"
PANEL_DIR="Maccy/Assets.xcassets/TransparentLogo.imageset"

if [ -f "$DARK_LOGO" ] && [ -f "$LIGHT_LOGO" ]; then
  # 1. Update panel transparent logos
  cp "$DARK_LOGO" "${PANEL_DIR}/dark_transparent_logo.png"
  cp "$LIGHT_LOGO" "${PANEL_DIR}/light_transparent_logo.png"
  
  # 2. Update status bar menu icons
  sips -z 16 16 "$DARK_LOGO" --out "${STATUSBAR_DIR}/LightMenuBar-16w.png" > /dev/null
  sips -z 32 32 "$DARK_LOGO" --out "${STATUSBAR_DIR}/LightMenuBar-32w.png" > /dev/null
  sips -z 16 16 "$LIGHT_LOGO" --out "${STATUSBAR_DIR}/DarkMenuBar-16w.png" > /dev/null
  sips -z 32 32 "$LIGHT_LOGO" --out "${STATUSBAR_DIR}/DarkMenuBar-32w.png" > /dev/null
  echo "✓ Done generating status bar menu icons and transparent panel logos!"
else
  echo "Error: Dark/Light Transparent logo variants not found in assets directory."
  exit 1
fi

echo "✓ Done generating icons!"
