#!/bin/sh
# Builds swisswitch and wraps it into build/Swisswitch.app (menu-bar style, no Dock icon).
set -e
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/swisswitch"
APP=build/Swisswitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/swisswitch"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Swisswitch</string>
    <key>CFBundleDisplayName</key><string>Swisswitch</string>
    <key>CFBundleIdentifier</key><string>io.zunish.Swisswitch</string>
    <key>CFBundleExecutable</key><string>swisswitch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# A stable identity (see scripts/make-cert.sh) keeps the Accessibility grant
# across rebuilds; ad-hoc signing ties it to this exact build.
IDENTITY="${SWISSWITCH_SIGN_IDENTITY:-swisswitch Dev}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "note: no \"$IDENTITY\" certificate; signing ad-hoc (run scripts/make-cert.sh)"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
