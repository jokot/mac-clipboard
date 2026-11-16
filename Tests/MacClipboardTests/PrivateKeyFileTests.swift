import XCTest
@testable import MaClip

final class PrivateKeyFileTests: XCTestCase {
    func test_theKeyFileHasPermission600() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PrivateKeyFile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("id_ed25519")
        let block = "-----" + "BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----" + "END OPENSSH PRIVATE KEY-----"

        try PrivateKeyFile.write(block, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try String(contentsOf: url), block + "\n")
    }

    func test_replacingAFileKeepsPermission600() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PrivateKeyFile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("id_rsa")
        try Data("old".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        try PrivateKeyFile.write("new\n", to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try String(contentsOf: url), "new\n")
    }
}
