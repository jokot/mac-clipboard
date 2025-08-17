import XCTest
@testable import MaClip

final class URLUtilsTests: XCTestCase {
    func testExactHTTPSURLPasses() {
        let input = "https://example.com/path"
        let url = URLUtils.linkURL(from: input)
        XCTAssertEqual(url?.absoluteString, "https://example.com/path")
    }

    func testTrailingPunctuationIsStripped() {
        let input = "https://example.com)."
        let url = URLUtils.linkURL(from: input)
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testAngleBracketedURLPasses() {
        let input = "<https://example.com/a?b=1>"
        let url = URLUtils.linkURL(from: input)
        XCTAssertEqual(url?.absoluteString, "https://example.com/a?b=1")
    }

    func testQuotedURLPasses() {
        let input = "\"https://example.com\""
        let url = URLUtils.linkURL(from: input)
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testBareDomainGetsHTTPSPrepended() {
        let input = "example.com"
        let url = URLUtils.linkURL(from: input)
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testBareDomainWithPathAndQueryGetsHTTPSPrepended() {
        let input = "www.example.co.uk/path?q=1#frag"
        let url = URLUtils.linkURL(from: input)
        XCTAssertEqual(url?.absoluteString, "https://www.example.co.uk/path?q=1#frag")
    }

    func testRejectsNonHttpSchemes() {
        let input = "ftp://example.com/file"
        let url = URLUtils.linkURL(from: input)
        XCTAssertNil(url)
    }

    func testRejectsLocalhostAndNonTLDHosts() {
        let input = "localhost:3000"
        let url = URLUtils.linkURL(from: input)
        XCTAssertNil(url)
    }

    func testRejectsEmbeddedURLNotAlone() {
        let input = "See https://example.com for details"
        let url = URLUtils.linkURL(from: input)
        XCTAssertNil(url)
    }
}