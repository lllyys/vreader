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
}
#endif
