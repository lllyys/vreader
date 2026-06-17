// Purpose: Actor-isolated SwiftData writer. Serializes all write operations
// to prevent race conditions on the model context.
//
// Key decisions:
// - Global actor for single-writer guarantee on SwiftData.
// - Background ModelContext for import operations.
// - Duplicate detection uses fingerprintKey unique constraint.
// - Race-safe: insert attempts that violate uniqueness retry as fetch.
//
// @coordinates-with: BookImporter.swift, ImportError.swift

import Foundation
import SwiftData

/// Errors from persistence operations beyond import.
enum PersistenceError: Error, Sendable {
    case recordNotFound(String)
    case invalidContent(String)
    /// Bulk-insert pipeline failed partway through. `insertedKeys` carries
    /// the fingerprintKeys that were successfully persisted in input order
    /// before the failure, so callers (e.g., `SelectiveRestoreCoordinator`
    /// in bug #119's fix) can still react to the partial result —
    /// notify subscribers for what landed, log the rest as "manual repair
    /// required." `underlyingDescription` is the original error
    /// rendered as a string (Sendable) from the failing record's
    /// `insertBook` call.
    case partialBulkInsert(insertedKeys: [String], underlyingDescription: String)
}

/// Protocol for persistence operations, enabling mock injection in tests.
protocol BookPersisting: Sendable {
    /// Finds an existing book by fingerprint key, or returns nil.
    func findBook(byFingerprintKey key: String) async throws -> BookRecord?

    /// Inserts a new book. Returns the book record.
    /// If a duplicate exists (unique constraint), returns the existing book instead.
    func insertBook(_ record: BookRecord) async throws -> BookRecord

    /// Updates the provenance for an existing book.
    /// Note: V1 replaces provenance. V2 will maintain a provenance history array.
    func replaceProvenance(_ provenance: ImportProvenance, toBookWithKey key: String) async throws

    /// Updates the title (and optionally author) for an existing book.
    /// Used by the WebDAV restore path (bug #247) when the manifest's
    /// `BackupLibraryEntry.title` should override the extractor's
    /// filename-derived title on a dedupe-hit. `title` must already be
    /// non-empty after trimming; the caller is responsible for that
    /// validation. `author` is set when non-nil; an existing author is
    /// left untouched when `author` is nil.
    func updateBookTitle(fingerprintKey: String, title: String, author: String?) async throws
}

/// Lightweight value type representing a book for cross-boundary transfer.
/// Avoids passing @Model objects across actor boundaries.
struct BookRecord: Sendable, Equatable {
    let fingerprintKey: String
    let title: String
    let author: String?
    let coverImagePath: String?
    let fingerprint: DocumentFingerprint
    let provenance: ImportProvenance
    let detectedEncoding: String?
    let addedAt: Date
    /// Original file extension at import time (e.g. "mobi" for AZW3-canonical books).
    /// Optional for legacy callers; set on new imports from the source URL.
    let originalExtension: String?
    /// Cross-platform canonical identity for converted-Kindle books (feature #108):
    /// `azw3:{sha256_of_source}:{source_byte_count}`. Nil for native imports and
    /// pre-#108 books. Set by `BookImporter` when convert-on-import runs (WI-2).
    let sourceCanonicalKey: String?
    /// When the book was last opened. Read-only mirror of Book.lastOpenedAt;
    /// set by reader open flows, not by insertBook.
    let lastOpenedAt: Date?
    /// File-presence state (feature #47 WI-1). Defaults to `.local` for
    /// new imports; remote-only / downloading / failed states are written
    /// by the lazy-download coordinator (#47 WI-3) and selective restore
    /// (#47 WI-4).
    let fileState: BookFileState
    /// Server-side blob path on the WebDAV backup server (feature #47 WI-1).
    /// Nil for local-only books that have never been uploaded; populated for
    /// rows materialized from a backup or pending download.
    let blobPath: String?

    init(
        fingerprintKey: String,
        title: String,
        author: String?,
        coverImagePath: String?,
        fingerprint: DocumentFingerprint,
        provenance: ImportProvenance,
        detectedEncoding: String?,
        addedAt: Date,
        originalExtension: String? = nil,
        sourceCanonicalKey: String? = nil,
        lastOpenedAt: Date? = nil,
        fileState: BookFileState = .local,
        blobPath: String? = nil
    ) {
        self.fingerprintKey = fingerprintKey
        self.title = title
        self.author = author
        self.coverImagePath = coverImagePath
        self.fingerprint = fingerprint
        self.provenance = provenance
        self.detectedEncoding = detectedEncoding
        self.addedAt = addedAt
        self.originalExtension = originalExtension
        self.sourceCanonicalKey = sourceCanonicalKey
        self.lastOpenedAt = lastOpenedAt
        self.fileState = fileState
        self.blobPath = blobPath
    }
}

