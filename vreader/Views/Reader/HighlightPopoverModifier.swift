// Purpose: Feature #64 WI-4 — the unified highlight-action popover's SwiftUI
// driver: `HighlightPopoverPresenting` (the anchored-card presenter protocol),
// `HighlightPopoverRequest` (the `.readerHighlightTapped` parse helper),
// `HighlightShareItem` + `HighlightActivityView` (the host-view-independent
// share channel), and `HighlightPopoverModifier` (the `ViewModifier`).
//
// The modifier observes `.readerHighlightTapped`, drives a
// `HighlightPopoverViewModel`, routes the published content to the anchored
// presenter (`.card`) or a SwiftUI `.sheet` (`.sheet`), owns the
// presenter-owned `mode` / `noteDraft` / `shareItem` `@State`, and dispatches
// `HighlightPopoverAction`s into `HighlightCoordinator` / the Foliate JS
// bridge / `UIPasteboard` / the share sheet.
//
// Supersedes feature #55's `NotePreviewModifier` (deleted in WI-10). The
// `HighlightPopoverPresenting` protocol is consumed here and realized by
// `UIKitHighlightPopoverPresenter` in WI-5.
//
// Key decisions:
// - The note draft is presenter-owned (`@State noteDraft`), reset whenever
//   the editor opens or the presented highlight swaps (R1-6).
// - `updateCard` is called whenever `mode` / `noteDraft` / `content` change
//   while the anchored card is live — an in-place `rootView` reassignment, no
//   dismiss+re-present, so the keyboard is preserved (R2-F6).
// - Share goes through a SwiftUI `.sheet(item:)` hosting `HighlightActivityView`
//   — host-view-independent, so it works whether or not a container supplies
//   a `hostViewProvider` (R2-F7).
//
// @coordinates-with: HighlightPopoverViewModel.swift, HighlightActionCardView.swift,
//   HighlightPopoverPresenter.swift, HighlightCoordinator.swift,
//   FoliateHighlightJSBridge.swift, UIKitHighlightPopoverPresenter.swift (WI-5),
//   ReaderNotifications.swift (.readerHighlightTapped)

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

// MARK: - Anchored-card presenter protocol

/// Presents the anchored `.card` form of the unified highlight popover.
/// Protocol so `HighlightPopoverModifier` is unit-testable against a fake;
/// realized by `UIKitHighlightPopoverPresenter` (WI-5).
///
/// R2-F6: the card is an *interactive* surface — while it stays on screen the
/// `mode` flips reading↔editing↔confirmingDelete, the `noteDraft` updates on
/// every keystroke, and after a recolor/save the `content` is rebuilt. So the
/// protocol exposes an explicit idempotent `updateCard` (an in-place
/// `rootView` reassignment, no modal transition) rather than forcing a
/// dismiss-and-re-present on every change.
@MainActor
protocol HighlightPopoverPresenting: AnyObject {
    /// Presents the anchored card. If a card is already presented for the
    /// same highlight (`content.id`), this is treated as an `updateCard`
    /// (idempotent — no flicker, keyboard preserved). A different `content.id`
    /// supersedes the prior card.
    func presentCard(
        _ content: HighlightPopoverContent,
        theme: ReaderThemeV2,
        mode: HighlightPopoverMode,
        noteDraft: String,
        pressedColor: NamedHighlightColor?,
        in view: UIView,
        onAction: @escaping (HighlightPopoverAction) -> Void,
        onDraftChange: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    )

    /// Updates the live card's `mode` / `noteDraft` / `content` /
    /// `pressedColor` in place by reassigning the hosting controller's
    /// `rootView` — NO dismiss, NO re-present. A no-op if no card is currently
    /// presented. `pressedColor` carries the design's transient swatch press
    /// feedback into the anchored card.
    func updateCard(
        content: HighlightPopoverContent,
        mode: HighlightPopoverMode,
        noteDraft: String,
        pressedColor: NamedHighlightColor?
    )

    /// Dismisses a currently-presented card, if any. `completion` runs after
    /// the dismissal finishes — or synchronously when nothing is presented.
    func dismissCard(completion: (@MainActor () -> Void)?)
}

extension HighlightPopoverPresenting {
    /// Dismiss with no completion — the common case.
    func dismissCard() { dismissCard(completion: nil) }
}

// MARK: - Request parse helper

/// Pure-logic helper for parsing the `.readerHighlightTapped` notification.
enum HighlightPopoverRequest {
    /// Extracts the `ReaderHighlightTapEvent` from a `.readerHighlightTapped`
    /// notification. Returns `nil` for a mis-posted / nil object — defensive.
    nonisolated static func event(from notification: Notification) -> ReaderHighlightTapEvent? {
        notification.object as? ReaderHighlightTapEvent
    }

    /// Feature #1121: extracts the `ReaderHighlightEditRequest` from a
    /// `.readerHighlightEditRequested` notification (the Edit-handoff auto-open).
    /// `nil` for a mis-posted / nil object.
    nonisolated static func editRequest(from notification: Notification) -> ReaderHighlightEditRequest? {
        notification.object as? ReaderHighlightEditRequest
    }
}

// MARK: - Share channel

/// A tiny `Identifiable` wrapper around the text to share — drives the
/// modifier's `.sheet(item:)` share channel (R2-F7).
struct HighlightShareItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// `UIViewControllerRepresentable` wrapping `UIActivityViewController` — the
/// host-view-independent share channel. SwiftUI owns the presentation, so it
/// works whether or not a container supplies a `hostViewProvider`. Mirrors
/// `ShareSheet.swift`'s `ShareActivityView`.
struct HighlightActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
