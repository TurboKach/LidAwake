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
    <key>CFBundleShortVersionString</key> <string>1.1</string>
    <key>CFBundleIconFile</key>       <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key> <string>12.0</string>
    <key>LSUIElement</key>            <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>LidAwake uses System Events to manage its Login Items entry.</string>
</dict>
</plist>
PLIST

if [ ! -f AppIcon.icns ]; then
    echo "AppIcon.icns missing — run ./make-icon.sh first." >&2; exit 1
fi
mkdir -p "$CONTENTS/Resources"
cp AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# Ad-hoc sign so the bundle has a stable code signature (no Developer ID,
# so users still clear Gatekeeper manually — see README "Install").
echo "Ad-hoc signing ${APP}…"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

# ---- Styled DMG: gradient background with a drag-to-Applications arrow ----
WIN_W=620; WIN_H=400          # Finder window content size, in points
echo "Packaging ${DMG}…"
rm -rf "$STAGING" "$DMG" rw.dmg
mkdir -p "$STAGING/.background"

# Render the background at 1x and 2x, then combine into a HiDPI TIFF.
cat > "$STAGING/.bg.swift" <<SWIFT
import Cocoa
let W: CGFloat = $WIN_W, H: CGFloat = $WIN_H
func render(_ scale: CGFloat, _ path: String) {
    let pw = Int(W*scale), ph = Int(H*scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    g.scaleBy(x: scale, y: scale)
    // Warm diagonal gradient (gold → coral).
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.86, blue: 0.45, alpha: 1),
               ending:   NSColor(srgbRed: 0.96, green: 0.62, blue: 0.58, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -45)
    // Brown right-pointing arrow, centred between the two icons.
    let cy = H * 0.52
    let brown = NSColor(srgbRed: 0.42, green: 0.30, blue: 0.22, alpha: 0.70)
    brown.set()
    let shaftX0 = W*0.43, shaftX1 = W*0.52, headX = W*0.575
    let sh: CGFloat = 16, hh: CGFloat = 40
    let p = NSBezierPath()
    p.move(to: NSPoint(x: shaftX0, y: cy - sh))
    p.line(to: NSPoint(x: shaftX1, y: cy - sh))
    p.line(to: NSPoint(x: shaftX1, y: cy - hh))
    p.line(to: NSPoint(x: headX,   y: cy))
    p.line(to: NSPoint(x: shaftX1, y: cy + hh))
    p.line(to: NSPoint(x: shaftX1, y: cy + sh))
    p.line(to: NSPoint(x: shaftX0, y: cy + sh))
    p.close()
    p.fill()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}
render(1, CommandLine.arguments[1])
render(2, CommandLine.arguments[2])
SWIFT
swiftc "$STAGING/.bg.swift" -o "$STAGING/.bg" -framework Cocoa
"$STAGING/.bg" "$STAGING/bg1.png" "$STAGING/bg2.png"
tiffutil -cathidpicheck "$STAGING/bg1.png" "$STAGING/bg2.png" \
    -out "$STAGING/.background/background.tiff" >/dev/null
rm -f "$STAGING/.bg" "$STAGING/.bg.swift" "$STAGING/bg1.png" "$STAGING/bg2.png"

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Detach any same-named volume first — a duplicate (e.g. a previously
# downloaded LidAwake.dmg left mounted) makes `tell disk "LidAwake"` ambiguous.
while [ -d "/Volumes/$VOLNAME" ]; do
    hdiutil detach "/Volumes/$VOLNAME" -force >/dev/null 2>&1 || break
done

# Writable image so Finder can record the view layout, then compress.
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" \
    -fs HFS+ -format UDRW -ov rw.dmg >/dev/null
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen rw.dmg | grep '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOLNAME"
sleep 1

osascript <<APPLESCRIPT || echo "  (Finder styling skipped — grant Automation access and re-run for the layout)" >&2
tell application "Finder"
    tell disk "$VOLNAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, ${WIN_W}+200, ${WIN_H}+140}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "LidAwake.app" of container window to {150, 205}
        set position of item "Applications" of container window to {470, 205}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE" >/dev/null || hdiutil detach "$MOUNT" -force >/dev/null
hdiutil convert rw.dmg -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f rw.dmg
rm -rf "$STAGING"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
