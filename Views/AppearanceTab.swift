import SwiftUI
import AppKit

/// Settings → Appearance: the theme, the accent color, and a preview of both.
struct AppearanceTab: View {
    @ObservedObject var settings: AppSettings
    let applyTheme: (AppTheme) -> Void
    @ObservedObject private var accentStore = AccentStore.shared
    @State private var previewView: AppearancePreviewView = .clipWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Theme and color") {
                SettingsRow(title: "Theme") {
                    Picker("Theme", selection: $settings.theme) {
                        Text("System").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .settingsFocus("theme", choice: $settings.theme, values: [AppTheme.system, .light, .dark])
                    .onChange(of: settings.theme) { newTheme in
                        applyTheme(newTheme)
                        NotificationCenter.default.post(name: .themeChanged, object: nil)
                    }
                }
                SettingsRow(title: "Accent color", caption: accentStore.choice.caption) {
                    AccentSwatches(settings: settings)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("Preview", selection: $previewView) {
                        ForEach(AppearancePreviewView.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .settingsFocus("previewView", choice: $previewView, values: AppearancePreviewView.allCases)
                }
                AppearancePreview(view: previewView)
                    .frame(height: 340)
                    .colorScheme(settings.theme.colorScheme)
                Text(previewNote)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var previewNote: String {
        switch settings.theme {
        case .system: return "The preview uses the theme of your Mac. Warnings stay orange with every color."
        case .light, .dark: return "The preview uses the \(settings.theme.rawValue) theme. Warnings stay orange with every color."
        }
    }
}

private extension View {
    /// A fixed color scheme, or the scheme of the window for nil.
    @ViewBuilder
    func colorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme { environment(\.colorScheme, scheme) } else { self }
    }
}

// MARK: - Swatches

/// The 10 presets and the custom color. ← → in Settings step through them, and space on
/// Custom opens the picker.
private struct AccentSwatches: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var accentStore = AccentStore.shared
    @State private var showsPicker = false

    private var saved: AccentChoice { AccentChoice(stored: settings.accentColor) }
    /// The color the picker starts with: the custom color in use, else the newest one.
    private var lastCustom: String {
        if case .custom(let hex) = saved { return hex }
        return settings.recentAccentColors.first ?? "#2BB673"
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentPreset.allCases, id: \.self) { preset in
                Swatch(fill: Color(nsColor: NSColor(hex: preset.hex)), isSelected: saved == .preset(preset),
                       dot: AccentColor.usesWhiteText(on: preset.hex) ? .white : .black.opacity(0.8)) {
                    settings.accentColor = preset.rawValue
                }
                .help(preset.title)
                .accessibilityLabel(preset.title)
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 18).padding(.horizontal, 2)
            customSwatch
        }
        .settingsFocus("accent") { action in
            switch action {
            case .step(let step):
                select(saved.stepped(by: step, lastCustom: lastCustom))
            case .activate:
                if saved.isCustom { showsPicker = true } else { select(saved.stepped(by: 1, lastCustom: lastCustom)) }
            case .remove:
                break
            }
        }
    }

    private var customSwatch: some View {
        let isCustom = saved.isCustom
        return Button {
            if !isCustom { settings.accentColor = lastCustom }
            showsPicker = true
        } label: {
            ZStack {
                if isCustom {
                    Circle().fill(Color(nsColor: NSColor(hex: saved.hex)))
                    Circle().fill(AccentColor.usesWhiteText(on: saved.hex) ? Color.white : Color.black.opacity(0.8))
                        .frame(width: 8, height: 8)
                } else {
                    Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                                                  center: .center))
                    Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 14, height: 14)
                    Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Color.primary.opacity(isCustom ? 0.9 : 0), lineWidth: 2).padding(-4))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Custom color")
        .accessibilityLabel("Custom color")
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            CustomColorPicker(start: lastCustom, recent: settings.recentAccentColors) { hex in
                settings.accentColor = hex
                settings.recentAccentColors = AccentColor.addRecent(hex, to: settings.recentAccentColors)
            } onClose: {
                showsPicker = false
            }
        }
    }

    private func select(_ choice: AccentChoice) {
        settings.accentColor = choice.stored
    }
}

