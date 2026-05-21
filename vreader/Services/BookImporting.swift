// Purpose: Protocol for book import operations, enabling mock injection in tests.
// Separates the import interface from the concrete BookImporter implementation.
//
// @coordinates-with: BookImporter.swift, LibraryViewModel.swift

import Foundation

/// Protocol for book import operations.
protocol BookImporting: Sendable {
    /// Imports a file into the library.
    ///
    /// - Parameters:
    ///   - fileURL: URL to the file to import.
    ///   - source: How the file was provided (Files app, share sheet, etc.).
    ///   - titleOverride: Optional title that takes priority over the
    ///     extractor's filename-derived title. Used by the WebDAV restore
    ///     path (bug #247) to thread `BackupLibraryEntry.title` through
    ///     so restored TXT/MD/PDF books keep their original names instead
    ///     of the SHA-prefixed `restore_<sha>` temp filename. Whitespace-
    ///     trimmed before use; an empty/whitespace-only string is treated
    ///     as nil so callers can pass through the manifest value without
    ///     guard-clauses.
    /// - Returns: The import result with book identity and metadata.
    /// - Throws: `ImportError` for all failure modes.
    func importFile(
        at fileURL: URL,
        source: ImportSource,
        titleOverride: String?
    ) async throws -> ImportResult
}

extension BookImporting {
    /// Convenience overload preserving the historical two-argument
    /// signature. Production paths that don't have a manifest title to
    /// pass (in-app Files picker, Share Sheet, share-extension flow)
    /// keep calling this; restore paths use the three-argument form.
    func importFile(at fileURL: URL, source: ImportSource) async throws -> ImportResult {
        try await importFile(at: fileURL, source: source, titleOverride: nil)
    }
}
