import XCTest
@testable import MaClip

final class TextPreviewTests: XCTestCase {
    func testPreviewTruncatesLongText() {
        let long = String(repeating: "abc ", count: 100)
        let preview = TextPreview.preview(for: long)
        XCTAssertTrue(preview.count <= 301) // 300 chars + ellipsis
        XCTAssertTrue(preview.hasSuffix("…"))
    }
}