#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$BUILD_DIR/Release"
APP_NAME="Codex Switch.app"
DMG_NAME="Codex-Switch-macOS.dmg"
APP_PATH="$RELEASE_DIR/$APP_NAME"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging"

"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"

hdiutil create \
  -volname "Codex Switch" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo ""
echo "DMG built at:"
echo "$DMG_PATH"
