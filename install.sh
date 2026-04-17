#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="WhisperMic"
APP_BUNDLE="$SCRIPT_DIR/build/$APP_NAME.app"
INSTALL_DIR="/Applications"
BUNDLE_ID="com.maydoga.whispermicapp"

# Kill running instance
pkill -f "$APP_NAME" 2>/dev/null && sleep 1 || true

echo "==> Building $APP_NAME..."
"$SCRIPT_DIR/build.sh"

echo ""
echo "==> Code signing..."
# Stable --identifier keeps TCC (Accessibility) grants valid across rebuilds.
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"

echo ""
echo "==> Installing to $INSTALL_DIR..."
# ditto overwrites in place, preserving the installed bundle's identity so the
# existing Accessibility permission keeps applying.
mkdir -p "$INSTALL_DIR/$APP_NAME.app"
ditto "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
echo "    Installed to $INSTALL_DIR/$APP_NAME.app"

echo ""
echo "==> Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "Done! $APP_NAME is running in your menu bar."
echo ""
echo "IMPORTANT: Add WhisperMic in System Settings > Privacy & Security > Privacy > Accessibility"
echo "Shortcut: ⌃+⌥+⌘+Space"
