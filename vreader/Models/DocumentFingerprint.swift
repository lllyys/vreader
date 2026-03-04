// Purpose: Content-based document identity. SHA-256 over imported bytes + size + format.
// Used as the canonical deduplication key across the library.
//
// Key decisions:
// - Codable for SwiftData storage as JSON in transformable columns.
// - Hashable for use as dictionary keys and Set membership.
// - Sendable for cross-actor transfer (Swift 6 strict concurrency).
// - `canonicalKey` provides a primitive String for SwiftData @Attribute(.unique)
//   since SwiftData/CloudKit cannot enforce uniqueness on custom Codable structs.
// - SHA-256 hex string is validated at init to prevent invalid fingerprints.

/// Content-based identity for an imported document.
struct DocumentFingerprint: Codable, Hashable, Sendable {
    /// SHA-256 hex digest over the exact imported bytes.
    let contentSHA256: String

    /// Size of the imported file in bytes.
    let fileByteCount: Int64

    /// Format of the document.
    let format: BookFormat

    /// Primitive key suitable for SwiftData @Attribute(.unique).
    /// Format: "{format}:{contentSHA256}:{fileByteCount}"
    var canonicalKey: String {
        "\(format.rawValue):\(contentSHA256):\(fileByteCount)"
    }

    /// Whether the SHA-256 hex string is valid (64 lowercase hex characters).
    static func isValidSHA256(_ hex: String) -> Bool {
        hex.count == 64 && hex.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Creates a validated fingerprint. Returns nil if SHA-256 format is invalid.
    static func validated(
        contentSHA256: String,
        fileByteCount: Int64,
        format: BookFormat
    ) -> DocumentFingerprint? {
        guard isValidSHA256(contentSHA256), fileByteCount >= 0 else { return nil }
        return DocumentFingerprint(
            contentSHA256: contentSHA256,
            fileByteCount: fileByteCount,
            format: format
        )
    }
}
