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
// bridges have a single typed entry point (`post(selection:on:)`)
// and observers have a single typed read point
// (`selection(from:)`). Keeps the wire format local to the
// presenter and trivially unit-testable without SwiftUI / sheet
// lifecycle integration.
//
// @coordinates-with: SelectionPopoverView.swift,
//   SelectionPopoverActionRouter.swift,
//   ReaderNotifications.swift (.readerSelectionPopoverRequested),
//   TXTBridgeShared.swift (future WI-7c2 caller)

#if canImport(UIKit)
import SwiftUI

// MARK: - Request helper (wire format)

/// Pure-logic helpers for posting / parsing the
/// `.readerSelectionPopoverRequested` notification. Lets bridges
/// (the producer) and the presenter modifier (the consumer) agree
/// on a single typed entry point without re-introspecting
/// `Notification.object` everywhere.
@MainActor
enum SelectionPopoverRequest {

    /// Post a `.readerSelectionPopoverRequested` notification carrying
    /// the long-press selection as `notification.object`. Bridges
    /// call this immediately after their UIKit selection finalises
    /// (and before they would have built the legacy `UIMenu`).
    static func post(
        selection: TextSelectionInfo,
        on notificationCenter: NotificationCenter = .default
    ) {
        notificationCenter.post(
            name: .readerSelectionPopoverRequested,
            object: selection
        )
    }

    /// Extract the `TextSelectionInfo` payload from a notification.
    /// Returns nil if `notification.object` isn't the expected
    /// shape — defensive against a bridge mis-posting during
    /// development, not a runtime error.
    static func selection(from notification: Notification) -> TextSelectionInfo? {
        notification.object as? TextSelectionInfo
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
    /// returning the same `currentSelection` keeps it open
    /// (deferred — see plan v8 / Codex Gate 4 round 1 Medium:
    /// `.askAI` / `.read` have no production pipeline yet, auto-
    /// dismissing would silently swallow the tap).
    static func nextPending(
        after result: SelectionPopoverActionRouter.Result,
        currentSelection: TextSelectionInfo
    ) -> TextSelectionInfo? {
        switch result {
        case .dispatched:
            return nil
        case .deferredNotYetWired:
            return currentSelection
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
/// Attach with `.selectionPopoverPresenter(theme:)`. WI-7c1 commits
/// the modifier; per-bridge attach + post calls land per
/// WI-7c2..7c5.
private struct SelectionPopoverPresenterModifier: ViewModifier {
    let theme: ReaderThemeV2
    @State private var pending: TextSelectionInfo?

    /// Maps `pending != nil` to a `Bool` binding the sheet API
    /// requires. Setting to `false` clears the pending state —
    /// covers iOS-driven dismissal (drag-down, tap-outside) without
    /// a separate `onDismiss` callback.
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
                guard let selection = SelectionPopoverRequest.selection(from: note) else {
                    return
                }
                pending = selection
            }
            .sheet(isPresented: isPresentedBinding) {
                sheetContent
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let selection = pending {
            SelectionPopoverView(
                selectionText: selection.selectedText,
                theme: theme,
                onAction: { action in
                    let result = SelectionPopoverActionRouter.route(
                        action: action,
                        selection: selection
                    )
                    pending = SelectionPopoverDismissPolicy.nextPending(
                        after: result,
                        currentSelection: selection
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
    /// SwiftUI sheet. Production bridges start posting the
    /// notification per WI-7c2..7c5.
    func selectionPopoverPresenter(theme: ReaderThemeV2) -> some View {
        modifier(SelectionPopoverPresenterModifier(theme: theme))
    }
}

#endif
