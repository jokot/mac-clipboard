import XCTest
@testable import MaClip

final class AppEnvironmentTests: XCTestCase {

    func test_detectsTestRun() {
        XCTAssertTrue(AppEnvironment.isRunningTests)
    }

    func test_appSupportDirectoryIsNotRealUserData() throws {
        let dir = try XCTUnwrap(AppEnvironment.appSupportDirectory)
        let real = try XCTUnwrap(FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        XCTAssertFalse(dir.standardizedFileURL.path.hasPrefix(real.standardizedFileURL.path),
                       "tests must not use \(real.path)")
    }

    func test_defaultsAreNotStandard() {
        XCTAssertFalse(AppEnvironment.defaults === UserDefaults.standard)
        let key = "appEnvironmentTests.probe"
        AppEnvironment.defaults.set(true, forKey: key)
        defer { AppEnvironment.defaults.removeObject(forKey: key) }
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }
}
