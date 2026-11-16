import XCTest
@testable import MaClip

final class JWTDecoderTests: XCTestCase {
    private let signature = String(repeating: "s", count: 20)
    private let us = Locale(identifier: "en_US")
    private let now = Date(timeIntervalSince1970: 1_794_700_000)

    private func part(_ object: [String: Any], padded: Bool = false) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var s = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        if !padded { s = s.replacingOccurrences(of: "=", with: "") }
        return s
    }

    private func token(_ header: [String: Any], _ payload: [String: Any], padded: Bool = false) -> String {
        part(header, padded: padded) + "." + part(payload, padded: padded) + "." + signature
    }

    func test_readsTheClaims() throws {
        let jwt = try XCTUnwrap(JWTDecoder.decode(token(["alg": "HS256", "typ": "JWT"],
            ["iss": "https://auth.example.com", "sub": "user_1", "aud": "api", "iat": 1_794_600_000,
             "exp": 1_794_700_100, "nbf": 1_794_600_000])))
        XCTAssertEqual(jwt.algorithm, "HS256")
        XCTAssertEqual(jwt.type, "JWT")
        XCTAssertEqual(jwt.issuer, "https://auth.example.com")
        XCTAssertEqual(jwt.subject, "user_1")
        XCTAssertEqual(jwt.audience, ["api"])
        XCTAssertEqual(jwt.issuedAt, Date(timeIntervalSince1970: 1_794_600_000))
        XCTAssertEqual(jwt.expiresAt, Date(timeIntervalSince1970: 1_794_700_100))
        XCTAssertEqual(jwt.notBefore, Date(timeIntervalSince1970: 1_794_600_000))
        XCTAssertFalse(jwt.isUnsigned)
        XCTAssertEqual(jwt.headerJSON, "{\n  \"alg\" : \"HS256\",\n  \"typ\" : \"JWT\"\n}")
    }

    func test_audienceCanBeAList() {
        XCTAssertEqual(JWTDecoder.decode(token(["alg": "RS256"], ["aud": ["a", "b"]]))?.audience, ["a", "b"])
    }

    func test_dateClaimsCanBeDecimals() {
        XCTAssertEqual(JWTDecoder.decode(token(["alg": "RS256"], ["exp": 1_794_700_000.5]))?.expiresAt,
                       Date(timeIntervalSince1970: 1_794_700_000.5))
    }

    func test_paddingIsOptional() {
        let header: [String: Any] = ["alg": "HS256"]
        let payload: [String: Any] = ["sub": "ab"]
        XCTAssertEqual(JWTDecoder.decode(token(header, payload, padded: true)), JWTDecoder.decode(token(header, payload)))
        XCTAssertNotNil(JWTDecoder.decode(token(header, payload, padded: true)))
    }

    func test_findsTheTokenInOtherText() {
        XCTAssertEqual(JWTDecoder.decode("Authorization: Bearer " + token(["alg": "HS256"], ["sub": "x"]) + "\n")?.subject, "x")
    }

    func test_algNoneIsUnsigned() {
        XCTAssertEqual(JWTDecoder.decode(token(["alg": "None"], ["sub": "x"]))?.isUnsigned, true)
    }

    func test_statusText() throws {
        func status(_ payload: [String: Any]) throws -> JWTStatus {
            try XCTUnwrap(JWTDecoder.decode(token(["alg": "HS256"], payload))).status(now: now)
        }
        let expired = try status(["exp": now.timeIntervalSince1970 - 3 * 86_400])
        XCTAssertEqual(expired.text(now: now, locale: us), "Expired 3 days ago")
        XCTAssertTrue(expired.isWarning)

        let valid = try status(["exp": now.timeIntervalSince1970 + 2 * 3_600])
        XCTAssertEqual(valid.text(now: now, locale: us), "Expires in 2 hours")
        XCTAssertFalse(valid.isWarning)

        let early = try status(["nbf": now.timeIntervalSince1970 + 86_400, "exp": now.timeIntervalSince1970 - 10])
        XCTAssertEqual(early, .notYetValid(now.addingTimeInterval(86_400)))
        XCTAssertTrue(early.text(now: now, locale: us).hasPrefix("Not valid until Nov"))
        XCTAssertTrue(early.isWarning)

        XCTAssertEqual(try status(["sub": "x"]).text(now: now, locale: us), "No expiry date")
    }

    func test_theSignatureIsNeverInTheOutput() throws {
        let jwt = try XCTUnwrap(JWTDecoder.decode(token(["alg": "HS256"], ["sub": "x"])))
        XCTAssertFalse(jwt.headerJSON.contains(signature))
        XCTAssertFalse(jwt.payloadJSON.contains(signature))
    }

    func test_badInputIsNil() {
        XCTAssertNil(JWTDecoder.decode("eyJ" + "notjson!!" + ".eyJ" + "zdWIiOiIxMjM0In0" + "." + signature))
        XCTAssertNil(JWTDecoder.decode("no token here"))
    }

    func test_dateText() {
        let text = JWTDecoder.dateText(Date(timeIntervalSince1970: 1_794_700_000), locale: us, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(text.hasPrefix("Nov"), text)
        XCTAssertTrue(text.contains("2026"), text)
    }
}
