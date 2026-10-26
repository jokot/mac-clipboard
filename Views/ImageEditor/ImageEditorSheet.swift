import SwiftUI
import AppKit

struct ImageEditorSheet: View {
    enum SaveMode { case inPlace, asNew }

    let item: ClipboardItem
    let baseImage: NSImage
    /// Returns false when the image could not be saved. The editor then stays open.
    let onCommit: (Data, SaveMode) -> Bool
    let onCancel: () -> Void

    @StateObject private var vm: ImageEditorViewModel
    @State private var tool: EditTool = .arrow
    @State private var stroke = StrokeStyle(color: .red, width: 4)
    @State private var fontSize: CGFloat = 24
    @State private var keyMonitor: Any?
    @State private var saveFailed = false

    private static let colorPresets: [Color] =
        [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
    private static let colorNames = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Black", "White"]
    private static let widths: [CGFloat] = [1, 2, 4, 6, 8, 12]

    init(item: ClipboardItem, baseImage: NSImage,
         onCommit: @escaping (Data, SaveMode) -> Bool,
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
                .padding(.horizontal, 12)
                .frame(height: 48)
            Rectangle().fill(Theme.line).frame(height: 1)
            CanvasView(viewModel: vm, tool: $tool, stroke: $stroke, fontSize: $fontSize)
                .background(Color.black.opacity(0.25))
            Rectangle().fill(Theme.line).frame(height: 1)
            statusBar
        }
        .frame(minWidth: 940, minHeight: 600)
        .alert("Could not save image", isPresented: $saveFailed) {
            Button("OK") {}
        } message: {
            Text("MaClip could not write the edited image. Make sure that the disk has free space, then try again. Your edits are still open.")
        }
        .shortcutsPanel(.imageEditor, title: "Image editor",
                        note: "Drawing, crop and text placement need the pointer. Tool keys are off while you type text.") {
            EditorKeyMap.columns()
        }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            ShortcutsPanelState.shared.hide(.imageEditor)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ToolbarIconButton(label: "Rotate Left (\u{2318}L)", systemImage: "rotate.left") { rotate(by: -1) }
                ToolbarIconButton(label: "Rotate Right (\u{2318}R)", systemImage: "rotate.right") { rotate(by: 1) }
            }

            separator

            HStack(spacing: 2) {
                ForEach(EditTool.allCases, id: \.self) { t in
                    ToolbarIconButton(label: "\(t.title) (\(t.key.uppercased()))", systemImage: symbol(for: t), isSelected: tool == t) {
                        tool = t
                    }
                }
            }

            separator

