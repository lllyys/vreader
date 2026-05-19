// Purpose: `HighlightLookup`, a narrow read-only persistence protocol for
// fetching one highlight by id.
//
// Boundary protocol so the highlight-popover view model is unit-testable with
// a mock instead of a live `PersistenceActor` — mirrors `LibraryPersisting` /
// `HighlightPersisting`. `PersistenceActor` is the production conformer.
// (Introduced for feature #55's note preview; feature #64's
// `HighlightPopoverViewModel` is the current consumer.)
//
// Key decisions:
// - Keyed by `(id, bookKey)` so a lookup is scoped to the open book and
//   cannot leak a highlight from a different book — the highlight-popover
//   path always knows which book is open.
// - Returns the existing `HighlightRecord` value type and takes the same
//   `(UUID, String)` identifiers the rest of the highlight API uses, so the
//   protocol shape leaks no persistence concern.
// - `Sendable` so the conformer can be held across actor boundaries.
//
// @coordinates-with: PersistenceActor+Highlights.swift, HighlightRecord.swift,
//   HighlightPopoverViewModel.swift

import Foundation

/// Read-only lookup of a single highlight by id, scoped to one book.
protocol HighlightLookup: Sendable {
    /// Fetches the highlight with `id` belonging to the book identified by
    /// `key` (the book's `fingerprintKey`). Returns `nil` when no highlight
    /// with that id exists under that book.
    func highlight(withID id: UUID, forBookWithKey key: String) async throws -> HighlightRecord?
}
