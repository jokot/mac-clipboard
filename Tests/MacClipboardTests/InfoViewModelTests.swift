import XCTest
@testable import MaClip

final class InfoViewModelTests: XCTestCase {
    @MainActor
    func testGetAppNameAndVersionNonEmpty() {
        let vm = InfoViewModel()
        XCTAssertFalse(vm.getAppName().isEmpty)
        XCTAssertFalse(vm.getAppVersion().isEmpty)
    }
}