import Foundation

/// Saves a private key for "Save as File…". Only the owner can read the file (permission 600).
enum PrivateKeyFile {
    static func write(_ keyBlock: String, to url: URL) throws {
        let text = keyBlock.hasSuffix("\n") ? keyBlock : keyBlock + "\n"
        let fm = FileManager.default
        // Write a new file with permission 600 next to the target, then move it into place,
        // so the key is never in a file that other users can read.
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: temp.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        do {
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: url)
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}
