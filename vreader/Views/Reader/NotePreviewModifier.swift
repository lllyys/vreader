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
            .sheet(item: $sheetContent, onDismiss: { dismissAll() }) { content in
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

    /// Routes a freshly-published `NotePreviewContent` to the callout or the
    /// sheet form. `nil` dismisses both.
    private func route(to content: NotePreviewContent?) {
        guard let content else {
            sheetContent = nil
            calloutPresenter.dismissCallout()
            return
        }
        let lineCount = NoteCalloutView.noteLineCount(for: content.note)
        let form = NotePreviewPresenter.form(
            for: content,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            noteLineCount: lineCount
        )
        switch form {
        case .sheet:
            calloutPresenter.dismissCallout()
            sheetContent = content
        case .callout:
            sheetContent = nil
            guard let host = hostViewProvider() else {
                // No host view — fall back to the sheet form so the user
                // still sees the note.
                sheetContent = content
                return
            }
            calloutPresenter.presentCallout(
                content,
                theme: theme,
                in: host,
                onAction: { action in handleHandoff(action, for: content) },
                onDismiss: { dismissAll() }
            )
        }
    }

    /// Handles a handoff-row action (Share / Open-in-panel).
    /// - Open-in-panel posts `.readerOpenNotes` — existing behavior, opens the
    ///   Annotations panel's Highlights tab.
    /// - Share presents the system share sheet (`UIActivityViewController`)
    ///   with the note text. Uses the standard iOS share; no new design
    ///   surface, no new notification. A note-less highlight has nothing to
    ///   share, so Share is a no-op there (the empty-state callout has no
    ///   handoff row anyway).
    /// Then the preview dismisses.
    private func handleHandoff(_ action: NoteCalloutAction, for content: NotePreviewContent) {
        switch action {
        case .openInPanel:
            NotificationCenter.default.post(name: .readerOpenNotes, object: nil)
            dismissAll()
        case .share:
            shareNote(content)
        }
    }

    /// Presents the system share sheet with the note text, anchored to the
    /// container's host view. The preview is dismissed first so the share
    /// sheet is not presented from a controller that is mid-dismiss.
    private func shareNote(_ content: NotePreviewContent) {
        let noteText = (content.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let host = hostViewProvider()
        dismissAll()
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

    /// Clears every preview surface and the view model state.
    private func dismissAll() {
        sheetContent = nil
        calloutPresenter.dismissCallout()
        viewModel.dismiss()
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
    /// popover's anchor. WI-6/WI-7 wire this per format.
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
}
#endif
