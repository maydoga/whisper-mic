#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Hulpje"
APP_BUNDLE="$SCRIPT_DIR/build/$APP_NAME.app"
INSTALL_DIR="/Applications"
BUNDLE_ID="com.maydoga.hulpje"

# Kill running instance
pkill -f "$APP_NAME" 2>/dev/null && sleep 1 || true

echo "==> Building $APP_NAME..."
"$SCRIPT_DIR/build.sh"

echo ""
echo "==> Code signing..."
# Ad-hoc signing keys the Accessibility grant to the binary's cdhash, which changes
# on every rebuild. The stable --identifier is not enough: after installing you have
# to remove WhisperMic from System Settings > Accessibility and add it back.
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
echo "IMPORTANT: the Accessibility grant does not survive a rebuild. If the menu bar icon"
echo "shows a crossed-out mic, open System Settings > Privacy & Security > Accessibility,"
echo "remove Hulpje with the - button and add it back with + from /Applications."
echo "Shortcut: ⌃+⌥+⌘+Space"
