// Draws the DMG window background with the install steps.
// Usage: swift scripts/release/make-dmg-background.swift <out-dir>
// Writes dmg-background.png (1x) and dmg-background@2x.png (2x).
// build-dmg.sh joins them into assets/dmg-background.tiff.
//
// The layout must match the create-dmg options in build-dmg.sh:
// icons 96 pt at (150, 140) and (450, 140). The window is 600x500, so the
// 440 pt image fits under the title bar and the Finder path bar.
import AppKit

let size = NSSize(width: 600, height: 440)
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let steps: [(String, String)] = [
    ("1", "Drag MaClip to the Applications folder."),
    ("2", "Open MaClip. If macOS shows \u{201C}MaClip.app\u{201D} Not Opened, click Done."),
    ("3", "Open System Settings \u{2192} Privacy & Security. Scroll down to \u{201C}MaClip.app was blocked\u{201D} and click Open Anyway. Confirm with your password."),
]

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    rep.size = size  // points, so Finder shows the 2x image at 600x440
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    // Flip to a top-left origin so the coordinates read like the Finder window.
    ctx.cgContext.translateBy(x: 0, y: size.height)
    ctx.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)

    NSColor(white: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    // Arrow from the app icon to the Applications icon.
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 230, y: 140))
    arrow.line(to: NSPoint(x: 366, y: 140))
    arrow.move(to: NSPoint(x: 354, y: 130))
    arrow.line(to: NSPoint(x: 368, y: 140))
    arrow.line(to: NSPoint(x: 354, y: 150))
    NSColor(white: 0.55, alpha: 1).setStroke()
    arrow.stroke()

    // Instruction panel below the icons.
    let panel = NSRect(x: 30, y: 226, width: 540, height: 198)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: panel, xRadius: 10, yRadius: 10).fill()
    NSColor(white: 0.85, alpha: 1).setStroke()
    NSBezierPath(roundedRect: panel.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()

    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
        .foregroundColor: NSColor(white: 0.1, alpha: 1),
    ]
    NSAttributedString(string: "How to install", attributes: title)
        .draw(at: NSPoint(x: panel.minX + 20, y: panel.minY + 14))

    let para = NSMutableParagraphStyle()
    para.lineSpacing = 2
    let body: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12.5),
        .foregroundColor: NSColor(white: 0.15, alpha: 1),
        .paragraphStyle: para,
    ]
    let number: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12.5, weight: .bold),
        .foregroundColor: NSColor.systemBlue,
    ]
    var y = panel.minY + 44
    for (n, text) in steps {
        NSAttributedString(string: n + ".", attributes: number).draw(at: NSPoint(x: panel.minX + 20, y: y))
        let box = NSRect(x: panel.minX + 40, y: y, width: panel.width - 60, height: 60)
        let s = NSAttributedString(string: text, attributes: body)
        s.draw(with: box, options: [.usesLineFragmentOrigin])
        y += ceil(s.boundingRect(with: box.size, options: [.usesLineFragmentOrigin]).height) + 12
    }

    let hint: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11.5),
        .foregroundColor: NSColor(white: 0.4, alpha: 1),
    ]
    let code: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
        .foregroundColor: NSColor(white: 0.2, alpha: 1),
    ]
    NSAttributedString(string: "Or, after step 1, run this in Terminal instead of steps 2 and 3:", attributes: hint)
        .draw(at: NSPoint(x: panel.minX + 20, y: y + 2))
    NSAttributedString(string: "xattr -dr com.apple.quarantine /Applications/MaClip.app", attributes: code)
        .draw(at: NSPoint(x: panel.minX + 20, y: y + 20))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (scale, name) in [(1.0, "dmg-background.png"), (2.0, "dmg-background@2x.png")] {
    try! render(scale: scale).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("wrote \(outDir)/dmg-background.png and @2x")
