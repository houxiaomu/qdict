#!/usr/bin/env bash
#
# Build an ad-hoc-signed Release DMG for personal distribution.
#
# Requirements:
#   - Xcode command line tools (xcodebuild)
#   - xcodegen          (brew install xcodegen)
#   - create-dmg        (brew install create-dmg) — optional; falls back to hdiutil
#
# Output:
#   build/Dictonary-<version>.dmg
#
# Recipients will see a Gatekeeper warning on first open because the app is
# ad-hoc signed. They need to right-click the .app → Open → Open. One time only.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Dictonary"
VERSION=$(awk '/MARKETING_VERSION:/ {print $2}' project.yml | tr -d '"' | head -1)
BUILD_DIR="./build"
RELEASE_DIR="$BUILD_DIR/Build/Products/Release"
APP_PATH="$RELEASE_DIR/$APP_NAME.app"
DMG_OUT="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building $APP_NAME ($VERSION) in Release"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  clean build \
  -quiet

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: $APP_PATH not built" >&2
  exit 1
fi

echo "==> Packaging DMG"
rm -f "$DMG_OUT"

if command -v create-dmg >/dev/null 2>&1; then
  # Polished drag-to-Applications layout
  create-dmg \
    --volname "$APP_NAME $VERSION" \
    --window-size 500 300 \
    --icon-size 96 \
    --icon "$APP_NAME.app" 130 130 \
    --app-drop-link 370 130 \
    --hdiutil-quiet \
    "$DMG_OUT" \
    "$APP_PATH"
else
  echo "   create-dmg not installed — falling back to plain hdiutil DMG."
  echo "   For a nicer drag-to-Applications layout: brew install create-dmg"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_OUT"
fi

echo
echo "✅ DMG created: $DMG_OUT"
echo "   Size: $(du -sh "$DMG_OUT" | cut -f1)"
echo
echo "Tell recipients: on first open they may see a Gatekeeper warning"
echo "(\"unidentified developer\"). They should right-click the app in"
echo "Applications and choose Open, then Open again in the dialog."
