// Purpose: Feature #60 WI-7b — pure-logic router mapping a
// `SelectionPopoverAction` (WI-3 dispatch enum) to the existing
// reader-bridge notification surface.
//
// The router is the glue between WI-7a's `SelectionPopoverView`
// (which surfaces 4 color buttons + 4 action buttons) and the
// production pipelines that already consume
// `.readerHighlightRequested`, `.readerAnnotationRequested`, and
// `.readerTranslateRequested`. WI-7c will plumb the production
// long-press path (TXT non-chunked → chunked → MD → EPUB) through
// `SelectionPopoverView` and call this router on each tap.
//
// **Why pure-logic, not a method on the view**: the dispatch logic
// must be testable without UIKit or NotificationCenter globals.
// Embedding it in a `View` body or `Coordinator` makes the contract
// untestable except through fragile UI scaffolding. The router is
// `@MainActor`-isolated (matches its callers) and accepts an
// injectable `NotificationCenter` so tests can use an isolated
// instance.
//
// **Deferred actions (`.askAI`, `.read`)**: no production
// notification surface exists for these yet — the WI-3 enum was
// shipped ahead of consumers per the design's "Ask AI" /
// "Read aloud" requirements (Feature #60 acceptance criterion (d)).
// Rather than silently no-op, the router returns
// `.deferredNotYetWired(action)` so a regression-finding audit can
// distinguish "router skipped on purpose" from "router dropped a
// notification".
//
// @coordinates-with: SelectionPopoverAction.swift,
//   SelectionPopoverActionRow.swift, SelectionPopoverView.swift,
//   ReaderNotifications.swift, TextSelectionInfo

import Foundation

@MainActor
enum SelectionPopoverActionRouter {

    /// What the router did with the action. Discriminates the
    /// dispatched-vs-deferred outcomes so the caller (and tests)
    /// can act on the result without re-deriving it.
    enum Result: Equatable {
        /// Router posted the named notification on the supplied
        /// center. `name` lets the caller assert against the
        /// expected pipeline.
        case dispatched(Notification.Name)

        /// Action has no production consumer in this feature
        /// iteration yet. Carries the action for forward-trace
        /// when WI-7c+ wires `.askAI` / `.read` to their pipelines.
        case deferredNotYetWired(SelectionPopoverAction)
    }

    /// Map a `SelectionPopoverAction` to the existing reader-
    /// notification surface and post it on `notificationCenter`.
    /// Returns a `Result` describing what happened so callers can
    /// drive UI affordances (toast for deferred, etc.) without
    /// re-introspecting the enum.
    ///
    /// `.highlight(color)` adds the chosen
    /// `NamedHighlightColor.rawValue` to the notification's
    /// `userInfo` under `"color"`. Existing observers that ignore
    /// `userInfo` fall back to the default `"yellow"` color in the
    /// downstream pipeline; new observers (WI-7c forward) can
    /// honor the chosen color.
    ///
    /// **WI-7c5a**: takes a `SelectionPopoverRequestPayload` rather
    /// than a bare `TextSelectionInfo`. When the payload carries a
    /// `requestToken`, it rides the action notification's `userInfo`
    /// under `"selectionRequestToken"` as a `UUID` — letting EPUB
    /// (WI-7c5b) resolve which cached selection an action belongs
    /// to. The posted `object` stays a bare `TextSelectionInfo` so
    /// the TXT / MD `ReaderNotificationModifier` consumers are
    /// unaffected. A tokenless payload (TXT / MD / chunked) attaches
    /// no token key.
    @discardableResult
    static func route(
        action: SelectionPopoverAction,
        payload: SelectionPopoverRequestPayload,
        notificationCenter: NotificationCenter = .default
    ) -> Result {
        let selection = payload.selection
        switch action {
        case .highlight(let color):
            notificationCenter.post(
                name: .readerHighlightRequested,
                object: selection,
                userInfo: makeUserInfo(token: payload.requestToken, color: color.rawValue)
            )
            return .dispatched(.readerHighlightRequested)
        case .note:
            notificationCenter.post(
                name: .readerAnnotationRequested,
                object: selection,
                userInfo: makeUserInfo(token: payload.requestToken, color: nil)
            )
            return .dispatched(.readerAnnotationRequested)
        case .translate:
            notificationCenter.post(
                name: .readerTranslateRequested,
                object: selection,
                userInfo: makeUserInfo(token: payload.requestToken, color: nil)
            )
            return .dispatched(.readerTranslateRequested)
        case .askAI, .read:
            // Deferred — no consumer exists in this iteration. The
            // SelectionPopoverActionRow contract (WI-7a) surfaces
            // these slots; the production wire-up to AI sheet
            // (`.askAI`) and TTS-from-selection (`.read`) lands in
            // a later WI of feature #60.
            return .deferredNotYetWired(action)
        }
    }

    /// Build the action notification's `userInfo`, attaching the
    /// request token and/or color only when present. Returns `nil`
    /// when neither applies — preserving the pre-WI-7c5a contract
    /// that a tokenless `.note` / `.translate` posts no `userInfo`
    /// at all.
    private static func makeUserInfo(
        token: UUID?,
        color: String?
    ) -> [AnyHashable: Any]? {
        var info: [AnyHashable: Any] = [:]
        if let token { info["selectionRequestToken"] = token }
        if let color { info["color"] = color }
        return info.isEmpty ? nil : info
    }
}
