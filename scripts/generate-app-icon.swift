import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent(".build/app-icon")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Arc-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func render(_ size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
                                       pixelsHigh: size, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ArcIcon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 256, y: CGFloat(size) / 256)

    let tile = NSBezierPath(roundedRect: CGRect(x: 16, y: 16, width: 224, height: 224),
                            xRadius: 50, yRadius: 50)
    NSColor(srgbRed: 0.09, green: 0.11, blue: 0.15, alpha: 1).setFill()
    tile.fill()

    let orbit = NSBezierPath()
    orbit.appendArc(withCenter: CGPoint(x: 128, y: 128), radius: 84,
                    startAngle: 65, endAngle: 360, clockwise: false)
    orbit.lineWidth = 24
    orbit.lineCapStyle = .round
    NSColor.white.setStroke()
    orbit.stroke()

    NSColor.white.setFill()
    NSBezierPath(ovalIn: CGRect(x: 192, y: 174, width: 28, height: 28)).fill()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ArcIcon", code: 2)
    }
    return data
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in sizes {
    try render(size).write(to: iconset.appendingPathComponent(name + ".png"))
}
try render(1024).write(to: output.appendingPathComponent("AppIcon.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", output.appendingPathComponent("AppIcon.icns").path,
                     iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { throw NSError(domain: "ArcIcon", code: 3) }
