#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="WhisperMic"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building $APP_NAME (release)..."
swift build -c release 2>&1

# Find the built binary
BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BINARY" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "$SCRIPT_DIR/Sources/WhisperMic/Info.plist" "$CONTENTS/Info.plist"

# Generate app icon
echo "==> Generating app icon..."
if swift "$SCRIPT_DIR/scripts/generate-icon.swift" "$RESOURCES/AppIcon.icns" 2>/dev/null; then
    echo "    App icon created"
else
    echo "    Warning: Could not create app icon, continuing without"
fi

echo "==> Done! App bundle at: $APP_BUNDLE"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To install: ./install.sh"