            HStack(spacing: 6) {
                ForEach(Array(Self.colorPresets.enumerated()), id: \.offset) { index, c in
                    let isSelected = stroke.color == c
                    Button { stroke.color = c } label: {
                        Circle().fill(c)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                            .padding(2)
                            .overlay(Circle().stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help("\(Self.colorNames[index]) (\(index + 1))")
                    .accessibilityLabel(Self.colorNames[index])
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Picker("Line width", selection: $stroke.width) {
                ForEach(Self.widths, id: \.self) { w in
                    Text("\(Int(w)) pt").tag(w)
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("Line width")

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                ToolbarIconButton(label: "Undo (\u{2318}Z)", systemImage: "arrow.uturn.backward") { vm.undo() }
                    .disabled(!vm.canUndo)
                ToolbarIconButton(label: "Redo (\u{21E7}\u{2318}Z)", systemImage: "arrow.uturn.forward") { vm.redo() }
                    .disabled(!vm.canRedo)
            }

            // ponytail: fixedSize + layoutPriority so the packed left cluster
            // can't squeeze the action buttons to ellipsis / zero width.
            // The key monitor runs ↩, ⌘S, ⇧⌘S and Esc. While text is typed, ↩ and Esc belong to the text field.
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .help("Cancel (esc)")
                Button("Save as New") { commit(.asNew) }
                    .disabled(!canSave)
                    .help("Save as a new clip (\u{21E7}\u{2318}S)")
                Button("Save") { commit(.inPlace) }
                    .buttonStyle(AccentButtonStyle())
                    .opacity(canSave ? 1 : 0.45)
                    .disabled(!canSave)
                    .help("Save (\u{21A9} or \u{2318}S)")
            }
            .fixedSize()
            .layoutPriority(1)
        }
    }

    private var separator: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 22)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(EditorStatus.hint(for: tool))
            Spacer()
            Text(EditorStatus.editsText(for: vm.state))
            Text(EditorStatus.sizeText(for: baseImage))
            Button { ShortcutsPanelState.shared.toggle(.imageEditor) } label: {
                HStack(spacing: 5) {
                    KeyLabel(key: "\u{2318}/")
                    Text("Shortcuts")
                }
            }
            .buttonStyle(.plain)
            .help("Keyboard Shortcuts (\u{2318}/)")
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
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

    private var canSave: Bool { vm.state.isDirty || vm.hasPendingText }

    private func rotate(by quarterTurns: Int) {
        vm.mutate { $0.rotationQuarterTurns = (($0.rotationQuarterTurns + quarterTurns) % 4 + 4) % 4 }
    }

    /// The next line width in `widths`, thinner or thicker. A width not in the list moves to the nearest one.
    private func stepWidth(_ step: Int) {
        let nearest = Self.widths.enumerated().min { abs($0.element - stroke.width) < abs($1.element - stroke.width) }?.offset ?? 0
        let index = min(max(0, nearest + step), Self.widths.count - 1)
        stroke.width = Self.widths[index]
    }

    private func perform(_ command: EditorCommand) {
        switch command {
        case .tool(let t): tool = t
        case .color(let n): stroke.color = Self.colorPresets[n - 1]
        case .thinner: stepWidth(-1)
        case .thicker: stepWidth(1)
        case .rotateLeft: rotate(by: -1)
        case .rotateRight: rotate(by: 1)
        case .undo: vm.undo()
        case .redo: vm.redo()
        case .save: if canSave { commit(.inPlace) } else { NSSound.beep() }
        case .saveAsNew: if canSave { commit(.asNew) } else { NSSound.beep() }
        case .cancel: onCancel()
        case .showShortcuts: ShortcutsPanelState.shared.toggle(.imageEditor)
        }
    }

    private func commit(_ mode: SaveMode) {
        vm.commitText(color: stroke.color, fontSize: fontSize)
        guard let data = ImageCompositor.compose(vm.state), onCommit(data, mode) else {
            saveFailed = true
            return
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors see keys for every MaClip window. Only take keys in the editor.
            guard event.window?.identifier == ImageEditorWindowController.windowIdentifier,
                  let combo = KeyCombo(event: event) else { return event }
            let panel = ShortcutsPanelState.shared
            if panel.isVisible(.imageEditor) {
                if combo == KeyCombo(.escape) || combo == .command("/") { panel.hide(.imageEditor) }
                return nil
            }
            if combo == KeyCombo(.escape), vm.isDrawing {  // Esc mid-drag cancels only the shape
                vm.cancelDrawing()
                return nil
            }
            guard let command = EditorKeyMap.table.command(for: combo) else { return event }
            // The text tool's field takes letters, digits, ↩ and Esc. Only ⌘S, ⇧⌘S and ⌘/ still work.
            if event.window?.firstResponder is NSTextView {
                let worksWhileTyping: Set<EditorCommand> = [.save, .saveAsNew, .showShortcuts]
                guard combo.modifiers.contains(.command), worksWhileTyping.contains(command) else { return event }
            }
            perform(command)
            return nil
        }
    }
}

/// A 32 × 30 pt icon button of the editor toolbar. A selected tool has the accent fill.
private struct ToolbarIconButton: View {
    @ObservedObject private var accentStore = AccentStore.shared
    let label: String
    let systemImage: String
    var isSelected: Bool = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .secondary))
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.accent : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The text of the editor status bar.
enum EditorStatus {
    static func hint(for tool: EditTool) -> String {
        switch tool {
        case .crop: return "Crop: drag a box on the image."
        case .arrow: return "Arrow: drag on the image. Esc cancels the shape."
        case .rectangle: return "Rectangle: drag on the image. Esc cancels the shape."
        case .oval: return "Oval: drag on the image. Esc cancels the shape."
        case .text: return "Text: click on the image, then type. Return adds the text."
        case .pen: return "Pen: drag to draw. Esc cancels the line."
        case .redact: return "Redact: drag a black box over private text."
        }
    }

    static func editsText(for state: ImageEditState) -> String {
        let count = state.layers.count + (state.cropRect == nil ? 0 : 1) + (state.rotationQuarterTurns == 0 ? 0 : 1)
        switch count {
        case 0: return "No edits"
        case 1: return "1 edit"
        default: return "\(count) edits"
        }
    }

    /// The size in pixels, not points.
    static func sizeText(for image: NSImage) -> String {
        let rep = image.representations.first
        let width = rep?.pixelsWide ?? Int(image.size.width)
        let height = rep?.pixelsHigh ?? Int(image.size.height)
        return "\(width) \u{00D7} \(height) px"
    }
}
