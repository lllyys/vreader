// Purpose: Protocol for highlight persistence operations.
// Enables mock injection in tests.
//
// @coordinates-with: PersistenceActor+Highlights.swift, HighlightRecord.swift

import Foundation

/// Protocol for highlight persistence operations, enabling mock injection in tests.
protocol HighlightPersisting: Sendable {
    /// Adds a highlight to a book. Returns the created record.
    func addHighlight(
        locator: Locator,
        selectedText: String,
        color: String,
        note: String?,
        toBookWithKey key: String
    ) async throws -> HighlightRecord

    /// Removes a highlight by its ID.
    func removeHighlight(highlightId: UUID) async throws

    /// Updates the note on a highlight.
    func updateHighlightNote(highlightId: UUID, note: String?) async throws

    /// Updates the color of a highlight.
    func updateHighlightColor(highlightId: UUID, color: String) async throws

    /// Fetches all highlights for a book, ordered by creation date (newest first).
    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord]
}
