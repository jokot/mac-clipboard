import XCTest
@testable import MaClip

final class AppMetadataTests: XCTestCase {

    @MainActor
    override func setUp() {
        super.setUp()
        AppMetadata.shared.clearCache()
    }

    @MainActor
    func test_displayNameForKnownAppReturnsNonNil() {
        let name = AppMetadata.shared.displayName(for: "com.apple.TextEdit")
        XCTAssertNotNil(name)
    }

    @MainActor
    func test_displayNameForUnknownAppReturnsNil() {
        let name = AppMetadata.shared.displayName(for: "com.example.does-not-exist-xyz")
        XCTAssertNil(name)
    }

    @MainActor
    func test_iconForKnownAppReturnsNonNil() {
        let icon = AppMetadata.shared.icon(for: "com.apple.TextEdit")
        XCTAssertNotNil(icon)
    }

    @MainActor
    func test_displayNameCachedOnSecondCall() {
        let bundleID = "com.apple.TextEdit"
        let first = AppMetadata.shared.displayName(for: bundleID)
        let second = AppMetadata.shared.displayName(for: bundleID)
        XCTAssertEqual(first, second)
        XCTAssertTrue(AppMetadata.shared.isCached(bundleID: bundleID))
    }
}
