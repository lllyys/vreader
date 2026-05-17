// Purpose: Tests for `UIKitHighlightActionPresenter` (Feature #53 / GH #596).
// Verifies the menu structure built by `buildMenu(for:completion:)` and the
// `FireOnceBox` single-shot completion guard, without presenting on a real
// screen (tests run on iPhone 17 Pro Sim but assert UIMenu structure only).
//
// @coordinates-with: HighlightActionPresenter.swift

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
import CoreGraphics
@testable import vreader

@Suite("UIKitHighlightActionPresenter")
struct UIKitHighlightActionPresenterTests {

    private func makeEvent() -> ReaderHighlightTapEvent {
        ReaderHighlightTapEvent(
            highlightID: UUID(),
            sourceRect: CGRect(x: 10, y: 20, width: 80, height: 18)
        )
    }

    @Test @MainActor
    func buildMenu_containsExactlyOneDeleteItem() {
        let menu = UIKitHighlightActionPresenter.buildMenu(
            for: makeEvent(),
            completion: { _ in }
        )
        // The presenter wraps the Delete UIAction inside a `.displayInline`
        // submenu, so flatten one level to find the actionable items.
        let actions = menu.children.flatMap { ($0 as? UIMenu)?.children ?? [$0] }
        let deleteItems = actions.compactMap { $0 as? UIAction }
            .filter { $0.title == UIKitHighlightActionPresenter.deleteItemTitle }
        #expect(deleteItems.count == 1)
    }

    @Test @MainActor
    func deleteAction_isDestructive() {
        let menu = UIKitHighlightActionPresenter.buildMenu(
            for: makeEvent(),
            completion: { _ in }
        )
        let actions = menu.children.flatMap { ($0 as? UIMenu)?.children ?? [$0] }
        guard let delete = actions.compactMap({ $0 as? UIAction })
            .first(where: { $0.title == UIKitHighlightActionPresenter.deleteItemTitle }) else {
            Issue.record("Delete action not found in menu")
            return
        }
        #expect(delete.attributes.contains(.destructive))
    }

    @Test @MainActor
    func invokeAction_delete_callsCompletionWithDeleteAction() {
        // UIAction.handler is not directly invokable in unit tests
        // (performWithSender is UIControl's API, not UIMenu's). Test the
        // action-firing logic via the testable invokeAction static helper
        // that the menu's UIAction handler funnels through.
        var captured: [HighlightTapAction?] = []
        let didFire = FireOnceBox()
        UIKitHighlightActionPresenter.invokeAction(
            .delete,
            didFire: didFire,
            completion: { action in captured.append(action) }
        )
        #expect(captured == [.delete])
    }

    @Test @MainActor
    func invokeAction_calledTwice_callsCompletionOnlyOnce() {
        // Simulates a rapid double-tap on the menu item; FireOnceBox must
        // guard against double delivery.
        var captured: [HighlightTapAction?] = []
        let didFire = FireOnceBox()
        let completion: @MainActor (HighlightTapAction?) -> Void = { action in
            captured.append(action)
        }
        UIKitHighlightActionPresenter.invokeAction(
            .delete, didFire: didFire, completion: completion
        )
        UIKitHighlightActionPresenter.invokeAction(
            .delete, didFire: didFire, completion: completion
        )
        #expect(captured == [.delete])
    }

    @Test @MainActor
    func invokeDismiss_withoutPriorAction_callsCompletionWithNil() {
        var captured: [HighlightTapAction?] = []
        let didFire = FireOnceBox()
        UIKitHighlightActionPresenter.invokeDismiss(
            didFire: didFire,
            completion: { action in captured.append(action) }
        )
        #expect(captured == [nil])
    }

    @Test @MainActor
    func invokeDismiss_afterPriorAction_doesNotCallCompletionAgain() {
        // Tap-then-dismiss race: action fires first, dismiss arrives after.
        // FireOnceBox must prevent the dismiss callback from delivering nil.
        var captured: [HighlightTapAction?] = []
        let didFire = FireOnceBox()
        let completion: @MainActor (HighlightTapAction?) -> Void = { action in
            captured.append(action)
        }
        UIKitHighlightActionPresenter.invokeAction(
            .delete, didFire: didFire, completion: completion
        )
        UIKitHighlightActionPresenter.invokeDismiss(
            didFire: didFire, completion: completion
        )
        #expect(captured == [.delete])
    }

    @Test @MainActor
    func fireOnceBox_runsBlockOnlyOnFirstCall() {
        let box = FireOnceBox()
        var count = 0
        box.fire { count += 1 }
        box.fire { count += 1 }
        box.fire { count += 1 }
        #expect(count == 1)
    }

    // MARK: - Delegate retention (Bug #205 / GH #751)

    @Test @MainActor
    func present_retainsItsDelegate_preventingComposeFailure() {
        // Bug #205: `UIEditMenuInteraction` holds its `delegate` weakly. The
        // pre-fix presenter created the `PresenterDelegate` as a local with no
        // owning reference, so it deallocated the instant `present` returned —
        // UIKit then queried a nil delegate, got no menu, and logged
        // `[EditMenuInteraction] <compose failure>`. The fix associates the
        // delegate onto the interaction. Because the interaction holds its
        // `delegate` *weakly*, a non-nil `delegate` read after `present`
        // returns proves something still retains the delegate — the exact
        // regression boundary. The pre-fix code would read nil here.
        let presenter = UIKitHighlightActionPresenter()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        presenter.present(for: makeEvent(), in: view, completion: { _ in })
        let interaction = view.interactions
            .compactMap { $0 as? UIEditMenuInteraction }
            .first
        #expect(interaction != nil)
        #expect(interaction?.delegate != nil)
    }

    @Test @MainActor
    func present_addsAnEditMenuInteractionToTheHostView() {
        // The interaction must be installed on the host view — UIKit routes
        // the menu-composition callback through it. Without it on the
        // responder chain there is nothing for UIKit to query.
        let presenter = UIKitHighlightActionPresenter()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        presenter.present(for: makeEvent(), in: view, completion: { _ in })
        let hasEditMenuInteraction = view.interactions.contains { $0 is UIEditMenuInteraction }
        #expect(hasEditMenuInteraction)
    }

    @Test @MainActor
    func present_calledTwice_supersedesThePriorMenuInteraction() {
        // Tapping a second highlight before the first menu dismisses must not
        // accumulate interactions: the second `present` removes the prior
        // edit-menu interaction it installed and leaves exactly one — whose
        // delegate is still retained (the compose-failure regression).
        let presenter = UIKitHighlightActionPresenter()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        presenter.present(for: makeEvent(), in: view, completion: { _ in })
        presenter.present(for: makeEvent(), in: view, completion: { _ in })
        let interactions = view.interactions.compactMap { $0 as? UIEditMenuInteraction }
        #expect(interactions.count == 1)
        #expect(interactions.first?.delegate != nil)
    }

    @Test @MainActor
    func present_leavesAnUnrelatedEditMenuInteractionInPlace() {
        // A `UITextView` host owns its own built-in `UIEditMenuInteraction`
        // for the selection menu. The supersede sweep keys on the presenter's
        // delegate association, so it must not remove an interaction it did
        // not install.
        let presenter = UIKitHighlightActionPresenter()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let foreign = UIEditMenuInteraction(delegate: nil)
        view.addInteraction(foreign)
        presenter.present(for: makeEvent(), in: view, completion: { _ in })
        #expect(view.interactions.contains { $0 === foreign })
    }
}
#endif
