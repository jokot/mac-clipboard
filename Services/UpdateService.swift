import Foundation

final class UpdateService {
    static let shared = UpdateService()
    static let lastCheckedDidChange = Notification.Name("UpdateServiceLastCheckedDidChange")
    
    private let userDefaults = UserDefaults.standard
    private let lastCheckedKey = "LastUpdateCheck"
    private var autoCheckTimer: Timer?
    
    struct UpdateInfo {
        let hasUpdate: Bool
        let currentVersion: String
        let latestVersion: String?
        let releaseURL: URL?
        let releaseNotes: String?
    }
    
    private struct LatestRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let published_at: String?
    }
    
    private init() {}
    
    deinit {
        stopAutoCheck()
    }
    
    // MARK: - Public API
    
    /// Check for updates manually
    func checkForUpdates() async throws -> UpdateInfo {
        let release = try await fetchLatestRelease()
        let latest = normalizeVersion(release.version)
        let current = normalizeVersion(getCurrentVersion())
        
        saveLastChecked()
        
        let hasUpdate = isVersion(latest, newerThan: current)
        let releaseNotes = hasUpdate ? formatReleaseNotes(release.releaseNotes) : nil
        
        return UpdateInfo(
            hasUpdate: hasUpdate,
            currentVersion: current,
            latestVersion: hasUpdate ? release.version : nil,
            releaseURL: hasUpdate ? release.url : nil,
            releaseNotes: releaseNotes
        )
    }
    
    /// Start automatic update checking
    func startAutoCheck(initialDelay: TimeInterval = 30, interval: TimeInterval = 24 * 60 * 60) {
        stopAutoCheck()
        
        // Check if we should auto-check
        let shouldAutoCheck: Bool
        if let lastCheck = getLastChecked() {
            shouldAutoCheck = Date().timeIntervalSince(lastCheck) > interval
        } else {
            shouldAutoCheck = true // Never checked before
        }
        
        if shouldAutoCheck {
            // Delay initial auto-check
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
                Task {
                    try? await self?.checkForUpdates()
                }
            }
        }
        
        // Schedule periodic checks
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                try? await self?.checkForUpdates()
            }
        }
    }
    
    /// Stop automatic update checking
    func stopAutoCheck() {
        autoCheckTimer?.invalidate()
        autoCheckTimer = nil
    }
    
    /// Get the last update check timestamp
    func getLastChecked() -> Date? {
        return userDefaults.object(forKey: lastCheckedKey) as? Date
    }
    
    /// Get formatted last checked string
    func getFormattedLastChecked() -> String {
        guard let lastChecked = getLastChecked() else { return "Never" }
        
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastChecked)
        
        // Less than 1 minute
        if timeInterval < 60 {
            return "recently"
        }
        
        // Minutes (1-59)
        let minutes = Int(timeInterval / 60)
        if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        
        // Hours (1-23)
        let hours = Int(timeInterval / 3600)
        if hours < 24 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        
        // Days
        let days = Int(timeInterval / 86400)
        if days == 1 {
            return "yesterday"
        } else if days < 7 {
            return "\(days) days ago"
        }
        
        // Weeks
        let weeks = days / 7
        if weeks < 4 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        }
        
        // Months (approximate)
        let months = days / 30
        if months < 12 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
        
        // Years
        let years = days / 365
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }
    
    /// Get current app version
    func getCurrentVersion() -> String {
        let dict = Bundle.main.infoDictionary
        return dict?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    /// Get current app version with build number
    func getFullVersion() -> String {
        let dict = Bundle.main.infoDictionary
        let short = dict?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = dict?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
    
    /// Get app name
    func getAppName() -> String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "MaClip"
    }
    
    // MARK: - Private Methods
    
    private func saveLastChecked() {
        userDefaults.set(Date(), forKey: lastCheckedKey)
        NotificationCenter.default.post(name: Self.lastCheckedDidChange, object: nil)
    }
    
    private func normalizeVersion(_ v: String) -> String {
        // Strip leading non-numeric chars like "v"
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = trimmed.firstIndex(where: { $0.isNumber }) {
            return String(trimmed[idx...])
        }
        return trimmed
    }
    
    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let count = max(aParts.count, bParts.count)
        for i in 0..<count {
            let ai = i < aParts.count ? aParts[i] : 0
            let bi = i < bParts.count ? bParts[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
    
    private func fetchLatestRelease() async throws -> (version: String, url: URL, releaseNotes: String?) {
        let url = URL(string: "https://api.github.com/repos/jokot/mac-clipboard/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("MaClip (macOS)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "UpdateError", code: http.statusCode, 
                         userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        
        let decoder = JSONDecoder()
        let rel = try decoder.decode(LatestRelease.self, from: data)
        
        guard let html = URL(string: rel.html_url) else {
            throw NSError(domain: "UpdateError", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid release URL"])
        }
        
        return (rel.tag_name, html, rel.body)
    }
    
    private func formatReleaseNotes(_ notes: String?) -> String? {
        guard let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        // Basic formatting: limit length and clean up markdown
        let cleanNotes = notes
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "•")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit to reasonable length for alert
        if cleanNotes.count > 300 {
            let index = cleanNotes.index(cleanNotes.startIndex, offsetBy: 297)
            return String(cleanNotes[..<index]) + "..."
        }
        
        return cleanNotes
    }
}