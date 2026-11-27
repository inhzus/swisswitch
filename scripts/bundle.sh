#!/usr/bin/env bash
# Builds swisswitch and wraps it in build/Swisswitch.app (menu-bar style, no Dock icon).
#
#   scripts/bundle.sh [release|debug]
#
#   VERSION        CFBundleShortVersionString (default: the one in Resources/Info.plist)
#   SIGN_IDENTITY  codesign identity to use (CI). A "Developer ID …" identity also gets the
#                  hardened runtime and a secure timestamp, as notarization requires.
#
# Without SIGN_IDENTITY it signs with the first local identity found (override with
# SWISSWITCH_SIGN_IDENTITY):
#   1. "Swisswitch Release": the release certificate, so a local build shares the
#      Accessibility grant of the installed release (the grant is per bundle ID + certificate)
#   2. ad-hoc, which ties the grant to this exact build
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
    IDENTITY=""
    for candidate in ${SWISSWITCH_SIGN_IDENTITY:+"$SWISSWITCH_SIGN_IDENTITY"} "Swisswitch Release"; do
        if security find-certificate -c "$candidate" >/dev/null 2>&1; then
            IDENTITY="$candidate"
            break
        fi
    done
    if [[ -n "$IDENTITY" ]]; then
        echo "signing with \"$IDENTITY\""
        codesign --force --sign "$IDENTITY" "$APP"
    else
        echo "note: \"Swisswitch Release\" not in keychain; signing ad-hoc (set SWISSWITCH_SIGN_IDENTITY to use another identity)"
        codesign --force --sign - "$APP"
    fi
fi

echo "Built $APP ($(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") ($BUILD_NUMBER))"
