import Foundation
import Combine

@MainActor
final class InfoViewModel: ObservableObject {
    @Published var isCheckingUpdate = false
    @Published var updateAlert: UpdateAlert?
    @Published var lastChecked: Date?
    
    private let updateService = UpdateService.shared
    private var autoCheckStarted = false
    
    struct UpdateAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let releaseNotes: String?
        let url: URL?
    }
    
    init() {
        // hydrate last checked
        lastChecked = updateService.getLastChecked()
        startAutoCheckIfNeeded()
    }
    
    deinit {
        // service manages its own timer lifecycle
    }
    
    // MARK: - Public Methods
    
    func checkForUpdates() {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        
        Task {
            do {
                let result = try await updateService.checkForUpdates()
                
                // Update local lastChecked to reflect persisted timestamp
                lastChecked = updateService.getLastChecked()
                
                if result.hasUpdate, let latest = result.latestVersion, let url = result.releaseURL {
                    updateAlert = UpdateAlert(
                        title: "Update Available",
                        message: "A new version (\(latest)) is available.",
                        releaseNotes: result.releaseNotes,
                        url: url
                    )
                } else {
                    updateAlert = UpdateAlert(
                        title: "You're up to date",
                        message: "You're running the latest version (\(getAppShortVersion())).",
                        releaseNotes: nil,
                        url: nil
                    )
                }
            } catch {
                updateAlert = UpdateAlert(
                    title: "Update Check Failed",
                    message: error.localizedDescription,
                    releaseNotes: nil,
                    url: nil
                )
            }
            isCheckingUpdate = false
        }
    }
    
    func getAppVersion() -> String {
        return updateService.getFullVersion()
    }
    
    func getAppName() -> String {
        return updateService.getAppName()
    }
    
    func getFormattedLastChecked() -> String {
        return updateService.getFormattedLastChecked()
    }
    
    // MARK: - Private Methods
    
    private func getAppShortVersion() -> String {
        return updateService.getCurrentVersion()
    }
    
    private func startAutoCheckIfNeeded() {
        guard !autoCheckStarted else { return }
        autoCheckStarted = true
        updateService.startAutoCheck(initialDelay: 30, interval: 24 * 60 * 60)
    }
}