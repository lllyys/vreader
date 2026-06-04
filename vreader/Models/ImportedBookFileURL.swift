// Purpose: The SINGLE source of truth for an imported book's on-device sandbox
// file URL — Application Support/ImportedBooks/<fingerprintKey with ':' → '_'>.<ext>.
// Both `LibraryBookItem.resolvedFileURL` and the agentic closed-book text
// extractor (Feature #91) resolve through here, so the two can never drift to
// different paths (a drift = a "file not found" for a book that is really present).
//
// @coordinates-with: LibraryBookItem.swift (resolvedFileURL), BookImporter (the
//   import-time write convention), ClosedBookTextExtractor.swift / Feature #91.

import Foundation

enum ImportedBookFileURL {
    /// The sandbox URL for an imported book (PRIMARY extension), from its
    /// fingerprint key + format. Synchronous, no I/O — the historical
    /// `resolvedFileURL` contract.
    static func resolve(fingerprintKey: String, format: String) -> URL {
        let safeName = fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let ext = BookFormat(rawValue: format.lowercased())?.fileExtensions.first ?? format.lowercased()
        return importedBooksDirectory().appendingPathComponent(safeName).appendingPathExtension(ext)
    }

    /// Resolve to the file that ACTUALLY exists on disk, trying each of the
    /// format's candidate extensions (e.g. `txt → ["txt","text"]`,
    /// `md → ["md","markdown"]`). Restore / lazy-download can materialize a book
    /// with its ORIGINAL extension (`.text` / `.markdown`), not the primary, so a
    /// primary-only path would file-not-found a readable book (Feature #91 Gate-4).
    /// Falls back to the primary path when none exists.
    static func resolveExisting(fingerprintKey: String, format: String) -> URL {
        let safeName = fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let dir = importedBooksDirectory()
        let candidates = BookFormat(rawValue: format.lowercased())?.fileExtensions
            ?? [format.lowercased()]
        for ext in candidates {
            let url = dir.appendingPathComponent(safeName).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return resolve(fingerprintKey: fingerprintKey, format: format)
    }

    private static func importedBooksDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
    }
}