private struct Swatch: View {
    let fill: Color
    let isSelected: Bool
    let dot: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay { if isSelected { Circle().fill(dot).frame(width: 8, height: 8) } }
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2).padding(-4))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Color picker

/// The custom color popover. The app shows the color under the knob at once. Done or ↩ keeps
/// it, and Cancel or esc goes back to the color before the picker opened.
private struct CustomColorPicker: View {
    let recent: [String]
    let onKeep: (String) -> Void
    let onClose: () -> Void

    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var hexText: String
    @State private var focus: PickerFocus = .field
    @State private var keyMonitor: Any?
    @State private var window: NSWindow?
    @State private var finished = false
    @FocusState private var isHexFocused: Bool

    enum PickerFocus: CaseIterable { case field, hue, hex, eyedropper }

    init(start: String, recent: [String], onKeep: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.recent = recent
        self.onKeep = onKeep
        self.onClose = onClose
        let hsv = AccentColor.hsv(start)
        _hue = State(initialValue: hsv.hue)
        _saturation = State(initialValue: hsv.saturation)
        _brightness = State(initialValue: hsv.brightness)
        _hexText = State(initialValue: start)
    }

    private var hex: String { AccentColor.hex(hue: hue, saturation: saturation, brightness: brightness) }
    private var color: Color { Color(nsColor: NSColor(hex: hex)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom color").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("The app changes as you pick").font(.system(size: 11)).foregroundColor(.secondary)
            }
            colorField
            hueSlider
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                HStack(spacing: 6) {
                    Text("Hex").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("Hex", text: $hexText, onCommit: { applyHex(); keep() })
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .focused($isHexFocused)
                        .onChange(of: hexText) { _ in applyHex() }
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(color, lineWidth: 1))
                .ring(focus == .hex)
                Button(action: pickFromScreen) {
                    Image(systemName: "eyedropper").frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.tileFill))
                .help("Pick a color from the screen")
                .accessibilityLabel("Pick a color from the screen")
                .ring(focus == .eyedropper)
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.system(size: 11)).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(recent, id: \.self) { recentHex in
                            Button { set(recentHex) } label: {
                                Circle().fill(Color(nsColor: NSColor(hex: recentHex))).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(recentHex)
                            .accessibilityLabel(recentHex)
                        }
                    }
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 8) {
                Text("esc cancels \u{00B7} \u{21A9} keeps").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button("Cancel", action: cancel)
                Button("Done", action: keep).buttonStyle(AccentButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 268)
        .background(WindowReader(window: $window))
        .onAppear {
            AccentStore.shared.showPreview(.custom(hex))
            installKeyMonitor()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            // A click outside the popover closes it. That keeps the color, like a macOS color well.
            if !finished { onKeep(hex) }
            AccentStore.shared.endPreview()
        }
        .onChange(of: hex) { newHex in
            AccentStore.shared.showPreview(.custom(newHex))
            if !isHexFocused { hexText = newHex }
        }
        .onChange(of: focus) { newFocus in isHexFocused = newFocus == .hex }
    }

    private var colorField: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color(hue: hue / 360, saturation: 1, brightness: 1))
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .position(x: saturation * geo.size.width, y: (1 - brightness) * geo.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                focus = .field
                saturation = min(max(value.location.x / geo.size.width, 0), 1)
                brightness = 1 - min(max(value.location.y / geo.size.height, 0), 1)
            })
        }
        .frame(height: 150)
        .ring(focus == .field)
        .accessibilityElement()
        .accessibilityLabel("Saturation and brightness")
        .accessibilityValue("Saturation \(Int(saturation * 100)) percent, brightness \(Int(brightness * 100)) percent")
    }

    private var hueSlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(
                    colors: stride(from: 0.0, through: 360, by: 60).map { Color(hue: $0 / 360, saturation: 1, brightness: 1) },
                    startPoint: .leading, endPoint: .trailing))
                Circle()
                    .fill(Color(hue: hue / 360, saturation: 1, brightness: 1))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(x: hue / 360 * geo.size.width - 8)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                focus = .hue
                hue = min(max(value.location.x / geo.size.width, 0), 1) * 360
            })
        }
        .frame(height: 12)
        .ring(focus == .hue)
        .accessibilityElement()
        .accessibilityLabel("Hue")
        .accessibilityValue("\(Int(hue)) degrees")
    }

    private func set(_ newHex: String) {
        let hsv = AccentColor.hsv(newHex)
        hue = hsv.hue
        saturation = hsv.saturation
        brightness = hsv.brightness
        hexText = newHex
    }

    private func applyHex() {
        guard let parsed = AccentColor.normalizedHex(hexText), parsed != hex else { return }
        let hsv = AccentColor.hsv(parsed)
        hue = hsv.hue
        saturation = hsv.saturation
        brightness = hsv.brightness
    }

    private func pickFromScreen() {
        NSColorSampler().show { picked in
            guard let picked else { return }
            set(picked.hexString)
        }
    }

    private func keep() {
        finished = true
        onKeep(hex)
        onClose()
    }

    private func cancel() {
        finished = true
        onClose()
    }

    /// ⇥ moves between the color field, the hue slider, the hex field and the eyedropper.
    /// The arrow keys move the knob: 1% a step, 10% with ⇧. ↩ keeps the color, esc cancels.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window, event.window === window, let combo = KeyCombo(event: event) else { return event }
            let big = combo.modifiers.contains(.shift)
            switch combo.key {
            case .escape:
                cancel()
            case .tab:
                let all = PickerFocus.allCases
                let index = all.firstIndex(of: focus) ?? 0
                focus = all[(index + (big ? all.count - 1 : 1)) % all.count]
            case .returnKey:
                if focus == .eyedropper { pickFromScreen() } else { applyHex(); keep() }
            case .space where focus == .eyedropper:
                pickFromScreen()
            case .left, .right, .up, .down where focus == .field || focus == .hue:
                let step = big ? 0.1 : 0.01
                if focus == .hue {
                    let sign: Double = combo.key == .left || combo.key == .down ? -1 : 1
                    hue = min(max(hue + sign * step * 360, 0), 360)
                } else if combo.key == .left || combo.key == .right {
                    saturation = min(max(saturation + (combo.key == .left ? -step : step), 0), 1)
                } else {
                    brightness = min(max(brightness + (combo.key == .down ? -step : step), 0), 1)
                }
            default:
                return event
            }
            return nil
        }
    }
}

