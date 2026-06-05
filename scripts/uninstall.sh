#!/bin/bash
# scripts/uninstall.sh
# Completely uninstalls and resets all cached copies, settings, and Accessibility entries for Copy Cat.

echo "→ Terminating running instances of Copy Cat..."
killall "Copy Cat" || true
killall Maccy || true

echo "→ Removing Copy Cat application binaries..."
rm -rf "/Applications/Copy Cat.app" || true
rm -rf "/Applications/CopyCat.app" || true
rm -rf "/Applications/Maccy.app" || true
rm -rf ~/Applications/"Copy Cat.app" || true
rm -rf ~/Applications/"CopyCat.app" || true

echo "→ Resetting system defaults and accessibility permissions database..."
tccutil reset Accessibility com.copycat.app || true
tccutil reset Accessibility org.p0deje.Maccy || true
defaults delete com.copycat.app || true
defaults delete org.p0deje.Maccy || true

echo "→ Clearing application support, cache, and state files..."
rm -rf ~/Library/Application\ Support/com.copycat.app || true
rm -rf ~/Library/Application\ Support/Copy\ Cat || true
rm -rf ~/Library/Caches/com.copycat.app || true
rm -rf ~/Library/Containers/com.copycat.app || true

echo "✓ Uninstalled and reset successfully!"
