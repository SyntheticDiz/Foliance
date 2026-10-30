import AppKit

// Original vector artwork: a geometric folded-page monogram with a restrained
// corporate palette. The bitmap is exactly 1024 pixels, independent of Retina.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: 1024); flip.scaleX(by: 1, yBy: -1); flip.concat()
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let tile = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 196, yRadius: 196)
NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.34, alpha: 1),
           ending: NSColor(calibratedRed: 0.055, green: 0.12, blue: 0.20, alpha: 1))!.draw(in: tile, angle: 65)
NSColor(calibratedRed: 0.45, green: 0.67, blue: 0.76, alpha: 0.18).setFill()
NSBezierPath(roundedRect: NSRect(x: 350, y: 292, width: 406, height: 484), xRadius: 28, yRadius: 28).fill()
NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.98, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 292, y: 248, width: 110, height: 520), xRadius: 20, yRadius: 20).fill()
NSBezierPath(roundedRect: NSRect(x: 292, y: 248, width: 434, height: 110), xRadius: 20, yRadius: 20).fill()
NSColor(calibratedRed: 0.54, green: 0.75, blue: 0.82, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 385, y: 452, width: 264, height: 104), xRadius: 18, yRadius: 18).fill()
let fold = NSBezierPath(); fold.move(to: NSPoint(x: 638, y: 248)); fold.line(to: NSPoint(x: 726, y: 336)); fold.line(to: NSPoint(x: 726, y: 268)); fold.curve(to: NSPoint(x: 706, y: 248), controlPoint1: NSPoint(x: 726, y: 257), controlPoint2: NSPoint(x: 717, y: 248)); fold.close()
NSColor(calibratedRed: 0.67, green: 0.82, blue: 0.88, alpha: 1).setFill(); fold.fill()
NSGraphicsContext.restoreGraphicsState()
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Assets/Foliance.png"))
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#1f4057"/><stop offset="1" stop-color="#0e1f33"/></linearGradient></defs><rect x="56" y="56" width="912" height="912" rx="196" fill="url(#bg)"/><rect x="350" y="292" width="406" height="484" rx="28" fill="#73abc2" opacity=".18"/><g fill="#f2f7fa"><rect x="292" y="248" width="110" height="520" rx="20"/><rect x="292" y="248" width="434" height="110" rx="20"/></g><rect x="385" y="452" width="264" height="104" rx="18" fill="#8abfd1"/><path d="M638 248L726 336V268Q726 248 706 248Z" fill="#abd1e0"/></svg>
"""
try svg.write(to: root.appendingPathComponent("Assets/Foliance.svg"), atomically: true, encoding: .utf8)
print("Generated Foliance corporate icon, 1024 × 1024, and matching SVG.")
