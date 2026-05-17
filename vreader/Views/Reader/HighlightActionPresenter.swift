// Purpose: Inline-menu presenter for a tapped highlight (Feature #53 / GH #596).
//
// Reader bridges post `.readerHighlightTapped` with a `ReaderHighlightTapEvent`
// carrying the highlight UUID + a `sourceRect` in the same `UIView`'s
// coordinate space as the view the bridge passes to `present(for:in:)` (per
// the contract on `ReaderHighlightTapEvent.sourceRect` — Bug #203 / GH
// #743). The container view (or its notification modifier) asks an injected
// `HighlightActionPresenting` to show a menu anchored at that rect and
// routes the resolved `HighlightTapAction` back to
// `HighlightCoordinator.handleTapAction(_:highlightID:)`. The presenter
// does NOT normalize coordinates — it trusts the bridge to emit
// view-local rects so `UIEditMenuConfiguration.sourcePoint` lands where
// the user tapped.
//
// Default impl is `UIKitHighlightActionPresenter` using `UIEditMenuInteraction`
// on iOS 16+ for the anchored popover. For test isolation, presenters are
// protocol-injected — tests inspect the `UIMenu` structure built by
// `buildMenu(for:completion:)` without presenting on a real screen.
//
// Key decisions:
// - Completion fires synchronously on the main actor (no Task hop), so tests
//   that simulate a UIAction tap can assert immediately. UIKit guarantees
//   UIAction handlers + UIEditMenuInteraction delegate callbacks run on main.
// - `FireOnceBox` is @MainActor-isolated; the single-shot guard prevents
//   double delivery under fast taps + dismiss races.
// - `UIEditMenuInteraction` holds its `delegate` *weakly* (SDK:
//   `@property (weak, readonly) delegate`). `present` therefore associates
//   the `PresenterDelegate` onto the interaction object itself with an
//   `OBJC_ASSOCIATION_RETAIN_NONATOMIC` policy: the interaction — which the
//   host view retains — strongly owns its delegate, so the delegate lives
//   exactly as long as the interaction and is reclaimed with it (on dismiss,
//   or when the host view is torn down). Without this the delegate
//   deallocates the instant `present` returns, UIKit queries a nil delegate,
//   and the menu fails to compose (Bug #205 / GH #751). Binding the lifetime
//   to the interaction rather than the presenter means a presenter recreated
//   on every SwiftUI render (the reader containers build one inline in
//   `body`) cannot strand an in-flight menu — the presenter is stateless.
//   `present` also removes any edit-menu interaction it installed on the
//   same view earlier, so a superseded/aborted presentation that never got
//   a `willDismissMenuFor` callback can't linger until view teardown.
// - WI-1 ships .delete only; the UIMenu has one item titled "Delete Highlight".
//   Future actions extend the menu builder; the protocol surface is unchanged.
//
// @coordinates-with: HighlightTapAction.swift, HighlightCoordinator.swift,
//   ReaderNotifications.swift

#if canImport(UIKit)
import UIKit
import ObjectiveC

@MainActor
protocol HighlightActionPresenting: AnyObject {
    /// Shows the action menu for `event` anchored to `event.sourceRect` in
    /// `view`'s coordinate space. Calls `completion` exactly once with the
    /// selected action, or with nil if the user dismissed without choosing.
    func present(
        for event: ReaderHighlightTapEvent,
        in view: UIView,
        completion: @escaping @MainActor (HighlightTapAction?) -> Void
    )
}

@MainActor
final class UIKitHighlightActionPresenter: HighlightActionPresenting {

    /// Title used for the Delete menu item. Exposed for test assertion.
    static let deleteItemTitle = "Delete Highlight"

    /// Identity key for the delegate→interaction object association in
    /// `present`. Only the *address* of this byte is used as the key; the
    /// stored value is never read or mutated. `nonisolated(unsafe)` is sound
    /// for an immutable identity token like this.
    nonisolated(unsafe) private static var delegateAssociationKey: UInt8 = 0

