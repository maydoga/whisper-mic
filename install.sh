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
echo "==> Clearing the stale Accessibility grant..."
# TCC does not store "Hulpje is allowed". It stores a code signing requirement, and
# for an ad-hoc signed app that requirement is the cdhash of the exact binary that
# was approved. Every rebuild produces a new cdhash, so the old row keeps saying
# "allowed" while matching nothing that exists any more. The app is denied and the
# checkbox still looks ticked, which is why toggling it never helps.
#
# Dropping the row is the whole repair. No sudo needed, and the fresh launch below
# asks once. Verify afterwards with:
#   sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
#     "select hex(csreq) from access where service='kTCCServiceAccessibility' \
#      and client='$BUNDLE_ID';"
#   codesign -d -r- "$INSTALL_DIR/$APP_NAME.app"
# The cdhash in both must be the same.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

echo ""
echo "==> Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "Done! $APP_NAME is running in your menu bar."
echo ""
echo "One dialog will appear asking for Accessibility. Allow it, and everything works:"
echo "pasting at the cursor, window tiling, menu bar auto-hide. It is asked once per"
echo "install, because the grant is tied to this exact build."
echo "Shortcut: ⌃+⌥+⌘+Space"
