// Purpose: Bug #207 / GH #765 — pure-logic helper that fans an array
// of `HighlightRecord`s out as per-CFI `.foliateRequestAnnotationJSCreate`
// notifications.
//
// Sits between the SwiftUI restore modifier (`FoliateSpikeView+
// Restore.swift`) — which holds `@Environment(\.modelContext)` and
// queries persistence — and the `FoliateSpikeView.Coordinator`'s
// existing `.foliateRequestAnnotationJSCreate` observer that holds
// the live `WKWebView`. Keeping this routing in a pure-logic helper
// (rather than inline in the modifier) makes the contract testable
// without SwiftUI / WKWebView / NotificationCenter globals.
//
// **Why per-CFI rather than batched JS string**: the existing
// Coordinator observer already accepts the `(cfi, color)` shape
// (from Bug #201). Reusing it avoids a parallel "batch restore"
// observer + JS path and keeps the bridge surface small. The cost
// is one notification per CFI — typically <50 highlights per book,
// fired on each section's `create-overlay`, so still trivial.
//
// **Idempotency**: Foliate's `addAnnotation` is idempotent on the
// JS side (view.js:387 `overlayer.remove(value)` precedes add), so
// refiring per section is safe.
//
// @coordinates-with: FoliateSpikeView.swift (Coordinator observer),
//   ReaderNotifications.swift (.foliateRequestAnnotationJSCreate +
//   .foliateOverlayReadyForSection), HighlightRecord.swift,
//   AnnotationAnchor.swift

import Foundation

@MainActor
enum FoliateHighlightRestoreDispatcher {

    /// Fan a list of saved highlights out as per-CFI
    /// `.foliateRequestAnnotationJSCreate` notifications. The
    /// Coordinator's existing observer (filtered by `fingerprintKey`)
    /// evaluates each one against the live WKWebView.
    ///
    /// - Returns: the number of notifications dispatched, primarily
    ///   for testability.
    ///
    /// Skips:
    /// - Highlights whose anchor is not `.epub(_, cfi, _)` — TXT/MD
    ///   text anchors and PDF page anchors can't be routed through
    ///   Foliate-js's CFI-keyed overlayer.
    /// - Highlights whose CFI is empty / whitespace-only — defense-
    ///   in-depth against pre-Bug-#201-parse-fix data that may have
    ///   persisted (the Coordinator observer also rejects these).
    /// - The entire call if `fingerprintKey` is empty — mirrors
    ///   `FoliateSelectionDispatcher`'s identity guard: an empty
    ///   identity is meaningless for routing.
    @discardableResult
    static func dispatch(
        highlights: [HighlightRecord],
        fingerprintKey: String,
        notificationCenter: NotificationCenter = .default
    ) -> Int {
        guard !fingerprintKey.isEmpty else { return 0 }

        var dispatched = 0
        for highlight in highlights {
            guard case let .epub(_, cfi, _) = highlight.anchor else { continue }
            guard !cfi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            notificationCenter.post(
                name: .foliateRequestAnnotationJSCreate,
                object: nil,
                userInfo: [
                    "cfi": cfi,
                    "color": highlight.color,
                    "fingerprintKey": fingerprintKey,
                ]
            )
            dispatched += 1
        }
        return dispatched
    }
}
