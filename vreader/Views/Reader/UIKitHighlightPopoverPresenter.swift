// Purpose: Feature #64 WI-4/WI-5 — `UIKitHighlightPopoverPresenter`, the
// `UIPopoverPresentationController`-based realization of
// `HighlightPopoverPresenting` for the anchored `.card` form.
//
// A SwiftUI `.popover` cannot anchor to a raw `CGRect` (it needs a SwiftUI
// source view), so the anchored card is presented by a UIKit presenter that
// anchors a `UIHostingController` (hosting `HighlightActionCardView`) as a
// `.popover`-style `modalPresentationStyle` whose
// `popoverPresentationController.sourceView` is the reader's content `UIView`
// and `sourceRect` is the tap's `sourceRect`. Mirrors feature #55's
// `UIKitNotePreviewPresenter`.
//
// R2-F6 — the card is interactive, so this presenter carries an explicit
// idempotent `updateCard`: it reassigns the held `UIHostingController.rootView`
// in place (a cheap SwiftUI diff, no modal transition, keyboard preserved)
// rather than forcing a dismiss-and-re-present on every `mode` / `noteDraft`
// change. A `presentCard` for an already-presented same-`content.id` is itself
// treated as an `updateCard`.
//
// A single serialized present/dismiss pipeline (idle / presenting /
// dismissing) guards modal collisions under rapid taps — only the latest
// stashed request is honored.
//
// @coordinates-with: HighlightActionCardView.swift, HighlightPopoverContent.swift,
//   HighlightPopoverMode.swift, HighlightPopoverModifier.swift
//   (HighlightPopoverPresenting)

#if canImport(UIKit)
import UIKit
import SwiftUI

/// `UIPopoverPresentationController`-based realization of
/// `HighlightPopoverPresenting`. Serialized present/dismiss; in-place
/// `updateCard`.
@MainActor
final class UIKitHighlightPopoverPresenter: NSObject, HighlightPopoverPresenting {

    /// A present request — stashed while the pipeline is busy.
    private struct CardRequest {
        let content: HighlightPopoverContent
        let theme: ReaderThemeV2
        let mode: HighlightPopoverMode
        let noteDraft: String
        let pressedColor: NamedHighlightColor?
        let view: UIView
        let onAction: (HighlightPopoverAction) -> Void
        let onDraftChange: (String) -> Void
        let onDismiss: () -> Void
    }

    private enum Phase { case idle, presenting, dismissing }

    private var phase: Phase = .idle
    /// The hosting controller of the presented card. Weak — the presenting
    /// view-controller hierarchy retains it while presented.
    private weak var presentedHost: UIHostingController<HighlightActionCardView>?
    /// The `content.id` of the live card — `presentCard` for the same id is
    /// an `updateCard`.
    private var presentedContentID: UUID?
    /// The live card's action / draft / dismiss callbacks — reused by
    /// `updateCard` so an in-place `rootView` swap keeps the same funnels.
    private var liveCallbacks: (
        onAction: (HighlightPopoverAction) -> Void,
        onDraftChange: (String) -> Void,
        onDismiss: () -> Void
    )?
    private var liveTheme: ReaderThemeV2?
    private var popoverDelegate: HighlightPopoverDelegate?
    /// The LATEST present request stashed while the pipeline is busy.
    private var pendingRequest: CardRequest?
    private var pendingDismissCompletions: [@MainActor () -> Void] = []

