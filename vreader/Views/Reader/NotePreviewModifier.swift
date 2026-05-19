// Purpose: Feature #55 WI-5 — `NotePreviewRequest` (the `.readerHighlightTapped`
// parse helper) and `NotePreviewModifier` (the SwiftUI `ViewModifier` that
// drives the note preview).
//
// Lives alongside `NotePreviewPresenter` (the pure enum) — kept in its own
// file because the modifier needs `SwiftUI`/`UIKit` while the pure enum is
// Foundation-only, and to keep each file under the ~300-line guideline.
//
// `NotePreviewModifier` observes `.readerHighlightTapped`, drives
// `NotePreviewViewModel.handleTap`, and routes the published
// `NotePreviewContent` to one of two forms per `NotePreviewPresenter.form`:
//   - `.callout` → the UIKit `NotePreviewPresenting` presenter, anchored to
//     the tap's `sourceRect` in the container's content `UIView`.
//   - `.sheet`   → a SwiftUI `.sheet` hosting `NotePreviewSheetView` (the
//     long-note / VoiceOver / Foliate path — no rect anchor needed).
//
// Mirrors `SelectionPopoverPresenterModifier`'s shape (notification → modifier
// → typed surface) for the sheet form; the callout form uses the #53-style
// UIKit presenter because a SwiftUI `.popover` cannot anchor to a raw rect
// (plan §2.7.1).
//
// @coordinates-with: NotePreviewPresenter.swift, NotePreviewViewModel.swift,
//   NotePreviewSheetView.swift, UIKitNotePreviewPresenter.swift,
//   NoteCalloutView.swift, ReaderNotifications.swift (.readerHighlightTapped)

#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - Request parse helper

/// Pure-logic helper for parsing the `.readerHighlightTapped` notification.
/// Lets the modifier (the consumer) read a single typed entry point without
/// re-introspecting `Notification.object` inline.
enum NotePreviewRequest {

    /// Extracts the `ReaderHighlightTapEvent` from a `.readerHighlightTapped`
    /// notification. Returns `nil` if `notification.object` is not a
    /// `ReaderHighlightTapEvent` (a bridge mis-posting, or a nil object) —
    /// defensive, not a runtime error.
    ///
    /// `nonisolated`: a pure parse over `Sendable` values
    /// (`ReaderHighlightTapEvent` is `Sendable`), callable from a synchronous
    /// `NotificationCenter` observer closure.
    nonisolated static func event(from notification: Notification) -> ReaderHighlightTapEvent? {
        notification.object as? ReaderHighlightTapEvent
    }
}

// MARK: - SwiftUI presenter modifier

/// Drives the note preview: observes `.readerHighlightTapped`, looks the
/// highlight up via `NotePreviewViewModel`, and presents the callout or the
/// sheet per `NotePreviewPresenter.form`.
private struct NotePreviewModifier: ViewModifier {

    /// The view model — owns the lookup + the published `presented` content.
    @State private var viewModel: NotePreviewViewModel

    /// The reader theme threaded into the callout / sheet.
    let theme: ReaderThemeV2

    /// The UIKit presenter for the anchored callout form. Injected so the
    /// modifier is testable; defaults to the real `UIPopoverPresentationController`
    /// presenter.
    @State private var calloutPresenter: any NotePreviewPresenting

    /// Resolves the reader's content `UIView` — the popover's `sourceView`.
    /// The container supplies this; `nil` (view not yet attached) falls back
    /// to the sheet form.
    let hostViewProvider: () -> UIView?

    /// The content currently driving the SwiftUI `.sheet` form. `nil` ⇒ no
    /// sheet. The callout form does NOT use this — it goes through the UIKit
    /// presenter.
    @State private var sheetContent: NotePreviewContent?

    /// An action to run AFTER the `.sheet` has finished dismissing — set by a
    /// sheet-form handoff so the follow-up surface (the Annotations panel, the
    /// share sheet) is presented only once the sheet's dismissal animation has
    /// completed. Run from `.sheet`'s `onDismiss` — the real completion hook,
    /// not a runloop guess (Codex Gate-4 round-2 High).
    @State private var pendingPostDismissAction: (@MainActor () -> Void)?

