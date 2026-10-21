import SwiftUI

struct CanvasView: View {
    @ObservedObject var viewModel: ImageEditorViewModel
    @Binding var tool: EditTool
    @Binding var stroke: StrokeStyle
    @Binding var fontSize: CGFloat

    @State private var draftStart: CGPoint? = nil
    @State private var draftCurrent: CGPoint? = nil
    @State private var draftPenPoints: [CGPoint] = []
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let imgSize = viewModel.state.baseImage.size
            // The crop tool shows the whole image so the crop can be changed.
            let showsCrop = tool != .crop
            let g = CanvasGeometry(imageSize: imgSize,
                                   cropRect: showsCrop ? viewModel.state.cropRect : nil,
                                   quarterTurns: viewModel.state.rotationQuarterTurns,
                                   container: geo.size)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.08)

                Canvas { ctx, _ in
                    ctx.clip(to: Path(g.display))
                    ctx.transform = g.transform

                    if let cg = viewModel.state.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        ctx.draw(Image(decorative: cg, scale: 1.0), in: CGRect(origin: .zero, size: imgSize))
                    }
                    for layer in viewModel.state.layers {
                        drawLayer(layer, in: &ctx)
                    }
                    if !showsCrop, let crop = viewModel.state.cropRect {
                        drawCropOutline(crop, imageSize: imgSize, scale: g.scale, in: &ctx)
                    }
                    if let start = draftStart, let cur = draftCurrent {
                        drawDraft(from: start, to: cur, in: &ctx)
                    }
                    if !draftPenPoints.isEmpty {
                        drawDraft(pen: draftPenPoints, in: &ctx)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(geometry: g, imageSize: imgSize))

                if let draft = viewModel.textDraft {
                    let screenPt = g.toView(draft.origin)
                    TextField("Text", text: Binding(get: { viewModel.textDraft?.string ?? "" },
                                                    set: { viewModel.textDraft?.string = $0 }),
                              onCommit: { commitTextDraft() })
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($textFieldFocused)
                        .onExitCommand { viewModel.cancelText() }
                        .position(x: screenPt.x + 100, y: screenPt.y)
                        // ponytail: without explicit focus the field shows but
                        // takes no keys; typed digits then change the color.
                        .onAppear { DispatchQueue.main.async { textFieldFocused = true } }
                }
            }
        }
        .onChange(of: tool) { _ in commitTextDraft() }
    }

    private func dragGesture(geometry g: CanvasGeometry, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = g.toBase(value.location)
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
                let p = g.toBase(value.location)
                switch tool {
                case .crop:
                    if let start = draftStart {
                        let rect = normalized(start, p).intersection(CGRect(origin: .zero, size: imageSize))
                        if !rect.isNull && rect.width > 1 && rect.height > 1 {
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
                    viewModel.beginText(at: p, color: stroke.color, fontSize: fontSize)
                }
                draftStart = nil
                draftCurrent = nil
                draftPenPoints = []
            }
    }

    private func commitTextDraft() {
        viewModel.commitText(color: stroke.color, fontSize: fontSize)
    }

    /// Crop tool: dim what the crop removes and outline what it keeps.
    private func drawCropOutline(_ crop: CGRect, imageSize: CGSize, scale: CGFloat, in ctx: inout GraphicsContext) {
        var outside = Path(CGRect(origin: .zero, size: imageSize))
        outside.addRect(crop)
        ctx.fill(outside, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        ctx.stroke(Path(crop), with: .color(.accentColor),
                   style: .init(lineWidth: 2 / max(scale, 0.0001), dash: [6 / max(scale, 0.0001)]))
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

/// Maps between base-image space, where layers and the crop are stored, and the
/// canvas view. Same order as ImageCompositor: crop, then rotate, then fit.
struct CanvasGeometry {
    let display: CGRect
    let scale: CGFloat
    let transform: CGAffineTransform

    init(imageSize: CGSize, cropRect: CGRect?, quarterTurns: Int, container: CGSize) {
        let content = cropRect ?? CGRect(origin: .zero, size: imageSize)
        let turns = ((quarterTurns % 4) + 4) % 4
        let rotated = turns % 2 == 0 ? content.size : CGSize(width: content.height, height: content.width)
        let fit = min(container.width / max(rotated.width, 1), container.height / max(rotated.height, 1))
        let scale = max(fit, 0.0001)
        let w = rotated.width * scale, h = rotated.height * scale
        let display = CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)

        // y-down space: a positive angle turns clockwise, like the compositor.
        var t = CGAffineTransform(translationX: display.minX, y: display.minY)
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: rotated.width / 2, y: rotated.height / 2)
        t = t.rotated(by: CGFloat(turns) * .pi / 2)
        t = t.translatedBy(x: -content.width / 2, y: -content.height / 2)
        t = t.translatedBy(x: -content.minX, y: -content.minY)

        self.display = display
        self.scale = scale
        self.transform = t
    }

    func toView(_ p: CGPoint) -> CGPoint { p.applying(transform) }
    func toBase(_ p: CGPoint) -> CGPoint { p.applying(transform.inverted()) }
}
