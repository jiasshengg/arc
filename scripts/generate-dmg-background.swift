import AppKit
import Foundation

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(".build/dmg")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// Finder uses the TIFF's logical size; render at 2x for Retina displays.
let size = NSSize(width: 660, height: 420)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1320, pixelsHigh: 840,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func centeredText(_ text: String, top: CGFloat, font: NSFont, color: NSColor) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let dimensions = string.size()
    string.draw(at: NSPoint(x: (size.width - dimensions.width) / 2,
                            y: size.height - top - dimensions.height))
}

let secondaryColor = NSColor(srgbRed: 0.44, green: 0.46, blue: 0.49, alpha: 1)
centeredText("A little more magic for your Mac.", top: 92,
             font: .systemFont(ofSize: 14), color: secondaryColor)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 304, y: 190))
arrow.line(to: NSPoint(x: 356, y: 190))
arrow.move(to: NSPoint(x: 345, y: 201))
arrow.line(to: NSPoint(x: 356, y: 190))
arrow.line(to: NSPoint(x: 345, y: 179))
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(srgbRed: 0.56, green: 0.58, blue: 0.61, alpha: 1).setStroke()
arrow.stroke()

centeredText("Drag Arc into Applications to install.", top: 348,
             font: .systemFont(ofSize: 14), color: secondaryColor)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .tiff, properties: [:])!
    .write(to: output.appendingPathComponent("background.tiff"))
try bitmap.representation(using: .png, properties: [:])!
    .write(to: output.appendingPathComponent("background.png"))
