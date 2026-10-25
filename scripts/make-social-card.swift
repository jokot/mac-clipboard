// Draws the link preview image of the website, 1200 x 630 px.
// Usage: swift scripts/make-social-card.swift <icon.svg> <clip-window.png> <out.png>
// Run from the repo root:
//   swift scripts/make-social-card.swift assets/icon/icon.svg site/img/clip-window.png site/img/social-card.png
import AppKit

let args = CommandLine.arguments
guard args.count == 4,
      let icon = NSImage(contentsOfFile: args[1]),
      let shot = NSImage(contentsOfFile: args[2]) else {
    FileHandle.standardError.write("usage: make-social-card.swift <icon.svg> <clip-window.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}

let size = NSSize(width: 1200, height: 630)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

// Ground: white, with a light panel at the right behind the screenshot.
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()
NSColor(red: 0.965, green: 0.965, blue: 0.976, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 640, y: -40, width: 640, height: 710), xRadius: 48, yRadius: 48).fill()

// Left: icon, name, tagline, line of facts. AppKit y goes up from the bottom.
icon.draw(in: NSRect(x: 58, y: 372, width: 196, height: 196))

func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat) {
    let para = NSMutableParagraphStyle()
    para.lineSpacing = size * 0.06
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: para,
        .kern: size * -0.02,
    ]
    let string = NSAttributedString(string: text, attributes: attrs)
    let box = string.boundingRect(with: NSSize(width: width, height: 400), options: [.usesLineFragmentOrigin])
    string.draw(with: NSRect(x: point.x, y: point.y - box.height, width: width, height: box.height),
                options: [.usesLineFragmentOrigin])
}

let ink = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let text = NSColor(red: 0.29, green: 0.29, blue: 0.31, alpha: 1)
let accent = NSColor(red: 94 / 255, green: 92 / 255, blue: 230 / 255, alpha: 1)
draw("MaClip", at: NSPoint(x: 84, y: 372), size: 72, weight: .heavy, color: ink, width: 520)
draw("Your clipboard history, one shortcut away.", at: NSPoint(x: 86, y: 276), size: 34, weight: .semibold, color: text, width: 500)
draw("Free and open source · macOS 12 or later", at: NSPoint(x: 86, y: 132), size: 24, weight: .medium, color: accent, width: 520)

// Right: the top of the clip window screenshot, with a shadow, cut by the bottom edge.
let shotWidth: CGFloat = 470
let shotHeight = shotWidth * shot.size.height / shot.size.width
let shotRect = NSRect(x: 690, y: 630 - 64 - shotHeight, width: shotWidth, height: shotHeight)
let shadow = NSShadow()
shadow.shadowColor = NSColor(red: 0.16, green: 0.12, blue: 0.47, alpha: 0.25)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.saveGraphicsState()
shadow.set()
let clip = NSBezierPath(roundedRect: shotRect, xRadius: 18, yRadius: 18)
NSColor.white.setFill()
clip.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
clip.addClip()
shot.draw(in: shotRect)
NSGraphicsContext.restoreGraphicsState()
NSColor(white: 0, alpha: 0.08).setStroke()
clip.lineWidth = 1.5
clip.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("wrote \(args[3])")
