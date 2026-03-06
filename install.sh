#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
INSTALL_DIR="$HOME/Applications"
APP_NAME="AutoScreenSnap"

echo "▶ Building $APP_NAME..."
xcodebuild \
  -project "$PROJECT_DIR/AutoScreenSnap.xcodeproj" \
  -scheme AutoScreenSnap \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

APP_DEST="$PROJECT_DIR/$APP_NAME.app"

echo "▶ Installing to project folder..."
rm -rf "$APP_DEST"
cp -R "$BUILD_DIR/Build/Products/Release/$APP_NAME.app" "$APP_DEST"

echo "▶ Signing with Apple Development certificate..."
CERT=$(security find-identity -p codesigning -v | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -n "$CERT" ]; then
    codesign --force --deep --sign "$CERT" \
        --entitlements "$PROJECT_DIR/AutoScreenSnap.entitlements" \
        "$APP_DEST" && echo "   Signed: $CERT"
else
    echo "   No Apple Development cert found, using ad-hoc signing"
fi

# Refresh icon cache
touch "$APP_DEST"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$APP_DEST" 2>/dev/null || true
killall Finder 2>/dev/null || true
killall Dock  2>/dev/null || true
echo "▶ Icon cache refreshed"

echo "▶ Killing any running instance..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

echo "▶ Launching $APP_NAME..."
open "$APP_DEST"

echo ""
echo "✅ Done! $APP_NAME is running from $APP_DEST"
echo ""
echo "Next step (one time only):"
echo "  When the permission dialog appears → click 'Open System Settings'"
echo "  Enable the toggle for $APP_NAME"
echo "  The app will relaunch automatically."
echo "  Permission is now permanent for this installation."