private extension View {
    /// The 2 pt focus ring of Settings.
    func ring(_ isOn: Bool) -> some View {
        overlay {
            if isOn {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Reads the window of the view, so a key monitor takes only its own keys.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if window !== nsView.window { window = nsView.window } }
    }
}

// MARK: - Preview

enum AppearancePreviewView: CaseIterable {
    case clipWindow, preview, controls, shortcuts

    var title: String {
        switch self {
        case .clipWindow: return "Clip window"
        case .preview: return "Preview"
        case .controls: return "Controls"
        case .shortcuts: return "Shortcuts"
        }
    }
}

/// A preview that draws the real MaClip views in the chosen theme and accent color. It takes no clicks.
private struct AppearancePreview: View {
    let view: AppearancePreviewView
    @ObservedObject private var accentStore = AccentStore.shared

    var body: some View {
        Group {
            switch view {
            case .clipWindow: ClipWindowSample()
            case .preview: PreviewSample()
            case .controls: ControlsSample()
            case .shortcuts:
                ShortcutsCard(title: "Preview", columns: ClipKeyMap.previewColumns(),
                              note: "Every clip key of the list works here too.") {}
                    .scaleEffect(0.82)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(view.title) with this theme and accent color")
    }
}

private enum Samples {
    static let text = ClipboardItem(date: Date(), content: .text("Release checklist for 2.1.0: build the DMG, then publish"))
    static let link = ClipboardItem(date: Date().addingTimeInterval(-120),
                                    content: .url(URL(string: "https://github.com/jokot/mac-clipboard")!))
    static let code = ClipboardItem(date: Date().addingTimeInterval(-840),
                                    content: .text("const total = items.reduce((sum, i) => sum + i.price, 0)"))
    static let concealed = ClipboardItem(date: Date().addingTimeInterval(-30), content: .text("hunter2-secret"),
                                         isConcealed: true, concealedExpiresAt: Date().addingTimeInterval(272))
}

private struct SampleWindow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

private struct ClipWindowSample: View {
    @ObservedObject private var accentStore = AccentStore.shared

    var body: some View {
        SampleWindow {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    Text("Search").foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fieldFill))
                .padding(10)
                VStack(spacing: 2) {
                    row(Samples.text, selected: true)
                    row(Samples.link)
                    row(Samples.code)
                    row(Samples.concealed)
                }
                .padding(.horizontal, 6)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    hint("\u{2191}\u{2193}", "Move")
                    hint("\u{21A9}", "Paste")
                    hint("space", "Preview")
                    HStack(spacing: 5) {
                        Text("\u{2318}/")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accentText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.selectedFill))
                        Text("Shortcuts")
                    }
                    Spacer()
                    Text("24 of 50 clips")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }

