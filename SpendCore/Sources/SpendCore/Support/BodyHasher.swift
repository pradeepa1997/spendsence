import CryptoKit
import Foundation

public enum BodyHasher {
    /// SHA-256 hex digest of the body with leading/trailing whitespace removed.
    public static func hash(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
