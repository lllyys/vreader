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

// MARK: - Outside-tap grace (Bug #351)

/// Pure-logic helper deciding whether an outside tap should dismiss the
/// card. Extracted so the grace contract is unit-testable without the
/// SwiftUI gesture lifecycle.
///
/// Bug #351: the #338 outside-tap dismissal is a simultaneous
/// `SpatialTapGesture` that fires on tap-up. The finger-up that COMPLETES
/// a word selection lands on the text — outside the bottom-anchored card —
/// so a quick release is recognised as an outside tap and dismisses the
/// card the instant it appears. (A lingering touch exceeds the tap
/// recogniser's threshold, never fires `onEnded`, and so the card
/// survives — which is the user-observed "only stays if the finger
/// lingers".) The grace window ignores any outside tap arriving within
/// `presentGrace` of the card being presented: that tap is the
/// selection's own release, not a deliberate dismissal. A genuine later
/// dismiss tap lands after the grace and still closes the card.
@MainActor
enum SelectionPopoverOutsideTapPolicy {

    /// How long after the card is presented an outside tap is treated as
    /// the selection's own release rather than a dismissal. Long enough
    /// to cover an instant finger-up after selection; short enough that a
    /// deliberate dismiss tap feels responsive.
    static let presentGrace: TimeInterval = 0.35

    /// Whether an outside tap at `tapTime` should dismiss a card
    /// presented at `presentedAt`. `false` within the grace window; a
    /// `nil` present-time falls back to dismissing (no grace to apply).
    static func shouldDismiss(
        presentedAt: Date?,
        tapTime: Date,
        grace: TimeInterval = presentGrace
    ) -> Bool {
        guard let presentedAt else { return true }
        return tapTime.timeIntervalSince(presentedAt) >= grace
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
    /// Bug #338 (Codex round-1 High): the card's frame in global space, kept
    /// fresh by the overlay's `onGeometryChange`. The outside-tap dismissal
    /// fires only for taps OUTSIDE this frame — a simultaneous recognizer on
    /// the content tree also sees taps that land on the overlay card, and
    /// dismissing on those would race the card's action handlers (the
    /// EPUB/Readium token cache is cleared by `onDismiss`).
    @State private var cardFrame: CGRect = .zero
    /// Bug #351: when the card was presented, so the outside-tap
    /// dismissal can ignore the selection's own terminal finger-up (which
    /// lands on the text within milliseconds of the card appearing). See
    /// `SelectionPopoverOutsideTapPolicy`.
    @State private var presentedAt: Date?

    func body(content: Content) -> some View {
        content
            // Bug #338: tap-outside-to-dismiss WITHOUT a hit-blocking overlay.
            // The old full-screen `Color.clear` tap-catcher swallowed EVERY
            // touch that wasn't a clean tap — selection-handle drags and reader
            // scrolling were dead while the card was up, so a selection could
            // never be refined. A SIMULTANEOUS TapGesture on the content
            // observes taps without claiming them: a tap dismisses the card AND
            // still reaches the reader (which clears its native selection — the
            // same end state as before); drags / pans / long-presses are not
            // taps, so handle refinement and scrolling flow to the underlying
            // UIKit views untouched. A completed handle drag makes the bridge
            // re-post `.readerSelectionPopoverRequested` (iOS re-requests the
            // edit menu; Readium re-fires `shouldShowMenuForSelection`), so the
            // card's quote refreshes to the expanded selection for free.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                guard pending != nil, !cardFrame.contains(value.location) else { return }
                // Bug #351: ignore the selection's own terminal finger-up
                // (lands on the text within ms of the card appearing) —
                // only a tap after the present-grace is a deliberate
                // dismissal.
                guard SelectionPopoverOutsideTapPolicy.shouldDismiss(
                    presentedAt: presentedAt, tapTime: Date()
                ) else { return }
                dismiss()
            })
            .onReceive(
                NotificationCenter.default.publisher(for: .readerSelectionPopoverRequested)
            ) { note in
                guard let payload = SelectionPopoverRequest.payload(from: note) else {
                    return
                }
                pending = payload
                // Bug #351: stamp the present time so the outside-tap
                // dismissal can grace-ignore the selection's own release.
                // A handle-drag re-post refreshes this, so the drag's
                // terminal up is graced too.
                presentedAt = Date()
                // Bug #338 (Codex round-2): while the card is up, the reader's
                // tap grammar is suppressed so the eventual outside tap is a
                // PURE dismissal (no page-turn away from the selected text).
                ReaderTapZoneRouter.selectionPopoverVisible = true
            }
            // Bug #317: present the designed FLOATING inset card — `left`/`right`
            // 18, ~100pt above the bottom, rounded (the card chrome lives in
            // `SelectionPopoverView`) — as an overlay, NOT a system `.sheet` with
            // detents + grabber + dimmed backdrop. Mirrors `vreader-reader.jsx`'s
            // `SelectionPopover` (`position:absolute; left:18; right:18; bottom:100;
            // borderRadius:18`). Shared modifier → all formats (TXT/MD/EPUB-Readium).
            .overlay(alignment: .bottom) {
                if let payload = pending {
                    floatingCard(payload)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pending != nil)
            // Codex round-3 Medium: if the reader unmounts while the popover
            // is visible, the global suppression must not leak into the next
            // reader session. Unconditional reset — no grace.
            .onDisappear {
                if pending != nil {
                    ReaderTapZoneRouter.selectionPopoverVisible = false
                    ReaderTapZoneRouter.dismissGraceDeadline = .distantPast
                }
            }
    }

