#!/bin/bash
# deploy.sh
# Stops, cleans, builds, installs, and launches the updated Copy Cat application.
set -euo pipefail

echo "→ Terminating running instances of Copy Cat..."
killall "Copy Cat" || true
killall Maccy || true

echo "→ Removing existing Copy Cat applications..."
rm -rf "/Applications/Copy Cat.app"
rm -rf "/Applications/CopyCat.app"
rm -rf "/Applications/Maccy.app"
rm -rf ~/Applications/"Copy Cat.app"
rm -rf ~/Applications/"CopyCat.app"

echo "→ Cleaning previous build artifacts..."
rm -rf build/
rm -f CopyCat-*.dmg

echo "→ Compiling and packaging app..."
bash scripts/make-dmg.sh

echo "→ Installing new app to /Applications..."
cp -R "build/DerivedData/Build/Products/Release/Copy Cat.app" "/Applications/"

echo "→ Launching the updated Copy Cat..."
open "/Applications/Copy Cat.app"

echo "✓ Deployment complete and application launched!"
