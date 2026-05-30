// Purpose: Pure routing for Feature #1121 — the HighlightsSheet "Edit" handoff.
// Decides, for an `AnnotationStreamItem`, what the post-navigation auto-open
// should do: a highlight requests the per-format reader bridge to re-open its
// in-reader editor (`ReaderHighlightEditRequest`, observed + resolved after the
// highlight re-renders), a standalone note opens its standalone editor.
//
// Lifted out of the SwiftUI sheet so the routing + payload construction are
// unit-testable without a view. The actual notification post / editor
// presentation (WI-2/WI-3) is bridge/UI wiring keyed on this decision.
//
// @coordinates-with: HighlightsSheet+Delete.swift (edit handoff), ReaderNotifications.swift
//   (ReaderHighlightEditRequest / .readerHighlightEditRequested)

import Foundation

enum HighlightEditHandoff {

    /// What the Edit handoff should do AFTER the navigate-to-passage jump.
    enum Action: Equatable {
        /// A highlight — ask the per-format bridge to auto-open the in-reader
        /// highlight editor once the highlight re-renders at the new position.
        case requestHighlightEdit(ReaderHighlightEditRequest)
        /// A standalone note — open its standalone editor (no anchored passage).
        case openStandaloneNote(annotationID: UUID)
    }

    /// The routing decision for `item`. `bookFingerprintKey` scopes the request
    /// to the open book; `token` is the single-flight handle (a newer Edit
    /// supersedes an older one).
    static func action(
        for item: AnnotationStreamItem,
        bookFingerprintKey: String,
        token: UUID
    ) -> Action {
        switch item {
        case .highlight(let record):
            return .requestHighlightEdit(ReaderHighlightEditRequest(
                highlightID: record.highlightId,
                bookFingerprintKey: bookFingerprintKey,
                token: token
            ))
        case .standalone(let record):
            return .openStandaloneNote(annotationID: record.annotationId)
        }
    }
}
