import SwiftUI
import AppKit

struct ImageEditorSheet: View {
    enum SaveMode { case inPlace, asNew }

    let item: ClipboardItem
    let baseImage: NSImage
    let onCommit: (Data, SaveMode) -> Void
    let onCancel: () -> Void

    @StateObject private var vm: ImageEditorViewModel
    @State private var tool: EditTool = .arrow
    @State private var stroke = StrokeStyle(color: .red, width: 4)
    @State private var fontSize: CGFloat = 24
    @State private var keyMonitor: Any?

    private static let colorPresets: [Color] =
        [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    init(item: ClipboardItem, baseImage: NSImage,
         onCommit: @escaping (Data, SaveMode) -> Void,
         onCancel: @escaping () -> Void) {
        self.item = item
        self.baseImage = baseImage
        self.onCommit = onCommit
        self.onCancel = onCancel
        _vm = StateObject(wrappedValue: ImageEditorViewModel(base: baseImage))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(8)
                .background(.ultraThinMaterial)
            Divider()
            CanvasView(viewModel: vm, tool: $tool, stroke: $stroke, fontSize: $fontSize)
        }
        .frame(minWidth: 940, minHeight: 600)
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { vm.mutate { $0.rotationQuarterTurns = (($0.rotationQuarterTurns - 1) % 4 + 4) % 4 } }
                label: { Image(systemName: "arrow.counterclockwise") }
            Button { vm.mutate { $0.rotationQuarterTurns = ($0.rotationQuarterTurns + 1) % 4 } }
                label: { Image(systemName: "arrow.clockwise") }

            Divider().frame(height: 24)

            ForEach(EditTool.allCases, id: \.self) { t in
                Button { tool = t } label: {
                    Image(systemName: symbol(for: t))
                        .foregroundColor(tool == t ? .accentColor : .primary)
                }
            }

            Divider().frame(height: 24)

            HStack(spacing: 4) {
                ForEach(Array(Self.colorPresets.enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(stroke.color == c ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2))
                        .onTapGesture { stroke.color = c }
                }
            }

            Slider(value: Binding(get: { Double(stroke.width) },
                                  set: { stroke.width = CGFloat($0) }),
                   in: 1...12, step: 1)
                .frame(width: 80)

            Divider().frame(height: 24)

            Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!vm.canUndo)
                .keyboardShortcut("z", modifiers: .command)

            Button { vm.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!vm.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])

            Spacer(minLength: 8)

            // ponytail: fixedSize + layoutPriority so the packed left cluster
            // can't squeeze the action buttons to ellipsis / zero width.
            // While text is typed, Return and Esc belong to the text field.
            let typing = vm.textDraft != nil
            let canSave = vm.state.isDirty || vm.hasPendingText
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction, enabled: !typing)
                Button("Save as new") { commit(.asNew) }.disabled(!canSave)
                Button("Save") { commit(.inPlace) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction, enabled: !typing)
            }
            .fixedSize()
            .layoutPriority(1)
        }
    }

    private func symbol(for tool: EditTool) -> String {
        switch tool {
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .text: return "textformat"
        case .pen: return "pencil.tip"
        case .redact: return "square.fill"
        }
    }

    private func commit(_ mode: SaveMode) {
        vm.commitText(color: stroke.color, fontSize: fontSize)
        guard let data = ImageCompositor.compose(vm.state) else { return }
        onCommit(data, mode)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors see keys for every MaClip window. Only take 1-8 in
            // the editor, and not while the text tool's field is being typed in.
            guard event.window?.identifier == ImageEditorWindowController.windowIdentifier,
                  !(event.window?.firstResponder is NSTextView) else { return event }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
               let chars = event.charactersIgnoringModifiers,
               let n = Int(chars), (1...8).contains(n) {
                stroke.color = Self.colorPresets[n - 1]
                return nil
            }
            return event
        }
    }
}

private extension View {
    @ViewBuilder
    func keyboardShortcut(_ shortcut: KeyboardShortcut, enabled: Bool) -> some View {
        if enabled { keyboardShortcut(shortcut) } else { self }
    }
}
