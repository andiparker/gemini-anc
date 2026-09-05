// Renders icon.png (1024x1024): white headphones glyph on a blue gradient squircle.
// Regenerate with: swiftc -O icon.swift -o /tmp/mkicon && /tmp/mkicon icon.png
import AppKit

let S = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Squircle background with an Apple-ish margin.
let margin: CGFloat = 90
let rect = CGRect(x: margin, y: margin, width: CGFloat(S) - 2*margin, height: CGFloat(S) - 2*margin)
let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237, cornerHeight: rect.width * 0.2237, transform: nil)
ctx.saveGState(); ctx.addPath(path); ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.24, green: 0.51, blue: 0.90, alpha: 1),   // top-left blue
    CGColor(red: 0.42, green: 0.31, blue: 0.86, alpha: 1)]   // bottom-right indigo
    as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: margin, y: CGFloat(S) - margin),
                       end: CGPoint(x: CGFloat(S) - margin, y: margin), options: [])
ctx.restoreGState()

// White headphones glyph, centered at ~52% of the icon.
let cfg = NSImage.SymbolConfiguration(pointSize: 520, weight: .regular)
let sym = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!
    .withSymbolConfiguration(cfg)!
let white = NSImage(size: sym.size, flipped: false) { r in
    sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
}
let target: CGFloat = CGFloat(S) * 0.52
let scale = target / max(white.size.width, white.size.height)
let w = white.size.width * scale, h = white.size.height * scale
white.draw(in: NSRect(x: (CGFloat(S) - w)/2, y: (CGFloat(S) - h)/2, width: w, height: h))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