    init(
        viewModel: NotePreviewViewModel,
        theme: ReaderThemeV2,
        calloutPresenter: any NotePreviewPresenting,
        hostViewProvider: @escaping () -> UIView?
    ) {
        _viewModel = State(initialValue: viewModel)
        self.theme = theme
        _calloutPresenter = State(initialValue: calloutPresenter)
        self.hostViewProvider = hostViewProvider
    }

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .readerHighlightTapped)
            ) { note in
                guard let event = NotePreviewRequest.event(from: note) else { return }
                Task { await viewModel.handleTap(event) }
            }
            .onChange(of: viewModel.presented) { _, newValue in
                route(to: newValue)
            }
            .sheet(item: $sheetContent, onDismiss: { runPendingPostDismissAction() }) { content in
                NotePreviewSheetView(
                    content: content,
                    theme: theme,
                    onAction: { action in handleHandoff(action, for: content) },
                    onDismiss: { dismissAll() }
                )
                .presentationDetents([.fraction(0.42), .large])
                .presentationDragIndicator(.visible)
            }
    }

    /// Runs (and clears) the stashed post-dismiss action. Called from the
    /// `.sheet`'s `onDismiss` — by which point SwiftUI has fully dismissed the
    /// sheet, so a follow-up surface can be presented with no modal collision.
    /// On a plain dismiss (no handoff) the action is `nil` and this also
    /// clears the view-model state.
    private func runPendingPostDismissAction() {
        let action = pendingPostDismissAction
        pendingPostDismissAction = nil
        if let action {
            action()
        } else {
            // Plain sheet dismissal (drag-down, Done) — clear VM state.
            viewModel.dismiss()
        }
    }

    /// Routes a freshly-published `NotePreviewContent` to the callout or the
    /// sheet form. `nil` dismisses both. Every transition first tears down the
    /// other form so two surfaces can never stack — and the `.callout`
    /// presenter itself serializes a callout→callout replacement through its
    /// own dismiss completion (`UIKitNotePreviewPresenter`).
    private func route(to content: NotePreviewContent?) {
        guard let content else {
            sheetContent = nil
            calloutPresenter.dismissCallout()
            return
        }
        let host = hostViewProvider()
        let lineCount = NoteCalloutView.noteLineCount(for: content.note)
        // `resolvedForm` folds in the host-availability fact: a callout with
        // no host UIView to anchor to degrades to the sheet (unit-tested).
        let form = NotePreviewPresenter.resolvedForm(
            for: content,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            noteLineCount: lineCount,
            hasHostView: host != nil
        )
        switch form {
        case .sheet:
            // Tear down any live callout before showing the sheet.
            calloutPresenter.dismissCallout()
            sheetContent = content
        case .callout:
            guard let host else {
                // `resolvedForm` returns `.callout` only when `hasHostView`
                // is true, so this is unreachable — but fall back safely.
                calloutPresenter.dismissCallout()
                sheetContent = content
                return
            }
            // Tear down the sheet (if showing), then present the callout.
            // The presenter handles a callout→callout supersede internally.
            sheetContent = nil
            calloutPresenter.presentCallout(
                content,
                theme: theme,
                in: host,
                onAction: { action in handleHandoff(action, for: content) },
                onDismiss: { dismissAll() }
            )
        }
    }

    /// Handles a handoff-row action (Share / Open-in-panel). Both follow-up
    /// surfaces (the Annotations panel, the share sheet) must NOT be presented
    /// while the note preview is still being dismissed — a modal collision
    /// drops the follow-up. So the preview is dismissed first and the
    /// side-effect runs only from the dismiss completion:
    /// - Open-in-panel posts `.readerOpenNotes` (existing behavior — opens the
    ///   Annotations panel's Highlights tab).
    /// - Share presents the system `UIActivityViewController` with the note
    ///   text. Standard iOS share — no new design surface, no new
    ///   notification. A note-less highlight has nothing to share (and the
    ///   empty-state callout has no handoff row anyway).
    private func handleHandoff(_ action: NoteCalloutAction, for content: NotePreviewContent) {
        let host = hostViewProvider()
        dismissPreview {
            switch action {
            case .openInPanel:
                NotificationCenter.default.post(name: .readerOpenNotes, object: nil)
            case .share:
                Self.presentShareSheet(for: content, anchoredTo: host)
            }
        }
    }

    /// Presents the system share sheet with the note text. A no-op when there
    /// is no note text or no host to anchor to.
    private static func presentShareSheet(
        for content: NotePreviewContent, anchoredTo host: UIView?
    ) {
        let noteText = (content.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noteText.isEmpty,
              let host,
              let presenter = host.nearestViewController else { return }
        let activity = UIActivityViewController(
            activityItems: [noteText], applicationActivities: nil
        )
        // iPad / popover-class presentation needs an anchor.
        activity.popoverPresentationController?.sourceView = host
        activity.popoverPresentationController?.sourceRect = content.sourceRect
        presenter.present(activity, animated: true)
    }

    /// Tears down whichever preview form is showing and runs `completion`
    /// once the teardown finishes — so a follow-up surface is presented only
    /// after the preview's dismissal has completed (no modal collision).
    ///
    /// - Sheet form: stashes `completion` in `pendingPostDismissAction` and
    ///   clears `sheetContent`. SwiftUI dismisses the sheet and fires
    ///   `.sheet`'s `onDismiss`, which runs the stashed action — a real
    ///   dismissal-completion hook, not a runloop guess.
    /// - Callout form: `UIKitNotePreviewPresenter.dismissCallout(completion:)`
    ///   already runs `completion` from the popover's real dismiss completion.
    private func dismissPreview(then completion: @escaping @MainActor () -> Void) {
        viewModel.dismiss()
        if sheetContent != nil {
            // The completion runs from `.sheet`'s `onDismiss`. `viewModel`
            // state is already cleared above; the stashed action wraps the
            // caller's follow-up only (the `onDismiss` path sees a non-nil
            // action and skips its own `viewModel.dismiss()`).
            pendingPostDismissAction = completion
            sheetContent = nil
        } else {
            // Callout form — the presenter's completion fires post-dismiss.
            calloutPresenter.dismissCallout(completion: completion)
        }
    }

    /// Clears every preview surface and the view model state. Used by the
    /// plain dismiss paths (× button, scrim tap, sheet drag-down, a `nil`
    /// route) where no follow-up surface needs to be presented.
    ///
    /// For the sheet form, clearing `sheetContent` triggers `.sheet`'s
    /// `onDismiss` → `runPendingPostDismissAction`, which (with no stashed
    /// action) clears the view-model state itself — so this method does not
    /// double-dismiss the view model on the sheet path.
    private func dismissAll() {
        if sheetContent != nil {
            // Sheet path — `onDismiss` will clear the VM. Just drop the sheet.
            pendingPostDismissAction = nil
            sheetContent = nil
        } else {
            calloutPresenter.dismissCallout()
            viewModel.dismiss()
        }
    }
}