    @ViewBuilder
    private func floatingCard(_ payload: SelectionPopoverRequestPayload) -> some View {
        // Bug #338: no ZStack tap-catcher — the card alone occupies the overlay,
        // so every touch outside its bounds reaches the live reader beneath
        // (handle drags, scrolling); tap-outside dismissal is handled by the
        // simultaneous gesture on the content above.
        SelectionPopoverView(
            selectionText: payload.selection.selectedText,
            theme: theme,
            onAction: { action in
                let result = SelectionPopoverActionRouter.route(
                    action: action,
                    payload: payload
                )
                let next = SelectionPopoverDismissPolicy.nextPending(
                    after: result,
                    currentPayload: payload
                )
                pending = next
                // Preserve the old `.sheet(onDismiss:)` contract: fire onDismiss
                // whenever the popover actually closes (here, the action path
                // resolved to no follow-up). Codex round-3 High: the action
                // path must also drop the tap-grammar suppression — with NO
                // dismissal grace (the action tap landed ON the card; there is
                // no in-flight reader tap to swallow).
                if next == nil {
                    ReaderTapZoneRouter.selectionPopoverVisible = false
                    onDismiss?()
                }
            },
            onClose: { dismiss() }
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 100)
        .background(
            // Track the card's global frame for the outside-tap exclusion
            // (Codex round-1 High). GeometryReader in a background reports
            // the framed card bounds without affecting layout.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cardFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.size) { _, _ in
                        cardFrame = proxy.frame(in: .global)
                    }
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Closes the popover by an outside tap or the close button, preserving the
    /// `onDismiss` callback the EPUB container uses to drop its token-cache entry.
    private func dismiss() {
        pending = nil
        presentedAt = nil
        releaseTapSuppression()
        onDismiss?()
    }

    /// Drops the popover-visible tap suppression, arming a short one-shot
    /// grace so the dismissing tap itself — whose bridge-side report arrives
    /// asynchronously AFTER this gesture — is also swallowed (Codex round-2:
    /// a side-zone dismiss tap must not page-turn away from the selection).
    private func releaseTapSuppression() {
        ReaderTapZoneRouter.selectionPopoverVisible = false
        ReaderTapZoneRouter.dismissGraceDeadline = Date().addingTimeInterval(0.4)
    }
}

extension View {
    /// Feature #60 WI-7c1: attach the SelectionPopover presenter to
    /// a reader-container view. The presenter observes
    /// `.readerSelectionPopoverRequested` (any object), filters
    /// invalid payloads, and presents `SelectionPopoverView` as the
    /// designed floating inset card (Bug #317 — overlay, not a system
    /// sheet). Production bridges post the notification per WI-7c2..7c5.
    ///
    /// `onDismiss` (WI-7c5b) fires whenever the popover closes — the
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
