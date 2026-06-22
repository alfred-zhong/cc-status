#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="CCStatus"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release

echo "Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/"

# Copy app icon
if [ -f "$PROJECT_DIR/Sources/$APP_NAME/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/$APP_NAME/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Ad-hoc 签名（macOS 通知等系统功能需要至少 ad-hoc 签名）
codesign --force --sign - "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"
