// Purpose: Extension adding HighlightPersisting conformance to PersistenceActor.
// Provides highlight CRUD for the reader views.
//
// @coordinates-with: PersistenceActor.swift, HighlightPersisting.swift,
//   Highlight.swift, HighlightRecord.swift, AnnotationAnchor.swift

import Foundation
import SwiftData

extension PersistenceActor: HighlightPersisting {

    func addHighlight(
        locator: Locator,
        selectedText: String,
        color: String,
        note: String?,
        toBookWithKey key: String
    ) async throws -> HighlightRecord {
        try await addHighlight(
            locator: locator,
            anchor: nil,
            selectedText: selectedText,
            color: color,
            note: note,
            toBookWithKey: key
        )
    }

    func addHighlight(
        locator: Locator,
        anchor: AnnotationAnchor?,
        selectedText: String,
        color: String,
        note: String?,
        toBookWithKey key: String
    ) async throws -> HighlightRecord {
        guard locator.bookFingerprint.canonicalKey == key else {
            throw PersistenceError.recordNotFound("Locator fingerprint does not match book key")
        }

        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(key)
        }

        // Dedupe: return existing highlight at the same location + anchor.
        // When anchor is present, require both profileKey AND anchorHash to match.
        // When anchor is nil (legacy), fall back to profileKey-only among nil-anchor highlights.
        let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        if let existing = book.highlights.first(where: { existing in
            guard existing.profileKey == profileKey else { return false }
            switch (existing.anchor, anchor) {
            case (nil, nil):
                return true
            case let (existingAnchor?, newAnchor?):
                return existingAnchor.anchorHash == newAnchor.anchorHash
            default:
                // One nil, one non-nil → not a duplicate
                return false
            }
        }) {
            return highlightToRecord(existing)
        }

        let highlight = Highlight(
            locator: locator,
            selectedText: selectedText,
            color: color,
            note: note,
            anchor: anchor
        )
        highlight.book = book
        book.highlights.append(highlight)
        context.insert(highlight)
        try context.save()

        return highlightToRecord(highlight)
    }

    func removeHighlight(highlightId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let id = highlightId
        let predicate = #Predicate<Highlight> { $0.highlightId == id }
        var descriptor = FetchDescriptor<Highlight>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let highlight = try context.fetch(descriptor).first else {
            return
        }

        context.delete(highlight)
        try context.save()
    }

    func updateHighlightNote(highlightId: UUID, note: String?) async throws {
        let context = ModelContext(modelContainer)
        let id = highlightId
        let predicate = #Predicate<Highlight> { $0.highlightId == id }
        var descriptor = FetchDescriptor<Highlight>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let highlight = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound("Highlight \(highlightId)")
        }

        highlight.note = note
        highlight.updatedAt = Date()
        try context.save()
    }

    func updateHighlightColor(highlightId: UUID, color: String) async throws {
        let context = ModelContext(modelContainer)
        let id = highlightId
        let predicate = #Predicate<Highlight> { $0.highlightId == id }
        var descriptor = FetchDescriptor<Highlight>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let highlight = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound("Highlight \(highlightId)")
        }

        highlight.color = color
        highlight.updatedAt = Date()
        try context.save()
    }

    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            return []
        }

        return book.highlights
            .sorted { $0.createdAt > $1.createdAt }
            .map { highlightToRecord($0) }
    }

    /// Fetches a single highlight by id, scoped to the book identified by
    /// `key`. Returns `nil` when no highlight with that id belongs to that
    /// book — feature #55's note-preview tap path.
    ///
    /// A dedicated single-row fetch with a predicate on `highlightId` AND the
    /// owning book's `fingerprintKey`: the note-preview path fires on every
    /// annotated-text tap, so it must not page the whole book's highlight set
    /// into memory (plan §2.4 / §6 R-1). The `(id, key)` scoping makes a
    /// lookup unable to leak a highlight from a different book.
    func highlight(withID id: UUID, forBookWithKey key: String) async throws -> HighlightRecord? {
        let context = ModelContext(modelContainer)
        let highlightID = id
        let bookKey = key
        let predicate = #Predicate<Highlight> { highlight in
            highlight.highlightId == highlightID
                && highlight.book?.fingerprintKey == bookKey
        }
        var descriptor = FetchDescriptor<Highlight>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let highlight = try context.fetch(descriptor).first else {
            return nil
        }
        return highlightToRecord(highlight)
    }

    /// Total count of all highlights in the library, across all books.
    /// Single aggregate query — does not materialize any record.
    func countAllHighlights() async throws -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Highlight>()
        return try context.fetchCount(descriptor)
    }

    // MARK: - Private

    private func highlightToRecord(_ highlight: Highlight) -> HighlightRecord {
        HighlightRecord(
            highlightId: highlight.highlightId,
            locator: highlight.locator,
            anchor: highlight.anchor,
            profileKey: highlight.profileKey,
            selectedText: highlight.selectedText,
            color: highlight.color,
            note: highlight.note,
            createdAt: highlight.createdAt,
            updatedAt: highlight.updatedAt
        )
    }
}

// `highlight(withID:forBookWithKey:)` above satisfies the `HighlightLookup`
// boundary protocol, letting feature #64's `HighlightPopoverViewModel` be
// unit-tested against a mock instead of a live actor.
extension PersistenceActor: HighlightLookup {}
