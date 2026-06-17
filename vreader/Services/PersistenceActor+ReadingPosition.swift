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
        // #109 WI-2 / #356: repair a non-finite (invalid) locator at the boundary
        // so the stored locator + locatorHash are always valid.
        let locator = locator.repairedForCanonicalization()

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
            // Gate-4 round-1 High (#42 WI-6): the legacy engine just wrote a
            // fresh position, so any previously-saved Readium `VReaderLocator`
            // envelope is now stale. Clear it so a later flag-ON reopen does NOT
            // restore a stale Readium position that predates this legacy write
            // (`loadVReaderLocator` then returns nil → Readium opens at start).
            // The authoritative position for the legacy engine lives in `locator`.
            existing.vreaderLocatorData = nil
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

    // MARK: - Engine-agnostic envelope (Feature #42 WI-6)

    /// Saves the engine-agnostic `VReaderLocator` envelope AND the back-compat
    /// legacy `Locator` in one `context.save()` (dual-write). The Readium engine
    /// persists its position through this path so a flag-OFF reopen (legacy
    /// engine reading `loadPosition`) still finds an approximate position from
    /// the legacy leg. Mirrors `savePosition`'s fetch-book-or-throw + upsert
    /// shape; the envelope is JSON-encoded into `ReadingPosition.vreaderLocatorData`
    /// (the SchemaV8 additive column).
    /// - Throws: `ImportError.bookNotFound` if the book doesn't exist.
    func saveVReaderLocator(
        bookFingerprintKey: String,
        vreaderLocator: VReaderLocator,
        legacyLocator: Locator,
        deviceId: String
    ) async throws {
        // Gate-4 round-1 Medium: mirror savePosition's fingerprint guard so a
        // caller cannot write book X's envelope/legacy locator into book Y's
        // ReadingPosition (which would corrupt both restore paths).
        guard vreaderLocator.fingerprintKey == bookFingerprintKey,
              legacyLocator.bookFingerprint.canonicalKey == bookFingerprintKey else {
            throw PersistenceError.recordNotFound(
                "VReaderLocator/legacy fingerprint does not match book key"
            )
        }
        // #109 WI-2 / #356: repair a non-finite (invalid) legacy locator so the
        // stored fallback locator + locatorHash are always valid.
        let legacyLocator = legacyLocator.repairedForCanonicalization()

        let envelopeData = try JSONEncoder().encode(vreaderLocator)

        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(bookFingerprintKey)
        }

        if let existing = book.readingPosition {
            existing.updateLocator(legacyLocator)
            existing.vreaderLocatorData = envelopeData
            existing.updatedAt = Date()
            existing.deviceId = deviceId
        } else {
            let position = ReadingPosition(
                locator: legacyLocator,
                updatedAt: Date(),
                deviceId: deviceId
            )
            position.vreaderLocatorData = envelopeData
            position.book = book
            book.readingPosition = position
            context.insert(position)
        }

        try context.save()
    }

    /// Loads the engine-agnostic `VReaderLocator` envelope for a book. Returns
    /// nil when no position exists, the row predates the SchemaV8 column
    /// (`vreaderLocatorData == nil`), or the stored bytes fail to decode. The
    /// decode uses `try?` (never throws) — the SwiftData-safe posture documented
    /// on `VReaderLocator`: a legacy / corrupt blob degrades to nil rather than
    /// crashing the reader open.
    func loadVReaderLocator(bookFingerprintKey: String) async throws -> VReaderLocator? {
        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey

        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first,
              let data = book.readingPosition?.vreaderLocatorData else {
            return nil
        }
        return try? JSONDecoder().decode(VReaderLocator.self, from: data)
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

// MARK: - VReaderLocatorPersisting (Feature #42 WI-6)

/// `PersistenceActor` is the sole real envelope store. The `saveVReaderLocator`
/// / `loadVReaderLocator` witnesses are defined in the extension above; this
/// declares the conformance so `ReadiumEPUBReaderViewModel` can take a narrow
/// `any VReaderLocatorPersisting` (no silent-drop default — Gate-4 round-1 Med).
extension PersistenceActor: VReaderLocatorPersisting {}
