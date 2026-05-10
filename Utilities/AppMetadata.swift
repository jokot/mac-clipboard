import Cocoa

/// Resolves bundle IDs to display names and icons, caching results.
@MainActor
final class AppMetadata {
    static let shared = AppMetadata()

    private struct Entry {
        let displayName: String?
        let icon: NSImage?
    }

    private var cache: [String: Entry] = [:]

    private init() {}

    func displayName(for bundleID: String) -> String? {
        return entry(for: bundleID).displayName
    }

    func icon(for bundleID: String) -> NSImage? {
        return entry(for: bundleID).icon
    }

    func isCached(bundleID: String) -> Bool {
        return cache[bundleID] != nil
    }

    func clearCache() {
        cache.removeAll()
    }

    private func entry(for bundleID: String) -> Entry {
        if let cached = cache[bundleID] { return cached }
        let resolved = resolve(bundleID: bundleID)
        cache[bundleID] = resolved
        return resolved
    }

    private func resolve(bundleID: String) -> Entry {
        let workspace = NSWorkspace.shared
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return Entry(displayName: nil, icon: nil)
        }
        let bundle = Bundle(url: appURL)
        let displayName = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = workspace.icon(forFile: appURL.path)
        return Entry(displayName: displayName, icon: icon)
    }
}
