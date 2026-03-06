// Purpose: Mock highlight persistence for unit testing.
//
// @coordinates-with: HighlightPersisting.swift, HighlightListViewModelTests.swift

import Foundation
@testable import vreader

/// In-memory mock of HighlightPersisting for unit tests.
actor MockHighlightStore: HighlightPersisting {
    private var highlights: [UUID: HighlightRecord] = [:]
    private var bookIndex: [String: [UUID]] = [:]

    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0
    private(set) var updateNoteCallCount = 0
    private(set) var updateColorCallCount = 0
    private(set) var fetchCallCount = 0

    var addError: (any Error & Sendable)?
    var removeError: (any Error & Sendable)?
    var fetchError: (any Error & Sendable)?

    func addHighlight(
        locator: Locator,
        selectedText: String,
        color: String,
        note: String?,
        toBookWithKey key: String
    ) async throws -> HighlightRecord {
        addCallCount += 1
        if let error = addError { throw error }

        let record = HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: selectedText,
            color: color,
            note: note,
            createdAt: Date(),
            updatedAt: Date()
        )
        highlights[record.highlightId] = record
        bookIndex[key, default: []].append(record.highlightId)
        return record
    }

    func removeHighlight(highlightId: UUID) async throws {
        removeCallCount += 1
        if let error = removeError { throw error }

        highlights.removeValue(forKey: highlightId)
        for (bookKey, ids) in bookIndex {
            bookIndex[bookKey] = ids.filter { $0 != highlightId }
        }
    }

    func updateHighlightNote(highlightId: UUID, note: String?) async throws {
        updateNoteCallCount += 1
        guard let record = highlights[highlightId] else { return }
        let updated = HighlightRecord(
            highlightId: record.highlightId,
            locator: record.locator,
            profileKey: record.profileKey,
            selectedText: record.selectedText,
            color: record.color,
            note: note,
            createdAt: record.createdAt,
            updatedAt: Date()
        )
        highlights[highlightId] = updated
    }

    func updateHighlightColor(highlightId: UUID, color: String) async throws {
        updateColorCallCount += 1
        guard let record = highlights[highlightId] else { return }
        let updated = HighlightRecord(
            highlightId: record.highlightId,
            locator: record.locator,
            profileKey: record.profileKey,
            selectedText: record.selectedText,
            color: color,
            note: record.note,
            createdAt: record.createdAt,
            updatedAt: Date()
        )
        highlights[highlightId] = updated
    }

    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
        fetchCallCount += 1
        if let error = fetchError { throw error }

        let ids = bookIndex[key] ?? []
        return ids.compactMap { highlights[$0] }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Test Helpers

    func setFetchError(_ error: (any Error & Sendable)?) {
        fetchError = error
    }

    func setAddError(_ error: (any Error & Sendable)?) {
        addError = error
    }

    func seed(_ record: HighlightRecord, forBookWithKey key: String) {
        highlights[record.highlightId] = record
        bookIndex[key, default: []].append(record.highlightId)
    }

    func allHighlights() -> [HighlightRecord] {
        Array(highlights.values)
    }

    func reset() {
        highlights = [:]
        bookIndex = [:]
        addCallCount = 0
        removeCallCount = 0
        updateNoteCallCount = 0
        updateColorCallCount = 0
        fetchCallCount = 0
        addError = nil
        removeError = nil
        fetchError = nil
    }
}
