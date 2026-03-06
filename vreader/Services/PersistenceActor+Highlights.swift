// Purpose: Extension adding HighlightPersisting conformance to PersistenceActor.
// Provides highlight CRUD for the reader views.
//
// @coordinates-with: PersistenceActor.swift, HighlightPersisting.swift,
//   Highlight.swift, HighlightRecord.swift

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
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(key)
        }

        // Dedupe: return existing highlight at the same location
        let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        if let existing = book.highlights.first(where: { $0.profileKey == profileKey }) {
            return highlightToRecord(existing)
        }

        let highlight = Highlight(
            locator: locator,
            selectedText: selectedText,
            color: color,
            note: note
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

    // MARK: - Private

    private func highlightToRecord(_ highlight: Highlight) -> HighlightRecord {
        HighlightRecord(
            highlightId: highlight.highlightId,
            locator: highlight.locator,
            profileKey: highlight.profileKey,
            selectedText: highlight.selectedText,
            color: highlight.color,
            note: highlight.note,
            createdAt: highlight.createdAt,
            updatedAt: highlight.updatedAt
        )
    }
}
