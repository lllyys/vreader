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

/// Protocol for persistence operations, enabling mock injection in tests.
protocol BookPersisting: Sendable {
    /// Finds an existing book by fingerprint key, or returns nil.
    func findBook(byFingerprintKey key: String) async throws -> BookRecord?

    /// Inserts a new book. Returns the book record.
    /// If a duplicate exists (unique constraint), returns the existing book instead.
    func insertBook(_ record: BookRecord) async throws -> BookRecord

    /// Updates the provenance for an existing book.
    /// Note: V1 replaces provenance. V2 will maintain a provenance history array.
    func appendProvenance(_ provenance: ImportProvenance, toBookWithKey key: String) async throws
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
            addedAt: record.addedAt
        )
        book.detectedEncoding = record.detectedEncoding
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

    func appendProvenance(_ provenance: ImportProvenance, toBookWithKey key: String) async throws {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.fileNotReadable("appendProvenance: book not found for key \(key)")
        }
        book.provenance = provenance
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
            addedAt: book.addedAt
        )
    }
}
