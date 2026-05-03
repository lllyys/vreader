// Purpose: 5-state enum describing whether a Book row's file bytes are
// available locally, remote-only, mid-download, failed, or known-missing on
// the remote. Persisted on Book as a raw String (matching the Book.format
// pattern); typed at the API surface.
//
// Key decisions:
// - Stored as raw String on @Model Book — SwiftData's enum encoding is
//   brittle; raw String matches existing patterns and migrations.
// - 5 distinct cases (not Bool) so the UI can show cloud icon, spinner,
//   retry, "removed from server" hint independently.
// - `isReadable` gates ReaderContainerView dispatch; `canDownload` gates
//   the Library tap / "retry" actions.
//
// @coordinates-with: Book.swift (raw String column),
//   LazyDownloadCoordinator.swift, ReaderContainerView.swift,
//   BookRowView.swift, dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation

/// File-presence state for a Book row in the library.
///
/// The Book row exists for every book the user has imported or restored.
/// `fileState` describes whether the bytes for that row are present
/// locally, on a remote backup server only, mid-transfer, or unrecoverable.
public enum BookFileState: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    /// Bytes are present at the sandbox URL; fingerprint was verified at import.
    case local

    /// Row exists, blob is on the WebDAV server, no local bytes.
    /// The row carries `blobPath` pointing at the server-side blob.
    case remoteOnly

    /// A background download is in flight via LazyDownloadCoordinator.
    case downloading

    /// The most recent download attempt failed. The user can retry.
    case failed

    /// The server confirmed it does not have the blob (404 or similar).
    /// The row stays for metadata, but the bytes can't be recovered from this server.
    case missingRemote

    /// True when the book can be opened in the reader without first downloading.
    public var isReadable: Bool {
        self == .local
    }

    /// True when the user can initiate (or retry) a download for this row.
    /// `.downloading` returns false because a transfer is already in flight;
    /// `.missingRemote` returns false because the server has confirmed there's nothing to fetch.
    public var canDownload: Bool {
        switch self {
        case .remoteOnly, .failed:
            return true
        case .local, .downloading, .missingRemote:
            return false
        }
    }
}
