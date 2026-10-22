import SwiftUI

enum EditTool: String, CaseIterable {
    case crop, arrow, rectangle, oval, text, pen, redact
}

struct StrokeStyle: Equatable {
    var color: Color
    var width: CGFloat
}

enum EditLayer: Equatable {
    case arrow(from: CGPoint, to: CGPoint, style: StrokeStyle)
    case rectangle(frame: CGRect, style: StrokeStyle)
    case oval(frame: CGRect, style: StrokeStyle)
    case text(origin: CGPoint, string: String, color: Color, fontSize: CGFloat)
    case pen(points: [CGPoint], style: StrokeStyle)
    case redact(frame: CGRect)
}

struct ImageEditState {
    var baseImage: NSImage
    var layers: [EditLayer] = []
    var cropRect: CGRect? = nil
    var rotationQuarterTurns: Int = 0

    var isDirty: Bool {
        !layers.isEmpty || cropRect != nil || rotationQuarterTurns != 0
    }
}

extension ImageEditState: Equatable {
    static func == (lhs: ImageEditState, rhs: ImageEditState) -> Bool {
        // baseImage is invariant during a sheet session; compare mutable fields only.
        return lhs.layers == rhs.layers
            && lhs.cropRect == rhs.cropRect
            && lhs.rotationQuarterTurns == rhs.rotationQuarterTurns
    }
}