    /// Builds the `UIMenu` shown for `event`. Exposed for test assertion —
    /// tests inspect the menu structure without actually presenting it.
    /// The completion fires synchronously on the main actor when the user
    /// taps Delete (UIAction handlers run on main); FireOnceBox guards
    /// double delivery from rapid taps.
    static func buildMenu(
        for event: ReaderHighlightTapEvent,
        completion: @escaping @MainActor (HighlightTapAction?) -> Void
    ) -> UIMenu {
        let didFire = FireOnceBox()
        let delete = UIAction(
            title: deleteItemTitle,
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { _ in
            MainActor.assumeIsolated {
                Self.invokeAction(.delete, didFire: didFire, completion: completion)
            }
        }
        return UIMenu(title: "", options: .displayInline, children: [delete])
    }

    /// Single entry point that the menu's UIAction handler funnels through.
    /// Exposed for tests so the FireOnceBox guard + completion delivery can
    /// be verified without driving UIKit's menu chrome (UIAction's handler
    /// is not directly invokable in unit tests — `performWithSender` is
    /// UIControl's action mechanism, not UIMenu's).
    @MainActor
    static func invokeAction(
        _ action: HighlightTapAction,
        didFire: FireOnceBox,
        completion: @escaping @MainActor (HighlightTapAction?) -> Void
    ) {
        didFire.fire { completion(action) }
    }

    /// Dismiss-path entry point. Mirrors `invokeAction` for symmetry; both
    /// share the same FireOnceBox to guard against tap-then-dismiss races.
    @MainActor
    static func invokeDismiss(
        didFire: FireOnceBox,
        completion: @escaping @MainActor (HighlightTapAction?) -> Void
    ) {
        didFire.fire { completion(nil) }
    }

    func present(
        for event: ReaderHighlightTapEvent,
        in view: UIView,
        completion: @escaping @MainActor (HighlightTapAction?) -> Void
    ) {
        // One FireOnceBox shared by the Delete action and the dismiss path
        // so a tap-then-dismiss race delivers the completion exactly once.
        let didFire = FireOnceBox()
        let menu = UIMenu(title: "", options: .displayInline, children: [
            UIAction(
                title: Self.deleteItemTitle,
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                MainActor.assumeIsolated {
                    Self.invokeAction(.delete, didFire: didFire, completion: completion)
                }
            }
        ])
        let delegate = PresenterDelegate(
            menu: menu,
            didFire: didFire,
            completion: completion
        )
        let interaction = UIEditMenuInteraction(delegate: delegate)
        delegate.hostView = view
        // `UIEditMenuInteraction.delegate` is weak. Associate the delegate
        // onto the interaction so the interaction — itself strongly retained
        // by the host view — owns it. The delegate then outlives `present`
        // and is reclaimed only when the interaction is (on dismiss, or when
        // the host view is torn down). This is what fixes Bug #205; see the
        // file header for why the lifetime is bound here and not on `self`.
        objc_setAssociatedObject(
            interaction,
            &Self.delegateAssociationKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        // Drop any edit-menu interaction a prior `present` installed on this
        // view. Normal dismiss already removes it via `willDismissMenuFor`,
        // but a superseded or aborted presentation (no menu produced, no
        // dismiss callback) would otherwise linger — with its associated
        // delegate — until the view is torn down.
        Self.removePriorMenuInteractions(from: view)
        view.addInteraction(interaction)

        let cfg = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(
            x: event.sourceRect.midX,
            y: event.sourceRect.midY
        ))
        interaction.presentEditMenu(with: cfg)
    }

    /// Removes every `UIEditMenuInteraction` a previous `present` call
    /// installed on `view`, identified by the delegate association. A view
    /// the presenter targets can own an unrelated `UIEditMenuInteraction`
    /// (e.g. `UITextView`'s built-in selection menu); that one has no
    /// association under our key and is left in place.
    private static func removePriorMenuInteractions(from view: UIView) {
        let installed = view.interactions.compactMap { interaction -> UIEditMenuInteraction? in
            guard let editMenu = interaction as? UIEditMenuInteraction,
                  objc_getAssociatedObject(editMenu, &delegateAssociationKey) is PresenterDelegate
            else { return nil }
            return editMenu
        }
        installed.forEach { view.removeInteraction($0) }
    }
}

/// Single-shot completion guard. Calling `fire(_:)` runs the block at most once.
@MainActor
final class FireOnceBox {
    private var didFire = false

    func fire(_ block: () -> Void) {
        guard !didFire else { return }
        didFire = true
        block()
    }
}

/// Delegate that hands the menu back to `UIEditMenuInteraction` and, on
/// dismiss, detaches the interaction from its host view so the interaction
/// — and this delegate, associated onto it — can deallocate (Bug #205).
/// Conformance is `nonisolated` because the SDK protocol is unannotated;
/// the delegate methods land on the main thread at runtime, and the
/// main-actor work hops explicitly via `MainActor.assumeIsolated`.
private final class PresenterDelegate: NSObject, UIEditMenuInteractionDelegate {
    private let menu: UIMenu
    private let didFire: FireOnceBox
    private let completion: @MainActor (HighlightTapAction?) -> Void

    /// Weak — the host view retains the interaction, which in turn owns this
    /// delegate via object association, so the delegate must not retain the
    /// view back. Used on dismiss to detach the dismissing interaction so a
    /// stale one doesn't accumulate on the host.
    weak var hostView: UIView?

    init(
        menu: UIMenu,
        didFire: FireOnceBox,
        completion: @escaping @MainActor (HighlightTapAction?) -> Void
    ) {
        self.menu = menu
        self.didFire = didFire
        self.completion = completion
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        menu
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        // This SDK callback is `nonisolated`, so every value used inside the
        // `@MainActor` hop is first copied into a Sendable local — the
        // closure must never capture non-Sendable `self`.
        let didFire = self.didFire
        let completion = self.completion
        let hostView = self.hostView
        MainActor.assumeIsolated {
            // Dismiss without a prior action delivers nil; FireOnceBox
            // suppresses it when a menu action already fired the completion.
            UIKitHighlightActionPresenter.invokeDismiss(
                didFire: didFire, completion: completion
            )
            // Detach the dismissing interaction from the host view. Nothing
            // else retains the interaction, so it — and this delegate,
            // associated onto it — deallocate once the callback unwinds.
            hostView?.removeInteraction(interaction)
        }
    }
}
#endif
