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

    // MARK: - Feature #64 — unified highlight-action popover mutations

    /// Feature #64 WI-3 — persists a new highlight color, then repaints the
    /// rendered highlight via the format's `HighlightRenderer`.
    ///
    /// Returns a typed `HighlightMutationOutcome` so the popover presenter can
    /// distinguish a deleted-record race (→ dismiss) from a generic failure
    /// (→ keep the popover open, no local mutation). `PersistenceActor`
    /// throws a distinct `PersistenceError.recordNotFound`.
    ///
    /// EPUB href-race (R1-4): when the renderer is chapter-scoped (the EPUB
    /// renderer), its `currentChapterHref` is captured BEFORE the persistence
    /// `await` and threaded into `restoreAll(forHref:)`.
    /// `EPUBHighlightRenderer.restore` resolves `href ?? currentHref` and
    /// `currentHref` is a mutable `var` — across the `await`, a racing
    /// chapter-nav could mutate it and repaint the wrong chapter. Capturing it
    /// up front is the Bug #103 immutable-href pattern. The capture goes
    /// through `ChapterScopedHighlightRenderer`, not a concrete-type cast, so
    /// it is unit-testable with a fake. Non-EPUB renderers (TXT/MD/PDF) are
    /// not chapter-scoped — they ignore the href and get `forHref: nil`.
    func changeColor(highlightID: UUID, to color: String) async -> HighlightMutationOutcome {
        // Capture the chapter context at call time, before the await.
        let capturedHref = (renderer as? any ChapterScopedHighlightRenderer)?.currentChapterHref

        do {
            try await persistence.updateHighlightColor(highlightId: highlightID, color: color)
        } catch let error as PersistenceError {
            if case .recordNotFound = error { return .notFound }
            return .failed
        } catch {
            return .failed
        }

        // Re-fetch to get the persisted post-mutation state AND the records to
        // repaint from. A fetch failure here is a generic failure (`.failed`),
        // NOT a deleted-record race — only a successful fetch with no matching
        // id means the record was concurrently deleted (R1-5).
        let records: [HighlightRecord]
        do {
            records = try await persistence.fetchHighlights(forBookWithKey: bookFingerprintKey)
        } catch {
            return .failed
        }
        guard let record = records.first(where: { $0.highlightId == highlightID }) else {
            return .notFound
        }
        // Repaint from the already-fetched records directly, so the repaint
        // is not silently dropped by `restoreAll`'s own fetch (which swallows
        // failures). The re-fetch above already carries the new color.
        renderer.restore(records: records, forHref: capturedHref, using: nil)
        return .success(record)
    }

    /// Feature #64 WI-3 — persists a note edit on a highlight. No
    /// reader-surface repaint — the note is not drawn on the page, so the
    /// only UI to refresh is the popover card itself (handled by the caller).
    ///
    /// A trimmed-empty draft (`nil` / `""` / all-whitespace) is normalized to
    /// `nil` before persisting, so a note "cleared" to whitespace stores as no
    /// note and the popover flips to the empty state. Returns the typed
    /// outcome for the same reason as `changeColor`.
    func updateNote(highlightID: UUID, note: String?) async -> HighlightMutationOutcome {
        let normalized = HighlightCoordinator.normalizedNote(note)

        do {
            try await persistence.updateHighlightNote(highlightId: highlightID, note: normalized)
        } catch let error as PersistenceError {
            if case .recordNotFound = error { return .notFound }
            return .failed
        } catch {
            return .failed
        }

        // Re-fetch to get the persisted post-mutation record. Same R1-5
        // discipline as `changeColor`: a fetch throw is `.failed`; only a
        // successful fetch with no match is `.notFound`.
        let records: [HighlightRecord]
        do {
            records = try await persistence.fetchHighlights(forBookWithKey: bookFingerprintKey)
        } catch {
            return .failed
        }
        guard let record = records.first(where: { $0.highlightId == highlightID }) else {
            return .notFound
        }
        return .success(record)
    }

    /// Normalizes a note draft: an all-whitespace (or empty / nil) draft
    /// becomes `nil`; a non-empty draft is preserved verbatim (including its
    /// own surrounding whitespace).
    static func normalizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : note
    }
}
#endif
