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
            // Upsert: avoid duplicates if store returned existing record
            if !highlights.contains(where: { $0.highlightId == record.highlightId }) {
                highlights.insert(record, at: 0)
            }
            detectOutOfBounds()
        } catch {
            errorMessage = "Failed to add highlight."
        }
    }

    // MARK: - Remove

    /// Removes a highlight by its ID.
    ///
    /// Bug #229 / GH #938: AZW3/MOBI highlights are rendered as Foliate-js SVG
    /// overlays driven by `.foliateRequestAnnotationJSDelete` (CFI-keyed), not
    /// by `.readerHighlightRemoved` (UUID-keyed). The Foliate Coordinator's
    /// `.readerHighlightRemoved` observer does not exist — only its
    /// `.foliateRequestAnnotationJSDelete` observer does — so the panel-delete
    /// path must capture the record's `.epub` anchor CFI BEFORE the
    /// persistence delete and post the JS-strip notification alongside the
    /// `.readerHighlightRemoved` it already emits for the panel/list sync.
    ///
    /// Mirrors `FoliateHighlightJSBridge.delete(record:fingerprintKey:)` — the
    /// in-reader popover's delete path — so panel + in-reader paths converge
    /// on the same notification contract. A record whose anchor is not
    /// `.epub` (TXT/MD/PDF, or legacy/nil/empty-CFI) posts only
    /// `.readerHighlightRemoved` — no JS strip is needed for those renderers,
    /// and the Foliate Coordinator's CFI filter would reject an empty CFI
    /// anyway.
    func removeHighlight(highlightId: UUID) async {
        errorMessage = nil
        // Capture the record BEFORE the persistence delete — a post-hoc
        // `fetchHighlights` would miss it (the record is gone), and `self.highlights`
        // is the authoritative in-memory copy after `loadHighlights`.
        let preDeleteCFI = Self.epubAnchorCFI(
            of: highlights.first(where: { $0.highlightId == highlightId })
        )
        do {
            try await store.removeHighlight(highlightId: highlightId)
            highlights.removeAll { $0.highlightId == highlightId }
            outOfBoundsHighlightIds.remove(highlightId)
            // Notify reader to clear the visual highlight immediately (bug #78).
            NotificationCenter.default.post(
                name: .readerHighlightRemoved,
                object: highlightId.uuidString
            )
            // AZW3/MOBI overlay strip (bug #229). The Foliate Coordinator
            // observes `.foliateRequestAnnotationJSDelete` keyed on
            // `fingerprintKey`; concurrent readers on other books ignore this
            // post via the same key filter. Posted only when the captured
            // record carried a non-empty `.epub` CFI — other anchor cases
            // (TXT/MD .text, PDF .pdf, nil, empty-CFI) skip cleanly.
            if let cfi = preDeleteCFI {
                NotificationCenter.default.post(
                    name: .foliateRequestAnnotationJSDelete,
                    object: nil,
                    userInfo: [
                        "cfi": cfi,
                        "fingerprintKey": bookFingerprintKey,
                    ]
                )
            }
        } catch {
            errorMessage = "Failed to remove highlight."
        }
    }

    /// Extracts the CFI from an `.epub` anchor on a captured highlight record.
    /// Returns `nil` for any non-`.epub` anchor, a `nil` record, a `nil`
    /// anchor, or an empty CFI — mirrors `FoliateHighlightJSBridge.cfi(from:)`
    /// so the panel-delete and in-reader-delete paths apply the same filter.
    private static func epubAnchorCFI(of record: HighlightRecord?) -> String? {
        guard let record = record else { return nil }
        guard case let .epub(_, cfi, _) = record.anchor, !cfi.isEmpty else { return nil }
        return cfi
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
                    anchor: old.anchor,
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
                    anchor: old.anchor,
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
