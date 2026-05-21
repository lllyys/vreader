// Purpose: Mock persistence actor for testing BookImporter without SwiftData.

import Foundation
@testable import vreader

/// In-memory mock of BookPersisting for unit tests.
actor MockPersistenceActor: BookPersisting {
    /// All inserted books, keyed by fingerprintKey.
    private var books: [String: BookRecord] = [:]

    /// Count of insertBook calls (for verifying behavior).
    private(set) var insertCallCount = 0

    /// Count of replaceProvenance calls.
    private(set) var replaceProvenanceCallCount = 0

    /// If set, insertBook will throw this error.
    var insertError: (any Error)?

    /// If set, findBook will throw this error.
    var findError: (any Error)?

    /// If set, replaceProvenance will throw this error.
    var replaceProvenanceError: (any Error)?

    func findBook(byFingerprintKey key: String) async throws -> BookRecord? {
        if let error = findError { throw error }
        return books[key]
    }

    func insertBook(_ record: BookRecord) async throws -> BookRecord {
        insertCallCount += 1
        if let error = insertError { throw error }

        // Simulate unique constraint: if already exists, return existing
        if let existing = books[record.fingerprintKey] {
            return existing
        }

        books[record.fingerprintKey] = record
        return record
    }

    func replaceProvenance(_ provenance: ImportProvenance, toBookWithKey key: String) async throws {
        replaceProvenanceCallCount += 1
        if let error = replaceProvenanceError { throw error }
        guard var book = books[key] else {
            assertionFailure("MockPersistenceActor.replaceProvenance: book not found for key \(key)")
            return
        }
        book = BookRecord(
            fingerprintKey: book.fingerprintKey,
            title: book.title,
            author: book.author,
            coverImagePath: book.coverImagePath,
            fingerprint: book.fingerprint,
            provenance: provenance,
            detectedEncoding: book.detectedEncoding,
            addedAt: book.addedAt,
            originalExtension: book.originalExtension,
            lastOpenedAt: book.lastOpenedAt,
            fileState: book.fileState,
            blobPath: book.blobPath
        )
        books[key] = book
    }

    /// Count of updateBookTitle calls.
    private(set) var updateBookTitleCallCount = 0

    /// If set, updateBookTitle will throw this error.
    var updateBookTitleError: (any Error)?

    func updateBookTitle(fingerprintKey key: String, title: String, author: String?) async throws {
        updateBookTitleCallCount += 1
        if let error = updateBookTitleError { throw error }
        guard var book = books[key] else {
            throw ImportError.bookNotFound(key)
        }
        // Mirror PersistenceActor's defense-in-depth normalization so
        // mock-based tests see the same truncation behavior as production.
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw PersistenceError.invalidContent("Empty title")
        }
        let normalizedTitle = String(trimmedTitle.prefix(255))
        book = BookRecord(
            fingerprintKey: book.fingerprintKey,
            title: normalizedTitle,
            author: author ?? book.author,
            coverImagePath: book.coverImagePath,
            fingerprint: book.fingerprint,
            provenance: book.provenance,
            detectedEncoding: book.detectedEncoding,
            addedAt: book.addedAt,
            originalExtension: book.originalExtension,
            lastOpenedAt: book.lastOpenedAt,
            fileState: book.fileState,
            blobPath: book.blobPath
        )
        books[key] = book
    }

    // MARK: - Test Helpers

    /// Returns the stored book for the given key, if any.
    func book(forKey key: String) -> BookRecord? {
        books[key]
    }

    /// Resets all state.
    func reset() {
        books = [:]
        insertCallCount = 0
        replaceProvenanceCallCount = 0
        updateBookTitleCallCount = 0
        insertError = nil
        findError = nil
        replaceProvenanceError = nil
        updateBookTitleError = nil
    }

    /// Directly seeds a book for testing duplicate detection.
    func seed(_ record: BookRecord) {
        books[record.fingerprintKey] = record
    }

    /// Sets the error that insertBook will throw. Actor-isolated setter for use from tests.
    func setInsertError(_ error: (any Error)?) {
        insertError = error
    }
}
