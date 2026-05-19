// Purpose: Feature #55 WI-1 — `HighlightLookup`, a narrow read-only
// persistence protocol for fetching one highlight by id.
//
// Boundary protocol so `NotePreviewViewModel` (WI-3) is unit-testable with a
// mock instead of a live `PersistenceActor` — mirrors `LibraryPersisting` /
// `HighlightPersisting`. `PersistenceActor` conforms in WI-2.
//
// Key decisions:
// - Keyed by `(id, bookKey)` so a lookup is scoped to the open book and
//   cannot leak a highlight from a different book — the note-preview path
//   always knows which book is open.
// - Returns the existing `HighlightRecord` value type and takes the same
//   `(UUID, String)` identifiers the rest of the highlight API uses, so the
//   protocol shape leaks no persistence concern.
// - `Sendable` so the conformer can be held across actor boundaries.
//
// @coordinates-with: PersistenceActor+Highlights.swift, HighlightRecord.swift,
//   NotePreviewViewModel.swift

import Foundation

/// Read-only lookup of a single highlight by id, scoped to one book.
protocol HighlightLookup: Sendable {
    /// Fetches the highlight with `id` belonging to the book identified by
    /// `key` (the book's `fingerprintKey`). Returns `nil` when no highlight
    /// with that id exists under that book.
    func highlight(withID id: UUID, forBookWithKey key: String) async throws -> HighlightRecord?
}