/// Actor-isolated persistence layer for SwiftData writes.
/// In production, wraps a ModelContainer. In tests, replaced by MockPersistenceActor.
actor PersistenceActor: BookPersisting {
    /// Internal visibility required: extensions in separate files
    /// (e.g. PersistenceActor+Library.swift) cannot access private members.
    let modelContainer: ModelContainer

    /// Core Data error codes indicating unique constraint violations.
    /// - 133021: NSManagedObjectConstraintMergeError (constraint merge conflict)
    /// - 1550–1560: NSManagedObjectValidationError range (includes multi-error wrapper)
    private static let constraintViolationCodes: Set<Int> = [133021, 1550, 1551, 1560]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func findBook(byFingerprintKey key: String) async throws -> BookRecord? {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        let results = try context.fetch(descriptor)
        return results.first.map { bookToRecord($0) }
    }

    func insertBook(_ record: BookRecord) async throws -> BookRecord {
        // Guard: fingerprintKey must match fingerprint's canonical key
        guard record.fingerprintKey == record.fingerprint.canonicalKey else {
            throw PersistenceError.invalidContent("Fingerprint key mismatch")
        }

        let context = ModelContext(modelContainer)

        // Check for existing first (idempotent)
        let key = record.fingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor)
        if let existingBook = existing.first {
            return bookToRecord(existingBook)
        }

        // Insert new
        let book = Book(
            fingerprint: record.fingerprint,
            title: record.title,
            author: record.author,
            coverImagePath: record.coverImagePath,
            provenance: record.provenance,
            addedAt: record.addedAt,
            originalExtension: record.originalExtension,
            sourceCanonicalKey: record.sourceCanonicalKey
        )
        book.detectedEncoding = record.detectedEncoding
        // Feature #47 WI-2: write fileState/blobPath if the record overrides
        // the SwiftData defaults (.local / nil). Most callers use defaults.
        book.fileState = record.fileState.rawValue
        book.blobPath = record.blobPath
        context.insert(book)

        do {
            try context.save()
        } catch let error as NSError where error.domain == "NSCocoaErrorDomain"
            && Self.constraintViolationCodes.contains(error.code) {
            // Unique constraint violation — race with concurrent import.
            // Retry as fetch; non-constraint errors propagate normally.
            let retryResults = try context.fetch(descriptor)
            if let racedBook = retryResults.first {
                return bookToRecord(racedBook)
            }
            throw error
        }

        return record
    }

    func replaceProvenance(_ provenance: ImportProvenance, toBookWithKey key: String) async throws {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(key)
        }
        book.provenance = provenance
        try context.save()
    }

    /// Bug #247: WebDAV restore re-uses a dedupe-hit Book row when the
    /// content SHA matches an existing import. Pre-fix, the existing
    /// title stuck (often the SHA-prefixed `restore_<sha>` from an
    /// earlier restore). Post-fix, the manifest title from
    /// `BackupLibraryEntry.title` is the source of truth and the row
    /// gets updated so the user sees the original book name.
    ///
    /// Defense in depth: applies the same trim + 255-char cap that
    /// `Book.init` does so direct callers (including future ones) can't
    /// silently bypass the invariant by going through this entry point.
    func updateBookTitle(fingerprintKey key: String, title: String, author: String?) async throws {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(key)
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            // Mirrors Book.init's "Untitled" fallback — but here it's a
            // programmer error to call with empty/whitespace; the
            // BookImporter caller has already filtered those out.
            throw PersistenceError.invalidContent("Empty title")
        }
        book.title = String(trimmedTitle.prefix(255))
        if let author { book.author = author }
        try context.save()
    }

    // MARK: - Private

    private func bookToRecord(_ book: Book) -> BookRecord {
        BookRecord(
            fingerprintKey: book.fingerprintKey,
            title: book.title,
            author: book.author,
            coverImagePath: book.coverImagePath,
            fingerprint: book.fingerprint,
            provenance: book.provenance,
            detectedEncoding: book.detectedEncoding,
            addedAt: book.addedAt,
            originalExtension: book.originalExtension,
            sourceCanonicalKey: book.sourceCanonicalKey,
            lastOpenedAt: book.lastOpenedAt,
            fileState: BookFileState(rawValue: book.fileState) ?? .local,
            blobPath: book.blobPath
        )
    }
}
