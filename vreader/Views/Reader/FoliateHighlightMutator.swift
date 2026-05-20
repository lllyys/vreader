// Purpose: Feature #64 WI-9 — `FoliateHighlightMutator`, the `HighlightMutating`
// conformer that wires the unified highlight-action popover to the Foliate
// (AZW3/MOBI) reader container.
//
// Foliate has NO `HighlightRenderer` conformer — `FoliateHighlightRenderer` is
// a `struct` with only `static` JS-builder methods, and Foliate highlight
// visuals are driven by `NotificationCenter` messages keyed on CFI. So the
// Foliate container cannot reuse `HighlightCoordinator` (which requires a
// `HighlightRenderer`) as the unified popover's `mutating:` boundary.
//
// `FoliateHighlightMutator` is the Foliate-specific `HighlightMutating`
// conformer. It composes two pieces:
//   - `HighlightPersisting` — persists the color / note / delete, returning
//     the same typed `HighlightMutationOutcome` as `HighlightCoordinator`
//     (`.success` / `.notFound` / `.failed`), with the same R1-5 fetch
//     discipline (a post-mutation fetch throw is `.failed`, only a successful
//     fetch with no matching id is `.notFound`).
//   - `FoliateHighlightJSBridge` — repaints the live WKWebView SVG overlay via
//     the CFI-keyed `.foliateRequestAnnotationJS*` notification pair.
//
// Why a separate type and not `HighlightCoordinator`: plan §5 rejected routing
// Foliate through `HighlightCoordinator` (R1-3 / R2-2) — constructing one
// requires a `HighlightRenderer` Foliate does not have.
//
// @coordinates-with: HighlightCoordinator.swift (the `HighlightMutating`
//   protocol + the persistence pattern this mirrors), FoliateHighlightJSBridge.swift,
//   HighlightPersisting.swift, FoliateSpikeView.swift (the consumer)

#if canImport(UIKit)
import Foundation

/// The Foliate (AZW3/MOBI) `HighlightMutating` conformer for the unified
/// highlight-action popover — persistence via `HighlightPersisting` + live
/// overlay repaint via `FoliateHighlightJSBridge`.
@MainActor
final class FoliateHighlightMutator {
    private let persistence: any HighlightPersisting
    private let bookFingerprintKey: String
    private let jsBridge: FoliateHighlightJSBridge

    init(
        persistence: any HighlightPersisting,
        bookFingerprintKey: String,
        jsBridge: FoliateHighlightJSBridge = FoliateHighlightJSBridge()
    ) {
        self.persistence = persistence
        self.bookFingerprintKey = bookFingerprintKey
        self.jsBridge = jsBridge
    }

    /// The result of `refetch` — either the post-mutation record, or the
    /// `HighlightMutationOutcome` to return verbatim. A dedicated enum (not
    /// `Result`) because `Result`'s failure type must be an `Error` and
    /// `HighlightMutationOutcome` is not.
    private enum RefetchResult {
        case found(HighlightRecord)
        case outcome(HighlightMutationOutcome)
    }

    /// Re-fetches the book's highlights after a mutation and returns the one
    /// matching `highlightID`. Mirrors `HighlightCoordinator`'s R1-5 discipline:
    /// a fetch throw is a generic `.failed`; only a successful fetch with no
    /// match is `.notFound` (a concurrent-deletion race).
    private func refetch(_ highlightID: UUID) async -> RefetchResult {
        let records: [HighlightRecord]
        do {
            records = try await persistence.fetchHighlights(forBookWithKey: bookFingerprintKey)
        } catch {
            return .outcome(.failed)
        }
        guard let record = records.first(where: { $0.highlightId == highlightID }) else {
            return .outcome(.notFound)
        }
        return .found(record)
    }
}

// MARK: - HighlightMutating

extension FoliateHighlightMutator: HighlightMutating {

    /// Persists a new highlight color, then repaints the Foliate WKWebView
    /// overlay via `FoliateHighlightJSBridge.recolor` (the CFI-keyed
    /// delete-then-create JS pair). Returns a typed outcome so the popover
    /// distinguishes a deleted-record race (→ dismiss) from a generic failure
    /// (→ keep the popover open).
    func changeColor(highlightID: UUID, to color: String) async -> HighlightMutationOutcome {
        do {
            try await persistence.updateHighlightColor(highlightId: highlightID, color: color)
        } catch let error as PersistenceError {
            if case .recordNotFound = error { return .notFound }
            return .failed
        } catch {
            return .failed
        }

        switch await refetch(highlightID) {
        case let .outcome(outcome):
            return outcome
        case let .found(record):
            // Repaint the live overlay from the re-fetched record's OWN color,
            // not the caller's `color` argument — the repaint must reflect
            // post-mutation persisted state (the two are equal in normal use,
            // but this keeps the invariant explicit).
            jsBridge.recolor(
                record: record, to: record.color, fingerprintKey: bookFingerprintKey
            )
            return .success(record)
        }
    }

    /// Persists a note edit. No overlay repaint — a note is not drawn on the
    /// page, so the only UI to refresh is the popover card (handled by the
    /// caller). A trimmed-empty draft normalizes to `nil`.
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

        switch await refetch(highlightID) {
        case let .outcome(outcome):
            return outcome
        case let .found(record):
            return .success(record)
        }
    }

    /// Deletes a highlight from persistence, then strips the Foliate overlay
    /// via `FoliateHighlightJSBridge.delete` — which posts BOTH
    /// `.readerHighlightRemoved` (UUID — keeps the Annotations panel in sync)
    /// AND `.foliateRequestAnnotationJSDelete` (CFI — clears the SVG overlay).
    /// The record is fetched up front so a concurrent-deletion race is
    /// `.notFound` rather than collapsing into a generic `.failed`.
    func deleteHighlight(highlightID: UUID) async -> HighlightMutationOutcome {
        // Fetch up front — to return the record on `.success` and to
        // distinguish "already gone" (.notFound) from a fetch failure.
        let record: HighlightRecord
        switch await refetch(highlightID) {
        case let .outcome(outcome):
            return outcome
        case let .found(fetched):
            record = fetched
        }

        do {
            try await persistence.removeHighlight(highlightId: highlightID)
        } catch let error as PersistenceError {
            if case .recordNotFound = error { return .notFound }
            return .failed
        } catch {
            return .failed
        }

        // The bridge owns the `.readerHighlightRemoved` post — the mutator does
        // NOT post it itself (that would double-fire and desync the panel).
        jsBridge.delete(record: record, fingerprintKey: bookFingerprintKey)
        return .success(record)
    }
}
#endif
