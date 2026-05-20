// Purpose: Mock book importer for testing LibraryViewModel.importFiles().
// Tracks calls and allows configuring per-URL success/failure behavior.

import Foundation
@testable import vreader

/// In-memory mock of BookImporting for unit tests.
actor MockBookImporter: BookImporting {
    /// URLs that were passed to importFile, in call order.
    private(set) var importedURLs: [URL] = []

    /// Sources that were passed to importFile, in call order.
    private(set) var importedSources: [ImportSource] = []

    /// Title overrides that were passed to importFile, in call order.
    /// Bug #247 tests use this to assert restore paths thread the
    /// manifest's `BackupLibraryEntry.title` through to the importer.
    private(set) var importedTitleOverrides: [String?] = []

    /// Per-URL error overrides. If a URL is in this map, importFile throws the error.
    private var errorsByURL: [URL: any Error] = [:]

    /// Default error to throw for any URL not in errorsByURL. Nil means success.
    var defaultError: (any Error)?

    /// Fixed result to return on success. Uses a sensible default if nil.
    var fixedResult: ImportResult?

    nonisolated func importFile(
        at fileURL: URL,
        source: ImportSource,
        titleOverride: String?
    ) async throws -> ImportResult {
        try await _importFile(at: fileURL, source: source, titleOverride: titleOverride)
    }

    private func _importFile(
        at fileURL: URL,
        source: ImportSource,
        titleOverride: String?
    ) async throws -> ImportResult {
        importedURLs.append(fileURL)
        importedSources.append(source)
        importedTitleOverrides.append(titleOverride)

        if let error = errorsByURL[fileURL] {
            throw error
        }
        if let error = defaultError {
            throw error
        }

        if let result = fixedResult {
            return result
        }

        // Generate a deterministic result from the URL
        let stableHash = abs(fileURL.lastPathComponent.utf8.reduce(0) { $0 &+ Int($1) })
        let key = "txt:\(stableHash):1024"
        guard let fingerprint = DocumentFingerprint.validated(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1024,
            format: .txt
        ) else {
            throw ImportError.hashComputationFailed("Mock fingerprint validation failed unexpectedly")
        }
        let provenance = ImportProvenance(
            source: source,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )
        // Honor the override (trimmed/empty-as-nil) so tests asserting
        // result.title see the override-or-filename behavior the real
        // BookImporter exhibits.
        let trimmedOverride = titleOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if let override = trimmedOverride, !override.isEmpty {
            resolvedTitle = override
        } else {
            resolvedTitle = fileURL.deletingPathExtension().lastPathComponent
        }
        return ImportResult(
            fingerprintKey: key,
            title: resolvedTitle,
            author: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: "utf-8",
            isDuplicate: false
        )
    }

    // MARK: - Test Helpers

    /// Configure a specific URL to fail with the given error.
    func setError(_ error: any Error, for url: URL) {
        errorsByURL[url] = error
    }

    /// Sets the default error for all URLs not in the per-URL map.
    func setDefaultError(_ error: (any Error)?) {
        defaultError = error
    }

    /// Resets all state.
    func reset() {
        importedURLs = []
        importedSources = []
        importedTitleOverrides = []
        errorsByURL = [:]
        defaultError = nil
        fixedResult = nil
    }
}
