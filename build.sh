#!/bin/bash
# Build LidAwake, wrap it in a .app bundle, and install to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="LidAwake.app"
CONTENTS="$APP/Contents"

echo "Compiling LidAwake.swift…"
swiftc LidAwake.swift -o LidAwake -framework Cocoa -framework IOKit -framework CoreGraphics

echo "Building $APP bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp LidAwake "$CONTENTS/MacOS/LidAwake"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>           <string>LidAwake</string>
    <key>CFBundleExecutable</key>     <string>LidAwake</string>
    <key>CFBundleIdentifier</key>     <string>local.lidawake</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key> <string>11.0</string>
    <key>LSUIElement</key>            <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>LidAwake uses System Events to manage its Login Items entry.</string>
</dict>
</plist>
PLIST

echo "Built $APP"

# Install to /Applications, asking before clobbering an existing copy.
DEST="/Applications/$APP"
if [ -e "$DEST" ]; then
    read -r -p "$DEST already exists. Overwrite? [y/N] " reply
    case "$reply" in
        [yY]*) ;;
        *) echo "Skipped install. Run ./$APP/Contents/MacOS/LidAwake to test locally."; exit 0 ;;
    esac
fi
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "Installed to $DEST"
