// Renders dmg-bg.png (640x400): DMG window background with a drag-to-install arrow.
// Regenerate: swiftc -O dmgbg.swift -o "$TMP/mkbg" && "$TMP/mkbg" dmg-bg.png
import AppKit

let W = 640, H = 400
let out = CommandLine.arguments.dropFirst().first ?? "dmg-bg.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Soft light gradient backdrop so the icons pop.
let cs = CGColorSpaceCreateDeviceRGB()
let g = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1),
    CGColor(red: 0.90, green: 0.92, blue: 0.97, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// Arrow (bottom-left origin; icons sit centered at y=200-from-top = y=200 here).
let y: CGFloat = CGFloat(H) - 200   // 200
let blue = CGColor(red: 0.42, green: 0.31, blue: 0.86, alpha: 0.55)
ctx.setStrokeColor(blue); ctx.setLineWidth(11); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 258, y: y)); ctx.addLine(to: CGPoint(x: 372, y: y)); ctx.strokePath()
ctx.setFillColor(blue)                          // arrowhead
ctx.move(to: CGPoint(x: 398, y: y))
ctx.addLine(to: CGPoint(x: 368, y: y + 20))
ctx.addLine(to: CGPoint(x: 368, y: y - 20))
ctx.closePath(); ctx.fillPath()

// Title.
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.36, alpha: 1),
    .paragraphStyle: para]
NSString(string: "Drag ANC to Applications").draw(
    in: NSRect(x: 0, y: CGFloat(H) - 70, width: CGFloat(W), height: 30), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
