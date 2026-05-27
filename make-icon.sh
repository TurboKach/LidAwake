#!/bin/bash
# Generate AppIcon.icns: a white coffee cup on a warm amber rounded-rect,
# rendered from the cup.and.saucer.fill SF Symbol. Run occasionally; the
# resulting AppIcon.icns is committed and copied into the bundle by build.sh.
set -euo pipefail
cd "$(dirname "$0")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/render.swift" <<'SWIFT'
import Cocoa

let canvas: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
let ctx = NSGraphicsContext(bitmapImageRep: rep)!

// Warm rounded-rect background (Big Sur icon-grid proportions).
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let inset: CGFloat = 92
let rect = CGRect(x: inset, y: inset, width: canvas - 2*inset, height: canvas - 2*inset)
NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237).addClip()
NSGradient(starting: NSColor(srgbRed: 0.85, green: 0.55, blue: 0.28, alpha: 1),
           ending:   NSColor(srgbRed: 0.45, green: 0.26, blue: 0.13, alpha: 1))!
    .draw(in: rect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// White cup symbol, centered, with a soft shadow.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    color.set()
    let r = NSRect(origin: .zero, size: image.size)
    image.draw(in: r)
    r.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}
let cfg = NSImage.SymbolConfiguration(pointSize: 800, weight: .regular)
guard let base = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil),
      let sym = base.withSymbolConfiguration(cfg) else { exit(1) }
let white = tinted(sym, .white)

let target = rect.width * 0.56
let scale = target / max(white.size.width, white.size.height)
let w = white.size.width * scale, h = white.size.height * scale
let drawRect = CGRect(x: (canvas - w)/2, y: (canvas - h)/2, width: w, height: h)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.shadowBlurRadius = 28
shadow.set()
white.draw(in: drawRect)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

echo "Rendering icon…"
swiftc "$WORK/render.swift" -o "$WORK/render" -framework Cocoa
"$WORK/render" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz"           "$WORK/icon-1024.png" --out "$ICONSET/icon_${sz}x${sz}.png"     >/dev/null
    sips -z "$((sz*2))" "$((sz*2))" "$WORK/icon-1024.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "Wrote AppIcon.icns"
