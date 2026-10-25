// Renders an SVG file to a square PNG.
// Usage: swift scripts/render-svg.swift <in.svg> <out.png> <pixels>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let pixels = Int(args[3]), let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: render-svg.swift <in.svg> <out.png> <pixels>\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
