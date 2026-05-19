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

    /// Dismisses a currently-presented callout, if any. A no-op when nothing
    /// is presented.
    func dismissCallout()
}

/// `UIPopoverPresentationController`-based realization of `NotePreviewPresenting`.
@MainActor
final class UIKitNotePreviewPresenter: NSObject, NotePreviewPresenting {

    /// The hosting controller of a currently-presented callout. Weak — the
    /// presenting view-controller hierarchy retains it while presented; this
    /// reference only lets the presenter dismiss a superseded callout.
    private weak var presentedHost: UIViewController?

    /// Retains the popover delegate while a callout is presented (the
    /// `UIPopoverPresentationController.delegate` is weak).
    private var popoverDelegate: PopoverDelegate?

    func presentCallout(
        _ content: NotePreviewContent,
        theme: ReaderThemeV2,
        in view: UIView,
        onAction: @escaping (NoteCalloutAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // A superseding tap replaces any live callout — dismiss the old one
        // first so two callouts can never stack.
        dismissCallout()

        guard let presenter = view.nearestViewController else {
            // No view-controller to present from — surface nothing rather
            // than crash. The modifier's sheet fallback still covers the user.
            onDismiss()
            return
        }

        let callout = NoteCalloutView(
            content: content,
            theme: theme,
            onAction: { [weak self] action in
                // The action fires; then the callout dismisses (read-only
                // handoffs hand off to another surface).
                onAction(action)
                self?.dismissCallout()
            },
            onDismiss: { [weak self] in self?.dismissCallout() }
        )
        let host = UIHostingController(rootView: callout)
        host.modalPresentationStyle = .popover
        host.preferredContentSize = Self.calloutContentSize
        host.view.backgroundColor = .clear

        guard let popover = host.popoverPresentationController else {
            onDismiss()
            return
        }
        popover.sourceView = view
        popover.sourceRect = content.sourceRect
        popover.permittedArrowDirections = [.up, .down]
        popover.backgroundColor = .clear

        let delegate = PopoverDelegate(onDismiss: { [weak self] in
            self?.presentedHost = nil
            self?.popoverDelegate = nil
            onDismiss()
        })
        popover.delegate = delegate

        self.presentedHost = host
        self.popoverDelegate = delegate
        presenter.present(host, animated: true)
    }

    func dismissCallout() {
        guard let host = presentedHost else { return }
        presentedHost = nil
        popoverDelegate = nil
        host.dismiss(animated: true)
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
private final class PopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
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
        onDismiss()
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
