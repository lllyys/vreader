// Purpose: ViewModel for highlight list — load, add, remove, edit, out-of-bounds detection.
// Manages highlights for a single book.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Protocol-based persistence for testability.
// - Newest-first ordering for deterministic overlap rendering.
// - Out-of-bounds detection compares charRangeEndUTF16 against totalTextLengthUTF16.
//
// @coordinates-with: HighlightPersisting.swift, HighlightRecord.swift, HighlightListView.swift

import Foundation

/// ViewModel for highlight list display and management.
@Observable
@MainActor
final class HighlightListViewModel {

    // MARK: - Published State

    /// All highlights for the current book, newest first.
    private(set) var highlights: [HighlightRecord] = []

    /// Whether the highlight list is empty.
    var isEmpty: Bool { highlights.isEmpty }

    /// IDs of highlights whose range extends beyond totalTextLengthUTF16.
    private(set) var outOfBoundsHighlightIds: Set<UUID> = []

    /// Whether any highlights are out of bounds (content may have changed).
    var hasOutOfBoundsHighlights: Bool { !outOfBoundsHighlightIds.isEmpty }

    /// Error message from the last failed operation.
    var errorMessage: String?

    // MARK: - Dependencies

    private let bookFingerprintKey: String
    private let store: any HighlightPersisting
    private let totalTextLengthUTF16: Int?

    // MARK: - Init

    init(
        bookFingerprintKey: String,
        store: any HighlightPersisting,
        totalTextLengthUTF16: Int?
    ) {
        self.bookFingerprintKey = bookFingerprintKey
        self.store = store
        self.totalTextLengthUTF16 = totalTextLengthUTF16
    }

    // MARK: - Load

    /// Loads all highlights for the current book.
    func loadHighlights() async {
        errorMessage = nil
        do {
            highlights = try await store.fetchHighlights(forBookWithKey: bookFingerprintKey)
            detectOutOfBounds()
        } catch {
            highlights = []
            outOfBoundsHighlightIds = []
            errorMessage = "Failed to load highlights."
        }
    }

    // MARK: - Add

    /// Adds a highlight at the given locator.
    func addHighlight(
        locator: Locator,
        selectedText: String,
        color: String,
        note: String?
    ) async {
        errorMessage = nil
        do {
            let record = try await store.addHighlight(
                locator: locator,
                selectedText: selectedText,
                color: color,
                note: note,
                toBookWithKey: bookFingerprintKey
            )
            highlights.insert(record, at: 0)
            detectOutOfBounds()
        } catch {
            errorMessage = "Failed to add highlight."
        }
    }

    // MARK: - Remove

    /// Removes a highlight by its ID.
    func removeHighlight(highlightId: UUID) async {
        errorMessage = nil
        do {
            try await store.removeHighlight(highlightId: highlightId)
            highlights.removeAll { $0.highlightId == highlightId }
            outOfBoundsHighlightIds.remove(highlightId)
        } catch {
            errorMessage = "Failed to remove highlight."
        }
    }

    // MARK: - Edit

    /// Updates the note on a highlight.
    func updateNote(highlightId: UUID, note: String?) async {
        errorMessage = nil
        do {
            try await store.updateHighlightNote(highlightId: highlightId, note: note)
            if let idx = highlights.firstIndex(where: { $0.highlightId == highlightId }) {
                let old = highlights[idx]
                highlights[idx] = HighlightRecord(
                    highlightId: old.highlightId, locator: old.locator,
                    profileKey: old.profileKey, selectedText: old.selectedText,
                    color: old.color, note: note,
                    createdAt: old.createdAt, updatedAt: Date()
                )
            }
        } catch {
            errorMessage = "Failed to update note."
        }
    }

    /// Updates the color of a highlight.
    func updateColor(highlightId: UUID, color: String) async {
        errorMessage = nil
        do {
            try await store.updateHighlightColor(highlightId: highlightId, color: color)
            if let idx = highlights.firstIndex(where: { $0.highlightId == highlightId }) {
                let old = highlights[idx]
                highlights[idx] = HighlightRecord(
                    highlightId: old.highlightId, locator: old.locator,
                    profileKey: old.profileKey, selectedText: old.selectedText,
                    color: color, note: old.note,
                    createdAt: old.createdAt, updatedAt: Date()
                )
            }
        } catch {
            errorMessage = "Failed to update color."
        }
    }

    // MARK: - Private

    /// Detects highlights whose charRangeEndUTF16 exceeds totalTextLengthUTF16.
    private func detectOutOfBounds() {
        guard let total = totalTextLengthUTF16 else {
            outOfBoundsHighlightIds = []
            return
        }
        outOfBoundsHighlightIds = Set(
            highlights
                .filter { highlight in
                    if let end = highlight.locator.charRangeEndUTF16, end > total {
                        return true
                    }
                    return false
                }
                .map(\.highlightId)
        )
    }
}
