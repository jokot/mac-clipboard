import Foundation

/// Where MaClip keeps its persistent data.
///
/// Unit tests run hosted inside the real app, so without this they read and
/// delete the user's real history and settings. Under XCTest every location
/// points at a throwaway folder and defaults suite instead.
enum AppEnvironment {
    static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
    }()

    static let testDefaultsSuiteName = "com.jokot.MacClipboard.tests"

    /// `UserDefaults.standard`, or an emptied private suite under XCTest.
    static let defaults: UserDefaults = {
        guard isRunningTests, let suite = UserDefaults(suiteName: testDefaultsSuiteName) else {
            return .standard
        }
        suite.removePersistentDomain(forName: testDefaultsSuiteName)
        return suite
    }()

    /// `~/Library/Application Support/MaClip`, or a per-process temp folder
    /// under XCTest. Callers create the folder on demand.
    static let appSupportDirectory: URL? = {
        let fm = FileManager.default
        if isRunningTests {
            return fm.temporaryDirectory.appendingPathComponent(
                "MaClipTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MaClip", isDirectory: true)
    }()
}