    // MARK: - HighlightPopoverPresenting

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
    ) {
        // Idempotent: a present for the already-live highlight is an update,
        // not a dismiss-re-present (R2-F6 — no flicker, keyboard preserved).
        if phase == .presenting, presentedContentID == content.id {
            updateCard(
                content: content, mode: mode, noteDraft: noteDraft,
                pressedColor: pressedColor
            )
            return
        }
        let request = CardRequest(
            content: content, theme: theme, mode: mode, noteDraft: noteDraft,
            pressedColor: pressedColor, view: view, onAction: onAction,
            onDraftChange: onDraftChange, onDismiss: onDismiss
        )
        switch phase {
        case .idle:
            performPresent(request)
        case .presenting:
            // A different highlight supersedes — dismiss, then present.
            pendingRequest = request
            beginDismiss()
        case .dismissing:
            pendingRequest = request
        }
    }

    func updateCard(
        content: HighlightPopoverContent,
        mode: HighlightPopoverMode,
        noteDraft: String,
        pressedColor: NamedHighlightColor?
    ) {
        // In-place `rootView` reassignment — no dismiss, no re-present. A
        // no-op when nothing is presented.
        guard phase == .presenting,
              let host = presentedHost,
              let callbacks = liveCallbacks,
              let theme = liveTheme else { return }
        presentedContentID = content.id
        host.rootView = HighlightActionCardView(
            content: content, theme: theme, mode: mode, form: .card,
            noteDraft: noteDraft, pressedColor: pressedColor,
            onAction: callbacks.onAction,
            onDraftChange: callbacks.onDraftChange,
            onDismiss: callbacks.onDismiss
        )
    }

    func dismissCard(completion: (@MainActor () -> Void)?) {
        if let completion { pendingDismissCompletions.append(completion) }
        switch phase {
        case .idle:
            pendingRequest = nil
            drainCompletions()
        case .presenting:
            pendingRequest = nil
            beginDismiss()
        case .dismissing:
            pendingRequest = nil
        }
    }

    // MARK: - Pipeline

    private func beginDismiss() {
        guard let host = presentedHost else {
            phase = .idle
            drainPipeline()
            return
        }
        phase = .dismissing
        presentedHost = nil
        presentedContentID = nil
        liveCallbacks = nil
        liveTheme = nil
        popoverDelegate = nil
        host.dismiss(animated: true) { [weak self] in
            self?.phase = .idle
            self?.drainPipeline()
        }
    }

    private func drainPipeline() {
        drainCompletions()
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        performPresent(request)
    }

    private func drainCompletions() {
        let completions = pendingDismissCompletions
        pendingDismissCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func performPresent(_ request: CardRequest) {
        guard let presenter = request.view.nearestViewController else {
            phase = .idle
            request.onDismiss()
            return
        }
        let card = HighlightActionCardView(
            content: request.content, theme: request.theme,
            mode: request.mode, form: .card,
            noteDraft: request.noteDraft, pressedColor: request.pressedColor,
            onAction: request.onAction,
            onDraftChange: request.onDraftChange,
            onDismiss: request.onDismiss
        )
        let host = UIHostingController(rootView: card)
        host.modalPresentationStyle = .popover
        host.preferredContentSize = Self.cardContentSize
        host.view.backgroundColor = .clear

        guard let popover = host.popoverPresentationController else {
            phase = .idle
            request.onDismiss()
            return
        }
        popover.sourceView = request.view
        popover.sourceRect = request.content.sourceRect
        popover.permittedArrowDirections = [.up, .down]
        popover.backgroundColor = .clear

        let delegate = HighlightPopoverDelegate(onDismiss: { [weak self] in
            guard let self else { return }
            if self.phase != .dismissing {
                self.presentedHost = nil
                self.presentedContentID = nil
                self.liveCallbacks = nil
                self.liveTheme = nil
                self.popoverDelegate = nil
                self.phase = .idle
                self.drainPipeline()
            }
            request.onDismiss()
        })
        popover.delegate = delegate

        presentedHost = host
        presentedContentID = request.content.id
        liveCallbacks = (request.onAction, request.onDraftChange, request.onDismiss)
        liveTheme = request.theme
        popoverDelegate = delegate
        phase = .presenting
        presenter.present(host, animated: true)
    }

    /// The anchored card's preferred content size. Width matches the design's
    /// `cardW` (320pt); height is a comfortable cap — the card's note body
    /// clamps inside `HighlightActionCardView`.
    private static let cardContentSize = CGSize(width: 320, height: 380)
}

/// `UIPopoverPresentationControllerDelegate` keeping the popover anchored even
/// on compact width, and reporting an interactive dismissal.
private final class HighlightPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    private let onDismiss: @MainActor () -> Void

    init(onDismiss: @escaping @MainActor () -> Void) {
        self.onDismiss = onDismiss
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        let onDismiss = self.onDismiss
        MainActor.assumeIsolated { onDismiss() }
    }
}

// MARK: - UIView → presenting UIViewController

extension UIView {
    /// Walks the responder chain to the nearest enclosing `UIViewController`
    /// — the controller a popover anchored in this view should present from.
    /// (Feature #64 WI-10: re-homed here from the deleted feature-#55
    /// `UIKitNotePreviewPresenter`; `UIKitHighlightPopoverPresenter` is its
    /// only caller.)
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController {
                return viewController
            }
            responder = next
        }
        return nil
    }
}
#endif
