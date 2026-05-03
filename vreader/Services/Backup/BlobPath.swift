// Purpose: Maps (format, sha256, byteCount) ↔ WebDAV-safe blob path for
// feature #46's content-addressed library blob store.
//
// Path layout: VReader/books/<format>/<sha256>_<byteCount>.<canonical-ext>
//
// Why not the raw fingerprintKey ("epub:abc:1024"): colons are not safe
// across all WebDAV servers — Apache/mod_dav passes them through but some
// proxies, S3-style adapters, and Windows-backed shares mangle them. The
// blob path uses only [0-9a-f_./], leaves the canonical fingerprintKey
// inside the manifest where it's pure data.
//
// Per-format subdirectory ("books/<format>/") keeps directory listings
// bounded as the library grows — most WebDAV servers throttle enumeration
// over ~1000 entries, and sharding by 5 known formats buys headroom.
//
// originalExtension is intentionally NOT in the blob path — different source
// extensions (.mobi, .prc, .azw) for the same SHA-256 content collapse to
// the same blob (canonical .azw3 extension). The original extension travels
// in the library manifest, not the path.
//
// @coordinates-with: BackupBookProjection (PersistenceActor+Backup.swift),
//   BackupLibraryManifestEnvelope (BackupSectionDTOs.swift, future WI-2),
//   BookFileMaterializer (future WI-5),
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Foundation

enum BlobPath {

    /// Top-level directory for content-addressed book blobs on the WebDAV
    /// server. Pinned by `BlobPathTests.booksRootIsStable` — changing it
    /// invalidates every previously-uploaded backup.
    static let booksRoot = "VReader/books"

    /// Builds the blob path for a (format, sha256, byteCount) triple.
    ///
    /// Returns: `"VReader/books/<format>/<sha256>_<byteCount>.<canonical-ext>"`
    static func make(format: BookFormat, sha256: String, byteCount: Int64) -> String {
        let formatStr = format.rawValue
        let canonicalExt = format.fileExtensions.first ?? formatStr
        return "\(booksRoot)/\(formatStr)/\(sha256)_\(byteCount).\(canonicalExt)"
    }

    /// Parses a blob path back into its components.
    ///
    /// Returns nil if the path doesn't match the expected layout, the format
    /// segment is unknown, the SHA-256 isn't 64 hex chars, or the byte count
    /// isn't a non-negative integer.
    static func parse(_ path: String) -> (format: BookFormat, sha256: String, byteCount: Int64)? {
        // Expected: "VReader/books/<format>/<sha256>_<byteCount>.<ext>"
        let prefix = booksRoot + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let trail = String(path.dropFirst(prefix.count))

        let segments = trail.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 2 else { return nil }
        let formatSegment = String(segments[0])
        let filename = String(segments[1])

        guard let format = BookFormat(rawValue: formatSegment) else { return nil }

        // Strip extension; rest must be "<sha256>_<byteCount>".
        let nsFilename = filename as NSString
        let stem = nsFilename.deletingPathExtension
        guard !stem.isEmpty, stem != filename else { return nil }  // require an extension

        let parts = stem.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let sha = String(parts[0])
        let byteStr = String(parts[1])

        guard isValidSHA256Hex(sha), let bytes = Int64(byteStr), bytes >= 0 else { return nil }
        return (format: format, sha256: sha, byteCount: bytes)
    }

    // MARK: - Helpers

    private static func isValidSHA256Hex(_ s: String) -> Bool {
        guard s.count == 64 else { return false }
        return s.allSatisfy { $0.isHexDigit }
    }
}
