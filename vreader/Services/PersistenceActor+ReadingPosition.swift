// Purpose: Extension adding ReadingPositionPersisting conformance to PersistenceActor.
// Provides reading position save/load for the reader views.
//
// @coordinates-with: PersistenceActor.swift, ReadingPositionPersisting.swift,
//   ReadingPosition.swift

import Foundation
import SwiftData

extension PersistenceActor: ReadingPositionPersisting {

    /// Loads the saved reading position for a book.
    func loadPosition(bookFingerprintKey: String) async throws -> Locator? {
        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey

        // Fetch via book -> readingPosition relationship
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            return nil
        }
        return book.readingPosition?.locator
    }

    /// Saves the current reading position for a book.
    /// Creates a new ReadingPosition if none exists, or updates the existing one.
    /// - Throws: `ImportError.bookNotFound` if the book doesn't exist.
    func savePosition(
        bookFingerprintKey: String,
        locator: Locator,
        deviceId: String
    ) async throws {
        guard locator.bookFingerprint.canonicalKey == bookFingerprintKey else {
            throw PersistenceError.recordNotFound("Locator fingerprint does not match book key")
        }

        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(bookFingerprintKey)
        }

        if let existing = book.readingPosition {
            existing.updateLocator(locator)
            existing.updatedAt = Date()
            existing.deviceId = deviceId
        } else {
            let position = ReadingPosition(
                locator: locator,
                updatedAt: Date(),
                deviceId: deviceId
            )
            position.book = book
            book.readingPosition = position
            context.insert(position)
        }

        try context.save()
    }

    /// Updates the lastOpenedAt timestamp for a book.
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws {
        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(bookFingerprintKey)
        }

        book.lastOpenedAt = date
        try context.save()
    }
}
