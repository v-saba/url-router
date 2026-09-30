// Draws the app icon (option-key glyph on a squircle) to a 1024x1024 PNG.
// Usage: swift scripts/make_icon.swift Resources/AppIcon-1024.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: the art sits on an 824pt rounded rect inside the 1024 canvas.
let box: CGFloat = 824
let inset = (size - box) / 2
let rect = CGRect(x: inset, y: inset, width: box, height: box)
let radius = box * 0.2237

ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.29, green: 0.51, blue: 0.99, alpha: 1),
                                   CGColor(red: 0.45, green: 0.27, blue: 0.91, alpha: 1)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

// Option key (⌥): one polyline — bottom-left horizontal, diagonal up, top-right horizontal.
let g = rect.insetBy(dx: box * 0.20, dy: box * 0.24)
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: g.minX + g.width * x, y: g.minY + g.height * y)
}

ctx.setLineWidth(box * 0.095)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Secondary branch: same white, dialled back so it reads behind the main route.
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
ctx.addLines(between: [pt(0.34, 0.08), pt(0.92, 0.08)])
ctx.strokePath()

// Main route, drawn last so the junction stays crisp.
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.addLines(between: [pt(0, 0.08), pt(0.34, 0.08), pt(0.66, 0.92), pt(1, 0.92)])
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
