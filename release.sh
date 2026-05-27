#!/bin/bash
# Build a universal (arm64 + x86_64) LidAwake.app, ad-hoc sign it, and package
# a drag-to-Applications LidAwake.dmg for distribution (e.g. GitHub Releases).
set -euo pipefail
cd "$(dirname "$0")"

APP="LidAwake.app"
CONTENTS="$APP/Contents"
DMG="LidAwake.dmg"
VOLNAME="LidAwake"
STAGING="dmg-staging"

echo "Compiling universal binary (arm64 + x86_64)…"
swiftc LidAwake.swift -target arm64-apple-macos12  -o LidAwake-arm64 \
    -framework Cocoa -framework IOKit -framework CoreGraphics
swiftc LidAwake.swift -target x86_64-apple-macos12 -o LidAwake-x86_64 \
    -framework Cocoa -framework IOKit -framework CoreGraphics
lipo -create -output LidAwake LidAwake-arm64 LidAwake-x86_64
rm -f LidAwake-arm64 LidAwake-x86_64
echo -n "  → "; lipo -archs LidAwake

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
    <key>LSMinimumSystemVersion</key> <string>12.0</string>
    <key>LSUIElement</key>            <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>LidAwake uses System Events to manage its Login Items entry.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so the bundle has a stable code signature (no Developer ID,
# so users still clear Gatekeeper manually — see README "Install").
echo "Ad-hoc signing ${APP}…"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "Packaging ${DMG}…"
rm -rf "$STAGING" "$DMG"
mkdir "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