// MARK: - View attach point

extension View {
    /// Feature #55 WI-5: attach the note-preview presenter to a reader
    /// container. The modifier observes `.readerHighlightTapped`, resolves the
    /// tapped highlight's note, and presents the anchored `NoteCalloutView`
    /// (via the UIKit presenter) or `NotePreviewSheetView` (via `.sheet`).
    ///
    /// `hostViewProvider` returns the container's content `UIView` — the
    /// popover's anchor; returning `nil` makes the preview use the bottom-sheet
    /// form (`NotePreviewPresenter.resolvedForm` degrades a callout with no
    /// host).
    func notePreviewPresenter(
        viewModel: NotePreviewViewModel,
        theme: ReaderThemeV2,
        calloutPresenter: any NotePreviewPresenting = UIKitNotePreviewPresenter(),
        hostViewProvider: @escaping () -> UIView?
    ) -> some View {
        modifier(
            NotePreviewModifier(
                viewModel: viewModel,
                theme: theme,
                calloutPresenter: calloutPresenter,
                hostViewProvider: hostViewProvider
            )
        )
    }

    /// Feature #55 WI-6: container-friendly attach point. Builds the
    /// `NotePreviewViewModel` from a `HighlightLookup` + the open book's
    /// `fingerprintKey` — the reader containers have both in scope and would
    /// otherwise hand-roll the view model. The modifier's `@State` keeps the
    /// view model stable across renders.
    ///
    /// `hostViewProvider` defaults to `{ nil }` — the native containers
    /// (TXT/MD/PDF) present the note preview via the bottom-sheet form in v1;
    /// the anchored-callout-for-native enhancement (which needs a host-`UIView`
    /// capture channel through the bridges) is a follow-up. Foliate likewise
    /// has no anchor (`sourceRect == .zero`).
    func notePreviewPresenter(
        highlightLookup: any HighlightLookup,
        bookFingerprintKey: String,
        theme: ReaderThemeV2,
        hostViewProvider: @escaping () -> UIView? = { nil }
    ) -> some View {
        notePreviewPresenter(
            viewModel: NotePreviewViewModel(
                persistence: highlightLookup,
                bookFingerprintKey: bookFingerprintKey
            ),
            theme: theme,
            hostViewProvider: hostViewProvider
        )
    }
}
#endif