    private func row(_ item: ClipboardItem, selected: Bool = false) -> some View {
        ClipboardItemRow(item: item, onSelect: { _ in }, onRemove: {}, isSelected: selected,
                         onEdit: { _ in }, onPreview: { _ in })
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) { KeyLabel(key: key); Text(label) }
    }
}

private struct PreviewSample: View {
    @ObservedObject private var accentStore = AccentStore.shared

    var body: some View {
        HStack(spacing: 10) {
            SampleWindow {
                VStack(spacing: 2) {
                    ClipboardItemRow(item: Samples.text, onSelect: { _ in }, onRemove: {}, isSelected: true, isListFocused: false)
                    ClipboardItemRow(item: Samples.link, onSelect: { _ in }, onRemove: {})
                    Spacer(minLength: 0)
                }
                .padding(6)
            }
            .frame(width: 230)
            SampleWindow {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        KeyLabel(key: "\u{2190}")
                        Text("List")
                        Spacer()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accentText)
                    .padding(12)
                    Text("Release checklist for 2.1.0\n1. Build the DMG.\n2. Test the install window.\n3. Publish the release notes.")
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button("Edit\u{2026}") {}
                        Spacer()
                        Button("Paste") {}.buttonStyle(AccentButtonStyle())
                    }
                    .padding(12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2))
            }
        }
    }
}

private struct ControlsSample: View {
    @ObservedObject private var accentStore = AccentStore.shared

    var body: some View {
        SampleWindow {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSection(title: "Pasting") {
                    SettingsRow(title: "Paste on selection") {
                        SettingsSwitch(label: "Paste on selection", isOn: .constant(true))
                    }
                    SettingsRow(title: "Close when idle") {
                        SettingsSwitch(label: "Close when idle", isOn: .constant(false))
                    }
                }
                SettingsSection(title: "History") {
                    SettingsRow(title: "Keep up to", caption: "Apply deletes the 14 oldest clips. You cannot undo this.",
                                captionIsWarning: true) {
                        HStack(spacing: 6) {
                            Text("30")
                                .frame(width: 44, height: 22, alignment: .trailing)
                                .padding(.trailing, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.accent, lineWidth: 1.5))
                            Button("Apply") {}.buttonStyle(AccentButtonStyle())
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}
