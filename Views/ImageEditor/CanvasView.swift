import SwiftUI

struct CanvasView: View {
    @ObservedObject var viewModel: ImageEditorViewModel
    @Binding var tool: EditTool
    @Binding var stroke: StrokeStyle
    @Binding var fontSize: CGFloat

    @State private var draftStart: CGPoint? = nil
    @State private var draftCurrent: CGPoint? = nil
    @State private var draftPenPoints: [CGPoint] = []
    @State private var textDraftOrigin: CGPoint? = nil
    @State private var textDraftString: String = ""

    var body: some View {
        GeometryReader { geo in
            let imgSize = viewModel.state.baseImage.size
            let display = fitRect(image: imgSize, container: geo.size)
            let scale = display.width / imgSize.width

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.08)

                Canvas { ctx, _ in
                    var transform = CGAffineTransform(translationX: display.minX, y: display.minY)
                    transform = transform.scaledBy(x: scale, y: scale)
                    ctx.transform = transform

                    if let cg = viewModel.state.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        ctx.draw(Image(decorative: cg, scale: 1.0), in: CGRect(origin: .zero, size: imgSize))
                    }
                    for layer in viewModel.state.layers {
                        drawLayer(layer, in: &ctx)
                    }
                    if let start = draftStart, let cur = draftCurrent {
                        drawDraft(from: start, to: cur, in: &ctx)
                    }
                    if !draftPenPoints.isEmpty {
                        drawDraft(pen: draftPenPoints, in: &ctx)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(display: display, scale: scale))

                if let origin = textDraftOrigin {
                    let screenPt = CGPoint(x: origin.x * scale + display.minX,
                                           y: origin.y * scale + display.minY)
                    TextField("Text", text: $textDraftString, onCommit: { commitTextDraft() })
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .position(x: screenPt.x + 100, y: screenPt.y)
                }
            }
        }
    }

    private func dragGesture(display: CGRect, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = imageCoord(value.location, display: display, scale: scale)
                switch tool {
                case .pen:
                    if draftPenPoints.isEmpty { draftPenPoints = [p] }
                    else { draftPenPoints.append(p) }
                case .text:
                    break
                default:
                    if draftStart == nil { draftStart = p }
                    draftCurrent = p
                }
            }
            .onEnded { value in
                let p = imageCoord(value.location, display: display, scale: scale)
                switch tool {
                case .crop:
                    if let start = draftStart {
                        let rect = normalized(start, p)
                        if rect.width > 1 && rect.height > 1 {
                            viewModel.mutate { $0.cropRect = rect }
                        }
                    }
                case .arrow:
                    if let start = draftStart {
                        viewModel.mutate { $0.layers.append(.arrow(from: start, to: p, style: stroke)) }
                    }
                case .rectangle:
                    if let start = draftStart {
                        viewModel.mutate { $0.layers.append(.rectangle(frame: normalized(start, p), style: stroke)) }
                    }
                case .oval:
                    if let start = draftStart {
                        viewModel.mutate { $0.layers.append(.oval(frame: normalized(start, p), style: stroke)) }
                    }
                case .redact:
                    if let start = draftStart {
                        viewModel.mutate { $0.layers.append(.redact(frame: normalized(start, p))) }
                    }
                case .pen:
                    let pts = draftPenPoints
                    if pts.count > 1 {
                        viewModel.mutate { $0.layers.append(.pen(points: pts, style: stroke)) }
                    }
                case .text:
                    textDraftOrigin = p
                    textDraftString = ""
                }
                draftStart = nil
                draftCurrent = nil
                draftPenPoints = []
            }
    }

    private func commitTextDraft() {
        guard let origin = textDraftOrigin, !textDraftString.isEmpty else {
            textDraftOrigin = nil
            return
        }
        let str = textDraftString
        viewModel.mutate {
            $0.layers.append(.text(origin: origin, string: str, color: stroke.color, fontSize: fontSize))
        }
        textDraftOrigin = nil
        textDraftString = ""
    }

    private func fitRect(image: CGSize, container: CGSize) -> CGRect {
        let scale = min(container.width / image.width, container.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func imageCoord(_ screen: CGPoint, display: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: (screen.x - display.minX) / scale, y: (screen.y - display.minY) / scale)
    }

    private func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func drawLayer(_ layer: EditLayer, in ctx: inout GraphicsContext) {
        switch layer {
        case .arrow(let from, let to, let style):
            var p = Path(); p.move(to: from); p.addLine(to: to)
            ctx.stroke(p, with: .color(style.color), lineWidth: style.width)
            drawArrowhead(from: from, to: to, style: style, in: &ctx)
        case .rectangle(let frame, let style):
            ctx.stroke(Path(frame), with: .color(style.color), lineWidth: style.width)
        case .oval(let frame, let style):
            ctx.stroke(Path(ellipseIn: frame), with: .color(style.color), lineWidth: style.width)
        case .text(let origin, let string, let color, let fontSize):
            ctx.draw(Text(string).font(.system(size: fontSize)).foregroundColor(color), at: origin, anchor: .topLeading)
        case .pen(let points, let style):
            guard points.count > 1 else { return }
            var p = Path(); p.move(to: points[0])
            for pt in points.dropFirst() { p.addLine(to: pt) }
            ctx.stroke(p, with: .color(style.color),
                       style: .init(lineWidth: style.width, lineCap: .round, lineJoin: .round))
        case .redact(let frame):
            ctx.fill(Path(frame), with: .color(.black))
        }
    }

    private func drawArrowhead(from: CGPoint, to: CGPoint, style: StrokeStyle, in ctx: inout GraphicsContext) {
        let dx = to.x - from.x, dy = to.y - from.y
        let angle = atan2(dy, dx)
        let headLen = max(6, style.width * 4)
        let left = CGPoint(x: to.x + cos(angle + .pi - .pi / 6) * headLen,
                           y: to.y + sin(angle + .pi - .pi / 6) * headLen)
        let right = CGPoint(x: to.x + cos(angle + .pi + .pi / 6) * headLen,
                            y: to.y + sin(angle + .pi + .pi / 6) * headLen)
        var p = Path()
        p.move(to: to); p.addLine(to: left)
        p.move(to: to); p.addLine(to: right)
        ctx.stroke(p, with: .color(style.color), lineWidth: style.width)
    }

    private func drawDraft(from: CGPoint, to: CGPoint, in ctx: inout GraphicsContext) {
        switch tool {
        case .arrow:      drawLayer(.arrow(from: from, to: to, style: stroke), in: &ctx)
        case .rectangle:  drawLayer(.rectangle(frame: normalized(from, to), style: stroke), in: &ctx)
        case .oval:       drawLayer(.oval(frame: normalized(from, to), style: stroke), in: &ctx)
        case .redact:     drawLayer(.redact(frame: normalized(from, to)), in: &ctx)
        case .crop:
            let p = Path(normalized(from, to))
            ctx.stroke(p, with: .color(.accentColor), style: .init(lineWidth: 1, dash: [4, 4]))
        default: break
        }
    }

    private func drawDraft(pen points: [CGPoint], in ctx: inout GraphicsContext) {
        guard points.count > 1 else { return }
        var p = Path(); p.move(to: points[0])
        for pt in points.dropFirst() { p.addLine(to: pt) }
        ctx.stroke(p, with: .color(stroke.color),
                   style: .init(lineWidth: stroke.width, lineCap: .round))
    }
}
