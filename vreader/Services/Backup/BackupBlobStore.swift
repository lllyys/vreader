// Purpose: Transport-neutral blob-store contract used by feature #46's
// BookFileMaterializer (read side) and WebDAVProvider blob upload path
// (write side). WebDAV is the only impl today; future iCloud / S3 / etc.
// providers conform without touching the materializer.
//
// Split read/write so the materializer (read-only on restore) doesn't
// import write capabilities by accident.
//
// @coordinates-with: WebDAVClient.swift (conforms),
//   BookFileMaterializer.swift (consumes read side, future WI-5),
//   WebDAVProvider.swift (drives write side, future WI-7),
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Foundation

// MARK: - Read side

/// Used by BookFileMaterializer at restore time. Only needs to check whether
/// a blob exists and download it.
protocol BackupBlobReading: Sendable {
    /// Returns the blob's byte count, or nil if no resource exists at `path`.
    /// Implemented as PROPFIND Depth: 0 on the WebDAV side; HEAD is unreliable
    /// across WebDAV servers.
    func existsWithSize(at path: String) async throws -> Int64?

    /// Downloads the full blob bytes at `path`.
    func download(from path: String) async throws -> Data
}

// MARK: - Write side

/// Used by WebDAVProvider at backup time to publish content-addressed blobs
/// atomically.
protocol BackupBlobWriting: Sendable {
    /// Publishes `data` atomically at `path`. The implementation guarantees the
    /// blob is either fully present or absent — never partially written.
    ///
    /// Idempotent: if a blob with matching `expectedByteCount` already exists
    /// at `path`, the implementation may skip the upload and return
    /// `.alreadyExists`. Content-addressed paths (`<sha256>_<bytes>.<ext>`)
    /// guarantee identical bytes have already converged at the destination.
    ///
    /// On WebDAV: PUT to `uploads/tmp/<uuid>.part` → PROPFIND-verify size →
    /// MOVE to `path`. May throw `BackupBlobStoreError.serverCapabilityMissing`
    /// if the server doesn't support MOVE (e.g., 501 Not Implemented).
    func putBlobAtomically(
        _ data: Data,
        to path: String,
        expectedByteCount: Int64
    ) async throws -> BlobPutResult
}

/// Result of `putBlobAtomically`. Distinguishes "we wrote bytes" from "the
/// destination already had matching bytes." Backup progress UI uses this to
/// report dedupe efficiency to the user.
enum BlobPutResult: Sendable, Equatable {
    case uploaded
    case alreadyExists
}

// MARK: - Errors

/// Errors specific to the blob-store layer. Keeps WebDAV-specific
/// `WebDAVError` from leaking into the materializer / backup orchestrator.
enum BackupBlobStoreError: Error, Sendable, Equatable {
    /// The server doesn't support a required capability (e.g., MOVE for
    /// atomic publication). Carries the missing capability name for the UI.
    case serverCapabilityMissing(String)

    /// After PUT, PROPFIND reported a different byte count than expected —
    /// the upload was truncated or corrupted in transit.
    case sizeAfterPutMismatch(expected: Int64, actual: Int64)

    /// Wraps an underlying transport error. Stringly-typed (not the raw
    /// WebDAVError) so consumers don't depend on transport internals.
    case underlying(String)
}
