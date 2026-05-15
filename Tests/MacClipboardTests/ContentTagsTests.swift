import XCTest
@testable import MaClip

@MainActor
final class ContentTagsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ContentTagDetector.clearCache()
    }

    private func text(_ s: String) -> ClipboardItem {
        ClipboardItem(date: Date(), content: .text(s))
    }

    func test_urlText() {
        let tags = ContentTagDetector.tags(for: text("https://example.com"))
        XCTAssertTrue(tags.contains(.url))
    }

    func test_email() {
        let tags = ContentTagDetector.tags(for: text("foo@bar.com"))
        XCTAssertTrue(tags.contains(.email))
    }

    func test_phone() {
        let tags = ContentTagDetector.tags(for: text("+1 (555) 555-5555"))
        XCTAssertTrue(tags.contains(.phone))
    }

    func test_jsonObject() {
        let tags = ContentTagDetector.tags(for: text("{\"a\":1}"))
        XCTAssertTrue(tags.contains(.json))
        XCTAssertFalse(tags.contains(.code))
    }

    func test_jsonArray() {
        let tags = ContentTagDetector.tags(for: text("[1, 2, 3]"))
        XCTAssertTrue(tags.contains(.json))
    }

    func test_multiLineCode() {
        let src = """
        func foo() {
            return 1
        }
        """
        let tags = ContentTagDetector.tags(for: text(src))
        XCTAssertTrue(tags.contains(.code))
    }

    func test_hexColor() {
        let tags = ContentTagDetector.tags(for: text("#FF00AA"))
        XCTAssertTrue(tags.contains(.color))
    }

    func test_inlineDiff() {
        let src = "+ added line\n- removed line"
        let tags = ContentTagDetector.tags(for: text(src))
        XCTAssertTrue(tags.contains(.diff))
    }

    func test_gitDiff() {
        let src = "diff --git a/foo b/foo\n--- a/foo\n+++ b/foo"
        let tags = ContentTagDetector.tags(for: text(src))
        XCTAssertTrue(tags.contains(.diff))
    }

    func test_plainTextHasNoTags() {
        let tags = ContentTagDetector.tags(for: text("hello world"))
        XCTAssertTrue(tags.isEmpty)
    }

    func test_cacheReturnsStableSet() {
        let item = text("https://example.com")
        let first = ContentTagDetector.tags(for: item)
        let second = ContentTagDetector.tags(for: item)
        XCTAssertEqual(first, second)
    }

    func test_urlItemAlwaysTaggedURL() {
        let item = ClipboardItem(date: Date(), content: .url(URL(string: "https://example.com")!))
        let tags = ContentTagDetector.tags(for: item)
        XCTAssertEqual(tags, [.url])
    }

    func test_imageItemHasNoTags() {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        let content = ImageContent(source: .memory(img), cachedText: nil, cachedId: nil, cachedBarcode: nil)
        let item = ClipboardItem(date: Date(), content: .image(content))
        XCTAssertTrue(ContentTagDetector.tags(for: item).isEmpty)
    }

    func test_emptyTextHasNoTags() {
        XCTAssertTrue(ContentTagDetector.tags(for: text("")).isEmpty)
        XCTAssertTrue(ContentTagDetector.tags(for: text("   \n")).isEmpty)
    }

    func test_jsonSuppressesCodeTag() {
        let tags = ContentTagDetector.tags(for: text("{ \"key\": \"value\" }"))
        XCTAssertTrue(tags.contains(.json))
        XCTAssertFalse(tags.contains(.code))
    }

    func test_clearCacheEmptiesIt() {
        _ = ContentTagDetector.tags(for: text("https://example.com"))
        ContentTagDetector.clearCache()
        let tags = ContentTagDetector.tags(for: text("https://example.com"))
        XCTAssertTrue(tags.contains(.url))
    }
}
