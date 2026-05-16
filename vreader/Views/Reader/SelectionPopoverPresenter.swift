// Purpose: Feature #60 WI-7c1 — SwiftUI infrastructure for presenting
// `SelectionPopoverView` (WI-7a) in response to a long-press
// selection. Sits between the reader bridges (TXT non-chunked /
// TXT chunked / MD / EPUB) — which will post
// `.readerSelectionPopoverRequested` in WI-7c2..7c5 — and the
// `SelectionPopoverActionRouter` (WI-7b) that dispatches tapped
// actions to the existing `.readerHighlightRequested` /
// `.readerAnnotationRequested` / `.readerTranslateRequested`
// notification surface.
//
// **WI-7c1 ships infrastructure only.** No production bridge has
// been swapped to post `.readerSelectionPopoverRequested` yet; the
// legacy `TXTBridgeShared.buildReaderEditMenu` `UIMenu` still drives
// long-press in all bridges. WI-7c2..7c5 land the per-bridge swap.
//
// **Why parse + post helpers in a small enum**: mirrors the
// `FoliateSelectionDispatcher` / `FoliateMessageParser` pattern so
// bridges have a single typed entry point
// (`post(selection:on:requestToken:)`) and observers have a single
// typed read point (`payload(from:)`). Keeps the wire format local
// to the presenter and trivially unit-testable without SwiftUI /
// sheet lifecycle integration.
//
// **WI-7c5a**: the notification `object` is a typed
// `SelectionPopoverRequestPayload` (selection + optional
// `requestToken`), not a bare `TextSelectionInfo`. The token lets
// EPUB (WI-7c5b) round-trip a non-UTF-16 selection identity.
// `payload(from:)` still decodes a legacy bare `TextSelectionInfo`
// as a tokenless payload, so the change is not a flag-day break.
//
// @coordinates-with: SelectionPopoverView.swift,
//   SelectionPopoverActionRouter.swift,
//   ReaderNotifications.swift (.readerSelectionPopoverRequested),
//   TXTBridgeShared.swift (future WI-7c2 caller)

#if canImport(UIKit)
import SwiftUI

// MARK: - Request payload (wire format — WI-7c5a)

/// Typed payload carried as `notification.object` on
/// `.readerSelectionPopoverRequested`. Bundles the long-press
/// `selection` with an optional `requestToken`.
///
/// **Why the token**: TXT / MD / chunked all anchor a selection by
/// UTF-16 offsets (`TextSelectionInfo.startUTF16` / `.endUTF16`), so
/// the selection *is* its own identity. EPUB (WI-7c5b) anchors by a
/// DOM-path `EPUBSerializedRange` that `TextSelectionInfo` cannot
/// carry — so the EPUB container mints a `UUID` per selection,
/// stashes the real `ReaderSelectionEvent` under it, and posts the
/// token here. The token round-trips through
/// `SelectionPopoverActionRouter` into the action notification's
/// `userInfo`, letting the EPUB consumer resolve which cached
/// selection an action belongs to. TXT / MD / chunked leave it
/// `nil`; the token is dormant for them.
struct SelectionPopoverRequestPayload: Equatable, Sendable {
    let selection: TextSelectionInfo
    let requestToken: UUID?
}

// MARK: - Request helper (wire format)

/// Pure-logic helpers for posting / parsing the
/// `.readerSelectionPopoverRequested` notification. Lets bridges
/// (the producer) and the presenter modifier (the consumer) agree
/// on a single typed entry point without re-introspecting
/// `Notification.object` everywhere.
@MainActor
enum SelectionPopoverRequest {

    /// Post a `.readerSelectionPopoverRequested` notification carrying
    /// a `SelectionPopoverRequestPayload` as `notification.object`.
    /// Bridges call this immediately after their UIKit selection
    /// finalises (and before they would have built the legacy
    /// `UIMenu`). `requestToken` defaults to `nil` — only EPUB
    /// (WI-7c5b) supplies one.
    static func post(
        selection: TextSelectionInfo,
        on notificationCenter: NotificationCenter = .default,
        requestToken: UUID? = nil
    ) {
        let payload = SelectionPopoverRequestPayload(
            selection: selection,
            requestToken: requestToken
        )
        notificationCenter.post(
            name: .readerSelectionPopoverRequested,
            object: payload
        )
    }

