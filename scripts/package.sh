#!/usr/bin/env bash
# Builds build/Swisswitch.app and zips it as build/Swisswitch-<version>.zip, for a release.
#
# Takes VERSION and SIGN_IDENTITY like bundle.sh. With NOTARY_KEY_ID, NOTARY_ISSUER_ID and
# NOTARY_KEY (path to an App Store Connect API .p8 key) set, also notarizes and staples;
# that needs a Developer ID identity.
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/bundle.sh release

APP="build/Swisswitch.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
ZIP="build/Swisswitch-$VERSION.zip"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && -n "${NOTARY_KEY:-}" ]]; then
    xcrun notarytool submit "$ZIP" --wait \
        --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
    xcrun stapler staple "$APP"
    # Re-zip so the download carries the stapled ticket.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "Packaged $ZIP"
echo "sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
