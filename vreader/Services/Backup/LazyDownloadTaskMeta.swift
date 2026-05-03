// Purpose: Codable Sendable payload encoded into URLSessionDownloadTask.taskDescription
// so the (fingerprintKey, blobPath, expectedSHA256, expectedByteCount, originalExtension)
// identity survives crash + relaunch + OS upgrades. Feature #47 WI-3a.
//
// Forward compat: `schemaVersion: Int` lets future versions add fields as
// optional/defaultable. Decoder accepts schemaVersion 1+; mismatch is treated
// as orphaned task (cancel + flip row to .failed).
//
// @coordinates-with: LazyDownloadCoordinator.swift, LazyDownloadDelegate.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation

struct LazyDownloadTaskMeta: Codable, Sendable, Equatable {
    /// Bumped when the JSON shape changes incompatibly. Decoder rejects
    /// unknown versions so a v1 client doesn't try to interpret a v2
    /// taskDescription it doesn't understand.
    let schemaVersion: Int

    /// Canonical fingerprint key of the book being downloaded.
    let fingerprintKey: String

    /// Server-side blob path on the WebDAV backup server.
    let blobPath: String

    /// Expected SHA-256 hex of the downloaded bytes; verified before import.
    let expectedSHA256: String

    /// Expected byte count of the downloaded bytes; verified before import.
    let expectedByteCount: Int64

    /// Original file extension at import time (preserves "mobi" for AZW3).
    let originalExtension: String

    /// Current schema version. Bump when the JSON shape changes.
    static let currentSchemaVersion = 1

    init(
        fingerprintKey: String,
        blobPath: String,
        expectedSHA256: String,
        expectedByteCount: Int64,
        originalExtension: String,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.fingerprintKey = fingerprintKey
        self.blobPath = blobPath
        self.expectedSHA256 = expectedSHA256
        self.expectedByteCount = expectedByteCount
        self.originalExtension = originalExtension
    }

    /// Encode self as a JSON string suitable for `URLSessionTask.taskDescription`.
    func encodeAsTaskDescription() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    /// Decode from a `URLSessionTask.taskDescription`. Returns nil if the
    /// description is missing, malformed, or carries an unrecognized
    /// schemaVersion (treated as an orphaned task by the coordinator).
    static func decode(fromTaskDescription description: String?) -> LazyDownloadTaskMeta? {
        guard let description, let data = description.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let meta = try? decoder.decode(LazyDownloadTaskMeta.self, from: data) else {
            return nil
        }
        // Refuse versions we don't understand. Future v2 clients will
        // accept v1; v1 won't accept v2. Reject 0/negative — those can
        // only be a corrupt/malicious description.
        guard (1...currentSchemaVersion).contains(meta.schemaVersion) else { return nil }
        // Validate SHA-256 hex (64 hex chars) and extension shape so a
        // corrupt taskDescription can't produce a path-traversing or
        // hidden-file staged URL downstream.
        let sha = meta.expectedSHA256
        guard sha.count == 64,
              sha.allSatisfy({ $0.isHexDigit }) else { return nil }
        let ext = meta.originalExtension
        guard !ext.isEmpty,
              ext.count <= 8,
              ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        guard meta.expectedByteCount >= 0 else { return nil }
        return meta
    }
}