    /// Extract the `SelectionPopoverRequestPayload` from a
    /// notification. Migration-safe: a producer that still posts a
    /// bare `TextSelectionInfo` (the pre-WI-7c5a wire shape) decodes
    /// as a tokenless payload. Returns nil if `notification.object`
    /// is neither shape — defensive against a bridge mis-posting
    /// during development, not a runtime error.
    ///
    /// `nonisolated`: a pure parse over `Sendable` inputs/outputs
    /// (`SelectionPopoverRequestPayload` + `TextSelectionInfo` are
    /// both `Sendable`). It must be callable from a synchronous
    /// `NotificationCenter` observer closure — a non-isolated
    /// `@Sendable` context — without "sending `note` risks data
    /// races". The enclosing enum stays `@MainActor` for `post`,
    /// whose callers are all main-actor bridges.
    nonisolated static func payload(from notification: Notification) -> SelectionPopoverRequestPayload? {
        if let payload = notification.object as? SelectionPopoverRequestPayload {
            return payload
        }
        if let selection = notification.object as? TextSelectionInfo {
            return SelectionPopoverRequestPayload(selection: selection, requestToken: nil)
        }
        return nil
    }
}

// MARK: - Dismiss policy (Codex Gate 4 round 1, Medium)

/// Pure-logic helper that decides whether the sheet should dismiss
/// after a router result. Extracted so the contract can be unit-
/// tested without SwiftUI sheet lifecycle integration.
@MainActor
enum SelectionPopoverDismissPolicy {

    /// What value `pending` should take after `router.route(...)`
    /// returns `result`. `nil` clears the sheet (dispatched);
    /// returning the same `currentPayload` keeps it open
    /// (deferred — see plan v8 / Codex Gate 4 round 1 Medium:
    /// `.askAI` / `.read` have no production pipeline yet, auto-
    /// dismissing would silently swallow the tap).
    static func nextPending(
        after result: SelectionPopoverActionRouter.Result,
        currentPayload: SelectionPopoverRequestPayload
    ) -> SelectionPopoverRequestPayload? {
        switch result {
        case .dispatched:
            return nil
        case .deferredNotYetWired:
            return currentPayload
        }
    }
}

// MARK: - SwiftUI presenter modifier

/// Observes `.readerSelectionPopoverRequested`, stashes the latest
/// selection in `@State`, and presents `SelectionPopoverView` as a
/// SwiftUI sheet. Tapped actions route through
/// `SelectionPopoverActionRouter` (which posts the existing reader-
/// notification surface); the close button + sheet dismiss clear
/// the pending state.
///
/// Attach with `.selectionPopoverPresenter(theme:onDismiss:)`. WI-7c1
/// committed the modifier; per-bridge attach + post calls landed per
/// WI-7c2..7c5. WI-7c5b added `onDismiss` so the EPUB container can
/// drop its token-cache entry when a popover closes without an
/// action (a tokenless TXT/MD attach simply omits the closure).
private struct SelectionPopoverPresenterModifier: ViewModifier {
    let theme: ReaderThemeV2
    /// Called when the sheet closes by any means (close button,
    /// drag-down, tap-outside, or after a dispatched action). WI-7c5b:
    /// the EPUB container uses this to `clear()` its
    /// `EPUBSelectionTokenCache` so an abandoned selection doesn't
    /// linger. Safe on the dispatch path too — by then the cache is
    /// already consumed, so `clear()` is an idempotent no-op.
    let onDismiss: (() -> Void)?
    @State private var pending: SelectionPopoverRequestPayload?

    /// Maps `pending != nil` to a `Bool` binding the sheet API
    /// requires. Setting to `false` clears the pending state —
    /// covers iOS-driven dismissal (drag-down, tap-outside).
    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { presenting in
                if !presenting { pending = nil }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .readerSelectionPopoverRequested)
            ) { note in
                guard let payload = SelectionPopoverRequest.payload(from: note) else {
                    return
                }
                pending = payload
            }
            .sheet(isPresented: isPresentedBinding, onDismiss: { onDismiss?() }) {
                sheetContent
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let payload = pending {
            SelectionPopoverView(
                selectionText: payload.selection.selectedText,
                theme: theme,
                onAction: { action in
                    let result = SelectionPopoverActionRouter.route(
                        action: action,
                        payload: payload
                    )
                    pending = SelectionPopoverDismissPolicy.nextPending(
                        after: result,
                        currentPayload: payload
                    )
                },
                onClose: { pending = nil }
            )
            .padding(.horizontal, 16)
            .presentationDetents([.fraction(0.30), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
    }
}

extension View {
    /// Feature #60 WI-7c1: attach the SelectionPopover presenter to
    /// a reader-container view. The presenter observes
    /// `.readerSelectionPopoverRequested` (any object), filters
    /// invalid payloads, and presents `SelectionPopoverView` as a
    /// SwiftUI sheet. Production bridges post the notification per
    /// WI-7c2..7c5.
    ///
    /// `onDismiss` (WI-7c5b) fires whenever the sheet closes — the
    /// EPUB container passes `{ selectionTokenCache.clear() }` so an
    /// abandoned long-press selection doesn't linger. TXT / MD /
    /// chunked carry their selection identity in `TextSelectionInfo`
    /// itself and omit the closure.
    func selectionPopoverPresenter(
        theme: ReaderThemeV2,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(SelectionPopoverPresenterModifier(theme: theme, onDismiss: onDismiss))
    }
}

#endif
