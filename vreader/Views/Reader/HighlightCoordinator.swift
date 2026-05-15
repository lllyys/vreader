// Purpose: Single coordinator for highlight lifecycle (Phase R4b).
// Owns create, delete, restore, and refresh-after-import flows.
// Calls format-specific HighlightRenderer for visuals and
// HighlightPersisting for database operations.
//
// Key decisions:
// - create() persists first, then calls renderer.apply() with the real record.
//   This ensures the renderer receives the actual highlight ID (needed for
//   PDF annotation map tracking and EPUB JS highlight IDs).
// - create() returns the persisted record (or nil on failure) so callers
//   that need the real ID (e.g., EPUB JS injection) can use it.
// - handleRemoval() removes visually first, then re-fetches and restores
//   the full list to ensure consistency.
// - restoreAll() is used on document open and after imports.
//
// @coordinates-with: HighlightRenderer.swift, HighlightPersisting.swift,
//   ReaderNotificationModifier.swift, EPUBReaderContainerView.swift,
//   PDFReaderContainerView.swift

#if canImport(UIKit)
import Foundation

/// Coordinates highlight create/delete/restore across persistence and rendering.
@MainActor
final class HighlightCoordinator {
    let renderer: any HighlightRenderer
    let persistence: any HighlightPersisting
    let bookFingerprintKey: String

    init(
        renderer: any HighlightRenderer,
        persistence: any HighlightPersisting,
        bookFingerprintKey: String
    ) {
        self.renderer = renderer
        self.persistence = persistence
        self.bookFingerprintKey = bookFingerprintKey
    }

    /// Creates a highlight: persists to DB, then visually applies via renderer.
    /// Returns the created record, or nil if persistence failed.
    @discardableResult
    func create(
        locator: Locator,
        anchor: AnnotationAnchor? = nil,
        selectedText: String,
        color: String = "yellow",
        note: String? = nil
    ) async -> HighlightRecord? {
        guard let record = try? await persistence.addHighlight(
            locator: locator,
            anchor: anchor,
            selectedText: selectedText,
            color: color,
            note: note,
            toBookWithKey: bookFingerprintKey
        ) else { return nil }
        renderer.apply(record: record)
        return record
    }

    /// Handles highlight removal (from annotations panel):
    /// removes visual highlight, then re-fetches all highlights to refresh.
    /// On fetch failure after removal, the removed highlight stays hidden
    /// but other visuals are unchanged.
    func handleRemoval(highlightId: UUID) async {
        renderer.remove(id: highlightId)
        if let records = try? await persistence.fetchHighlights(
            forBookWithKey: bookFingerprintKey
        ) {
            renderer.restore(records: records)
        }
    }

    /// Fetches and restores all saved highlights from persistence.
    /// On fetch failure, leaves current visuals unchanged (avoids destructive reset).
    ///
    /// Bug #103: optional `using` evaluator routes the produced JS to a
    /// caller-supplied destination (e.g., the page-ready WKWebView's
    /// evaluateJavaScript) without mutating the renderer's persistent
    /// `onInjectJS` callback. This avoids the original swap pattern in
    /// `restoreHighlightsOnLoad` which would misroute concurrent
    /// highlight-creation JS to the temporary restore-only callback.
    ///
    /// Bug #103 follow-up: `forHref` is the chapter context captured
    /// at call time. Threading it as immutable input prevents two
    /// concurrent restores for different chapters (fast page
    /// navigation) from cross-wiring through the renderer's shared
    /// mutable `currentHref` — the second call would otherwise
    /// generate JS for a chapter the first call didn't intend.
    func restoreAll(
        forHref href: String? = nil,
        using evaluator: ((String) -> Void)? = nil
    ) async {
        guard let records = try? await persistence.fetchHighlights(
            forBookWithKey: bookFingerprintKey
        ) else { return }
        renderer.restore(records: records, forHref: href, using: evaluator)
    }

    /// Feature #53 / GH #596 — handles an action selected from the inline
    /// menu shown on a highlight tap. WI-1 dispatches `.delete` only; new
    /// cases trigger a compile error here so wiring stays exhaustive.
    ///
    /// `.delete` removes from persistence, then posts `.readerHighlightRemoved`
    /// so the existing bug-#78 visual-clear pipeline updates the rendered
    /// highlight without duplicating the renderer.remove() call here. This
    /// mirrors `HighlightListViewModel.removeHighlight(highlightId:)`.
    func handleTapAction(_ action: HighlightTapAction, highlightID: UUID) async {
        switch action {
        case .delete:
            do {
                try await persistence.removeHighlight(highlightId: highlightID)
                NotificationCenter.default.post(
                    name: .readerHighlightRemoved,
                    object: highlightID.uuidString
                )
            } catch {
                // Persistence failure: keep visual state intact (do not post
                // the removed notification). The user can retry; no UI alert
                // here because the inline menu has already dismissed.
            }
        }
    }
}
#endif
