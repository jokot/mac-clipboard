import Cocoa
import ApplicationServices

/// "Paste on selection" sends Command+V to another app. macOS allows that only
/// with Accessibility access. MaClip never asks at launch. It asks the first
/// time that it must paste for the user.
@MainActor
final class AccessibilityAccess: ObservableObject {
    static let shared = AccessibilityAccess()

    @Published private(set) var isGranted: Bool

    private let isTrusted: () -> Bool
    private let defaults: UserDefaults
    private let currentBuild: String
    private var askedThisLaunch = false

    private static let grantedBuildKey = "accessibility.lastGrantedBuild"

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         defaults: UserDefaults = AppEnvironment.defaults,
         currentBuild: String = AccessibilityAccess.bundleBuild()) {
        self.isTrusted = isTrusted
        self.defaults = defaults
        self.currentBuild = currentBuild
        self.isGranted = isTrusted()
        recordGrant()
    }

    /// True when an earlier build had access and this build does not. macOS keeps
    /// the old entry turned on, but the entry is for the old build. The user must
    /// remove the entry and add MaClip again.
    var needsRepair: Bool {
        guard !isGranted, let build = defaults.string(forKey: Self.grantedBuildKey) else { return false }
        return build != currentBuild
    }

    /// Reads the current state from macOS.
    func isGrantedNow() -> Bool {
        refresh()
        return isGranted
    }

    func refresh() {
        let granted = isTrusted()
        if granted != isGranted { isGranted = granted }
        recordGrant()
    }

    /// True one time in each launch while access is off. After "Not Now", MaClip
    /// does not ask again until the next launch.
    func shouldAskBeforePaste() -> Bool {
        refresh()
        guard !isGranted, !askedThisLaunch else { return false }
        askedThisLaunch = true
        return true
    }

    /// Shows the macOS dialog. Its "Open System Settings" button adds MaClip to the
    /// Accessibility list.
    func requestSystemPrompt() {
        let opts: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func recordGrant() {
        if isGranted { defaults.set(currentBuild, forKey: Self.grantedBuildKey) }
    }

    nonisolated static func bundleBuild() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
