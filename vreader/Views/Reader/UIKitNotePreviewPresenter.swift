// Purpose: Feature #55 WI-5 — `NotePreviewPresenting` + `UIKitNotePreviewPresenter`,
// the rect-anchored presenter for the note-preview callout.
//
// The anchored `NoteCalloutView` is presented by a UIKit presenter that
// anchors a `UIHostingController` (hosting the SwiftUI callout) as a
// `.popover`-style `modalPresentationStyle` whose
// `popoverPresentationController.sourceView` is the reader's content `UIView`
// and whose `sourceRect` is the tap event's `sourceRect`. This is the
// standard supported UIKit path for "anchor a popover to an arbitrary rect in
// a view" — `UIPopoverPresentationController` gives the pointer arrow, the
// auto-flip when there is no room, and outside-tap dismiss (plan §2.7.1).
//
// Mirrors feature #53's `UIKitHighlightActionPresenter`: a UIKit presenter,
// protocol-injected for test isolation, anchored to the same
// `ReaderHighlightTapEvent.sourceRect` — just presenting a hosted SwiftUI
// card instead of a `UIEditMenuInteraction`.
//
// The bottom-sheet form (`NotePreviewSheetView`) is NOT presented here — it
// is driven the SwiftUI way by `NotePreviewModifier`'s `.sheet`. This
// presenter owns only the anchored-callout form.
//
// Key decisions:
// - `@MainActor` — all UIKit presentation is main-actor.
// - The presenter holds the presented controller weakly enough to dismiss it
//   on a superseding tap, but the view-controller hierarchy retains it while
//   presented. `dismissCallout()` tears down a live callout.
// - On a compact-width iPhone `UIPopoverPresentationController` adapts to a
//   sheet-like presentation (risk R-7) — accepted, it degrades to the same
//   family as the intended fallback. The adaptive-presentation delegate is
//   set explicitly so the behavior is deliberate, not incidental.
//
// @coordinates-with: NoteCalloutView.swift, NoteCalloutAction.swift,
//   NotePreviewContent.swift, NotePreviewModifier (NotePreviewPresenter.swift)

#if canImport(UIKit)
import UIKit
import SwiftUI

/// Presents the anchored note-preview callout. Protocol so `NotePreviewModifier`
/// can be unit-tested against a fake instead of a real popover.
@MainActor
protocol NotePreviewPresenting: AnyObject {
    /// Presents the anchored note callout for `content` at `content.sourceRect`
    /// in `view`. `onAction` receives a handoff-row tap (Share / Open-in-panel
    /// — the v1 surface; Edit is the BLOCKED: needs-design slice). `onDismiss`
    /// fires when the popover closes by any means.
    func presentCallout(
        _ content: NotePreviewContent,
        theme: ReaderThemeV2,
        in view: UIView,
        onAction: @escaping (NoteCalloutAction) -> Void,
        onDismiss: @escaping () -> Void
    )

    /// Dismisses a currently-presented callout, if any. `completion` runs
    /// after the dismissal finishes — or synchronously when nothing is
    /// presented — so a caller can safely present a follow-up surface
    /// (a share sheet, the Annotations panel) without a modal collision.
    func dismissCallout(completion: (@MainActor () -> Void)?)
}

extension NotePreviewPresenting {
    /// Dismiss with no completion — the common case.
    func dismissCallout() { dismissCallout(completion: nil) }
}

/// `UIPopoverPresentationController`-based realization of `NotePreviewPresenting`.
///
/// A single serialized present/dismiss pipeline guards against modal
/// collisions under rapid taps. The presenter is in one of three phases —
/// `idle`, `presenting`, `dismissing` — and never starts a UIKit
/// present/dismiss while another is in flight. A request that arrives mid-
/// transition is stashed in `pendingRequest`; only the **latest** stashed
/// request is honored when the pipeline becomes free, so an older queued tap
/// can never overwrite a newer one (Codex Gate-4 round-2 High).
@MainActor
final class UIKitNotePreviewPresenter: NSObject, NotePreviewPresenting {

    /// A request to present a callout — stashed while the pipeline is busy.
    private struct CalloutRequest {
        let content: NotePreviewContent
        let theme: ReaderThemeV2
        let view: UIView
        let onAction: (NoteCalloutAction) -> Void
        let onDismiss: () -> Void
    }

    /// The pipeline phase.
    private enum Phase {
        case idle        // nothing presented, no transition in flight
        case presenting  // a callout is presented (and settled)
        case dismissing  // a dismissal is in flight
    }

    private var phase: Phase = .idle

    /// The hosting controller of the presented callout. Weak — the presenting
    /// view-controller hierarchy retains it while presented.
    private weak var presentedHost: UIViewController?

    /// Retains the popover delegate while a callout is presented (the
    /// `UIPopoverPresentationController.delegate` is weak).
    private var popoverDelegate: PopoverDelegate?

    /// The LATEST present request that arrived while the pipeline was busy.
    /// Replaced (not appended) by each new request so only the newest wins.
    private var pendingRequest: CalloutRequest?

    /// `dismissCallout` completions queued while a transition is in flight.
    private var pendingDismissCompletions: [@MainActor () -> Void] = []

