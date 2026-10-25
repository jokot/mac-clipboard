import XCTest
@testable import MaClip

@MainActor
final class AccessibilityAccessTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "com.jokot.MacClipboard.tests.accessibility"
    private var trusted = false

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        trusted = false
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeAccess(build: String = "1.13.0 (20)") -> AccessibilityAccess {
        AccessibilityAccess(isTrusted: { [unowned self] in self.trusted }, defaults: defaults, currentBuild: build)
    }

    func test_asksOncePerLaunchWhenNotGranted() {
        let access = makeAccess()
        XCTAssertTrue(access.shouldAskBeforePaste())
        XCTAssertFalse(access.shouldAskBeforePaste(), "after Not Now, do not ask again in this launch")
        XCTAssertTrue(makeAccess().shouldAskBeforePaste(), "a new launch asks again")
    }

    func test_doesNotAskWhenGranted() {
        trusted = true
        XCTAssertFalse(makeAccess().shouldAskBeforePaste())
    }

    func test_refreshFollowsTheSystemState() {
        let access = makeAccess()
        XCTAssertFalse(access.isGranted)
        trusted = true
        access.refresh()
        XCTAssertTrue(access.isGranted)
    }

    func test_needsRepairAfterAnUpdateLosesAccess() {
        trusted = true
        makeAccess(build: "1.12.1 (19)").refresh()

        trusted = false
        let updated = makeAccess(build: "1.13.0 (20)")
        XCTAssertTrue(updated.needsRepair)
    }

    func test_noRepairOnFirstInstall() {
        XCTAssertFalse(makeAccess().needsRepair)
    }

    func test_noRepairWhenTheSameBuildLosesAccess() {
        trusted = true
        makeAccess().refresh()
        trusted = false
        XCTAssertFalse(makeAccess().needsRepair, "the user turned it off, so ask in the normal way")
    }

    func test_noRepairWhenGranted() {
        trusted = true
        makeAccess(build: "1.12.1 (19)").refresh()
        XCTAssertFalse(makeAccess(build: "1.13.0 (20)").needsRepair)
    }
}
