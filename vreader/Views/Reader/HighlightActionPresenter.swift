// Purpose: Inline-menu presenter for a tapped highlight (Feature #53 / GH #596).
//
// Reader bridges post `.readerHighlightTapped` with a `ReaderHighlightTapEvent`
// carrying the highlight UUID + screen-space rect. The container view (or its
// notification modifier) asks an injected `HighlightActionPresenting` to show
// a menu anchored at that rect and routes the resolved `HighlightTapAction`
// back to `HighlightCoordinator.handleTapAction(_:highlightID:)`.
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
// - WI-1 ships .delete only; the UIMenu has one item titled "Delete Highlight".
//   Future actions extend the menu builder; the protocol surface is unchanged.
//
// @coordinates-with: HighlightTapAction.swift, HighlightCoordinator.swift,
//   ReaderNotifications.swift

#if canImport(UIKit)
import UIKit

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
        let interaction = UIEditMenuInteraction(delegate: PresenterDelegate(
            menu: menu,
            onDismiss: {
                MainActor.assumeIsolated {
                    Self.invokeDismiss(didFire: didFire, completion: completion)
                }
            }
        ))
        view.addInteraction(interaction)

        let cfg = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(
            x: event.sourceRect.midX,
            y: event.sourceRect.midY
        ))
        interaction.presentEditMenu(with: cfg)
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

/// Delegate that hands the menu builder back to `UIEditMenuInteraction` and
/// notifies on dismiss. Conformance is `nonisolated` because the SDK protocol
/// is unannotated; the delegate methods land on the main thread at runtime,
/// and the stored callbacks hop to the main actor explicitly via
/// `MainActor.assumeIsolated` when fired.
private final class PresenterDelegate: NSObject, UIEditMenuInteractionDelegate {
    private let menu: UIMenu
    private let onDismiss: @Sendable () -> Void

    init(menu: UIMenu, onDismiss: @escaping @Sendable () -> Void) {
        self.menu = menu
        self.onDismiss = onDismiss
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
        onDismiss()
    }
}
#endif