    func presentCallout(
        _ content: NotePreviewContent,
        theme: ReaderThemeV2,
        in view: UIView,
        onAction: @escaping (NoteCalloutAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let request = CalloutRequest(
            content: content, theme: theme, view: view,
            onAction: onAction, onDismiss: onDismiss
        )
        switch phase {
        case .idle:
            // Pipeline free — present immediately.
            performPresent(request)
        case .presenting:
            // A callout is up — dismiss it; the pending request presents
            // from the dismiss completion.
            pendingRequest = request
            beginDismiss()
        case .dismissing:
            // A dismissal is already running — just stash the latest request.
            // `drainPipeline` (run when the dismissal finishes) presents it.
            pendingRequest = request
        }
    }

    func dismissCallout(completion: (@MainActor () -> Void)?) {
        if let completion { pendingDismissCompletions.append(completion) }
        switch phase {
        case .idle:
            // Nothing to dismiss — drain queued completions synchronously.
            // Also drop any stale pending present request: a dismiss
            // supersedes a not-yet-presented callout.
            pendingRequest = nil
            drainCompletions()
        case .presenting:
            pendingRequest = nil   // a dismiss cancels a queued present
            beginDismiss()
        case .dismissing:
            // Dismissal already in flight; a dismiss also cancels any queued
            // present so the callout does not reappear after teardown.
            pendingRequest = nil
        }
    }

    // MARK: - Pipeline

    /// Starts dismissing the live callout. On completion, `drainPipeline`
    /// runs the queued completions and presents the latest pending request.
    private func beginDismiss() {
        guard let host = presentedHost else {
            // Defensive — `presenting` with no host. Treat as idle.
            phase = .idle
            drainPipeline()
            return
        }
        phase = .dismissing
        presentedHost = nil
        popoverDelegate = nil
        host.dismiss(animated: true) { [weak self] in
            self?.phase = .idle
            self?.drainPipeline()
        }
    }

    /// Called once the pipeline is free (`.idle`). Runs every queued dismiss
    /// completion, then presents the single latest pending request if one
    /// was stashed.
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

    /// Presents `request`'s callout. Only ever called from `.idle`.
    private func performPresent(_ request: CalloutRequest) {
        guard let presenter = request.view.nearestViewController else {
            // No view-controller to present from — surface nothing rather
            // than crash. The modifier's sheet fallback still covers the user.
            phase = .idle
            request.onDismiss()
            return
        }

        let callout = NoteCalloutView(
            content: request.content,
            theme: request.theme,
            onAction: { [weak self] action in
                // The action fires; then the callout dismisses (read-only
                // handoffs hand off to another surface).
                request.onAction(action)
                self?.dismissCallout()
            },
            onDismiss: { [weak self] in self?.dismissCallout() }
        )
        let host = UIHostingController(rootView: callout)
        host.modalPresentationStyle = .popover
        host.preferredContentSize = Self.calloutContentSize
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

        // The popover delegate reports an interactive dismissal (outside-tap
        // / swipe). It routes back through `dismissCallout` so the phase
        // machine stays consistent — `presentationControllerDidDismiss`
        // fires AFTER UIKit has torn the popover down, so by then we just
        // need to reconcile state, not start another dismissal.
        let delegate = PopoverDelegate(onDismiss: { [weak self] in
            guard let self else { return }
            // UIKit already dismissed — reconcile to idle and drain.
            if self.phase != .dismissing {
                self.presentedHost = nil
                self.popoverDelegate = nil
                self.phase = .idle
                self.drainPipeline()
            }
            request.onDismiss()
        })
        popover.delegate = delegate

        presentedHost = host
        popoverDelegate = delegate
        phase = .presenting
        presenter.present(host, animated: true)
    }

    /// The callout's preferred content size. Width matches the design's
    /// `cardW` (304pt); height is a comfortable cap — the note body scrolls
    /// inside `NoteCalloutView` past its own 180pt limit.
    private static let calloutContentSize = CGSize(width: 304, height: 320)
}

/// `UIPopoverPresentationControllerDelegate` that (a) keeps the popover a
/// popover even on compact width — explicitly opting OUT of the default
/// full-screen adaptation so the anchored form is deliberate (risk R-7) — and
/// (b) reports dismissal so the presenter can clear its state.
///
/// `.none` adaptive style keeps a true anchored popover on iPhone; if a future
/// device class genuinely cannot host one, UIKit still falls back gracefully.
///
/// Conformance is `nonisolated` because the SDK protocol is unannotated; the
/// delegate methods land on the main thread at runtime, and the main-actor
/// `onDismiss` closure is invoked via an explicit `MainActor.assumeIsolated`
/// hop — mirroring `HighlightActionPresenter`'s documented pattern rather than
/// relying on an unstated main-thread assumption.
private final class PopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    private let onDismiss: @MainActor () -> Void

    init(onDismiss: @escaping @MainActor () -> Void) {
        self.onDismiss = onDismiss
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        // Keep the anchored popover on compact width too — the note preview
        // is a small card, not a full-screen surface.
        .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // This SDK callback is `nonisolated`; copy the main-actor closure into
        // a Sendable local and hop explicitly before invoking it.
        let onDismiss = self.onDismiss
        MainActor.assumeIsolated { onDismiss() }
    }
}

// MARK: - UIView → presenting UIViewController

extension UIView {
    /// Walks the responder chain to the nearest enclosing `UIViewController`
    /// — the controller a popover anchored in this view should present from.
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
