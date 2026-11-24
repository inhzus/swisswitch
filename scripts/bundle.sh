#!/usr/bin/env bash
# Builds swisswitch and wraps it in build/Swisswitch.app (menu-bar style, no Dock icon).
#
#   scripts/bundle.sh [release|debug]
#
#   VERSION        CFBundleShortVersionString (default: the one in Resources/Info.plist)
#   SIGN_IDENTITY  codesign identity to use (CI). A "Developer ID …" identity also gets the
#                  hardened runtime and a secure timestamp, as notarization requires.
#
# Without SIGN_IDENTITY it signs with the local "swisswitch Dev" identity (see
# scripts/make-cert.sh, override with SWISSWITCH_SIGN_IDENTITY) when present, else ad-hoc.
# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc signing ties it to
# this exact build.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Swisswitch.app"
PLIST="$APP/Contents/Info.plist"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/swisswitch" "$APP/Contents/MacOS/swisswitch"
cp Resources/Info.plist "$PLIST"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    if [[ "$SIGN_IDENTITY" == "Developer ID"* ]]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    else
        codesign --force --sign "$SIGN_IDENTITY" "$APP"
    fi
else
    IDENTITY="${SWISSWITCH_SIGN_IDENTITY:-swisswitch Dev}"
    if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
        codesign --force --sign "$IDENTITY" "$APP"
    else
        echo "note: no \"$IDENTITY\" certificate; signing ad-hoc (run scripts/make-cert.sh)"
        codesign --force --sign - "$APP"
    fi
fi

echo "Built $APP ($(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") ($BUILD_NUMBER))"
