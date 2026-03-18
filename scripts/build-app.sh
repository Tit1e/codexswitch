#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
DERIVED_APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/Codex Switch.app"
APP_PATH="$BUILD_DIR/Release/Codex Switch.app"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

xcodebuild \
  -project "$ROOT_DIR/codexswitch.xcodeproj" \
  -scheme codexswitch \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

mkdir -p "$BUILD_DIR/Release"
rm -rf "$APP_PATH"
cp -R "$DERIVED_APP_PATH" "$APP_PATH"

echo ""
echo "App built at:"
echo "$APP_PATH"
