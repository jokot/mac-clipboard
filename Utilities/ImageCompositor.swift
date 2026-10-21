import AppKit
import SwiftUI

enum ImageCompositor {
    static func compose(_ state: ImageEditState) -> Data? {
        let base = state.baseImage
        let baseSize = base.size
        let cropSource = state.cropRect ?? CGRect(origin: .zero, size: baseSize)

        let outSize: NSSize
        if state.rotationQuarterTurns % 2 == 0 {
            outSize = NSSize(width: cropSource.width, height: cropSource.height)
        } else {
            outSize = NSSize(width: cropSource.height, height: cropSource.width)
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outSize.width),
            pixelsHigh: Int(outSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outSize).fill()

        // ponytail: CanvasView records crop + layer geometry in SwiftUI space
        // (top-left origin, y down). Flip the bitmap context to match, or every
        // edit lands mirrored vertically in the saved PNG.
        let cg = ctx.cgContext
        cg.translateBy(x: 0, y: outSize.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

        cg.translateBy(x: outSize.width / 2, y: outSize.height / 2)
        // y-down space: a positive angle turns clockwise.
        cg.rotate(by: CGFloat(state.rotationQuarterTurns) * .pi / 2)
        cg.translateBy(x: -cropSource.width / 2, y: -cropSource.height / 2)
        cg.translateBy(x: -cropSource.origin.x, y: -cropSource.origin.y)

        base.draw(in: NSRect(origin: .zero, size: baseSize), from: .zero,
                  operation: .sourceOver, fraction: 1.0,
                  respectFlipped: true, hints: nil)

        for layer in state.layers {
            draw(layer: layer)
        }

        return rep.representation(using: .png, properties: [:])
    }

    private static func draw(layer: EditLayer) {
        switch layer {
        case .arrow(let from, let to, let style):
            NSColor(style.color).setStroke()
            let path = NSBezierPath()
            path.lineWidth = style.width
            path.lineCapStyle = .round
            path.move(to: from)
            path.line(to: to)
            path.stroke()
            let dx = to.x - from.x
            let dy = to.y - from.y
            let angle = atan2(dy, dx)
            let headLen = max(6, style.width * 4)
            let left = CGPoint(x: to.x + cos(angle + .pi - .pi / 6) * headLen,
                               y: to.y + sin(angle + .pi - .pi / 6) * headLen)
            let right = CGPoint(x: to.x + cos(angle + .pi + .pi / 6) * headLen,
                                y: to.y + sin(angle + .pi + .pi / 6) * headLen)
            let head = NSBezierPath()
            head.lineWidth = style.width
            head.lineCapStyle = .round
            head.move(to: to); head.line(to: left)
            head.move(to: to); head.line(to: right)
            head.stroke()

        case .rectangle(let frame, let style):
            NSColor(style.color).setStroke()
            let path = NSBezierPath(rect: frame)
            path.lineWidth = style.width
            path.stroke()

        case .oval(let frame, let style):
            NSColor(style.color).setStroke()
            let path = NSBezierPath(ovalIn: frame)
            path.lineWidth = style.width
            path.stroke()

        case .text(let origin, let string, let color, let fontSize):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(color)
            ]
            NSAttributedString(string: string, attributes: attrs).draw(at: origin)

        case .pen(let points, let style):
            guard points.count > 1 else { return }
            NSColor(style.color).setStroke()
            let path = NSBezierPath()
            path.lineWidth = style.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: points[0])
            for p in points.dropFirst() { path.line(to: p) }
            path.stroke()

        case .redact(let frame):
            NSColor.black.setFill()
            NSBezierPath(rect: frame).fill()
        }
    }
}
