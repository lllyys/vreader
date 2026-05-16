// Purpose: Feature #60 WI-7c1 — pins the cross-boundary contract for
// the `.readerSelectionPopoverRequested` notification and the parse
// helper that turns the raw `Notification` into a typed
// `TextSelectionInfo`. The SwiftUI sheet lifecycle inside
// `SelectionPopoverPresenterModifier` is integration / device-verify
// territory (sheet presents/dismisses are SwiftUI side-effects that
// don't unit-test cleanly). The unit-test surface this file pins is
// the public wire format that bridge swaps (WI-7c2–WI-7c5) will post
// onto.
//
// **Why a parse helper on the modifier's enum and not free-floating
// on `Notification`**: keeps the contract local to the presenter,
// mirroring `FoliateSelectionDispatcher.notificationUserInfo` /
// `FoliateMessageParser.parseSelection`. Bridges post via the
// helper's `post(selection:on:)`; tests read it back via
// `selection(from:)`.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #60 WI-7c1 — SelectionPopoverRequest notification contract")
@MainActor
struct SelectionPopoverPresenterTests {

    // MARK: - Notification name shape

    @Test("Notification name is the documented stable identifier")
    func notificationName() {
        // Stable across the WI-7c bridge swap so observers (the
        // presenter + future XCUITest harnesses) match on the raw
        // string without importing Foundation.
        #expect(Notification.Name.readerSelectionPopoverRequested.rawValue
                == "vreader.readerSelectionPopoverRequested")
    }

    // MARK: - Parse helper

    private func makeSelection(
        text: String = "the rapidity of the infection",
        start: Int = 1024,
        end: Int = 1053
    ) -> TextSelectionInfo {
        TextSelectionInfo(
            selectedText: text,
            startUTF16: start,
            endUTF16: end
        )
    }

    @Test("selection(from:) round-trips the posted TextSelectionInfo")
    func roundTrip() {
        let info = makeSelection()
        let note = Notification(
            name: .readerSelectionPopoverRequested,
            object: info,
            userInfo: nil
        )
        let parsed = SelectionPopoverRequest.selection(from: note)
        #expect(parsed?.selectedText == "the rapidity of the infection")
        #expect(parsed?.startUTF16 == 1024)
        #expect(parsed?.endUTF16 == 1053)
    }

    @Test("selection(from:) returns nil when object is not TextSelectionInfo")
    func wrongObjectType() {
        // A bridge that mis-posts (e.g., string instead of struct)
        // must not crash the presenter. Returning nil lets the
        // modifier silently drop the notification — bridges posting
        // garbage are a development-time bug, not a user-facing
        // crash.
        let note = Notification(
            name: .readerSelectionPopoverRequested,
            object: "wrong-shape",
            userInfo: nil
        )
        #expect(SelectionPopoverRequest.selection(from: note) == nil)
    }

    @Test("selection(from:) returns nil when object is nil")
    func nilObject() {
        let note = Notification(
            name: .readerSelectionPopoverRequested,
            object: nil,
            userInfo: nil
        )
        #expect(SelectionPopoverRequest.selection(from: note) == nil)
    }

    // MARK: - Post helper

    @Test("post(selection:on:) posts on the named notification with TextSelectionInfo as object")
    func postRoundTrip() throws {
        let center = NotificationCenter()
        var captured: Notification?
        let token = center.addObserver(
            forName: .readerSelectionPopoverRequested,
            object: nil,
            queue: nil
        ) { note in captured = note }
        defer { center.removeObserver(token) }

        let info = makeSelection(text: "hello", start: 5, end: 10)
        SelectionPopoverRequest.post(selection: info, on: center)

        let note = try #require(captured)
        #expect(note.name == .readerSelectionPopoverRequested)
        let parsed = try #require(SelectionPopoverRequest.selection(from: note))
        #expect(parsed.selectedText == "hello")
        #expect(parsed.startUTF16 == 5)
        #expect(parsed.endUTF16 == 10)
    }

    @Test("post(selection:on:) with empty text still emits — caller decides downstream filtering")
    func emptyTextPosts() throws {
        // Mirrors `FoliateSelectionDispatcher.emptyTextRoutes` —
        // the post helper is pure pipe-through. Filtering empty
        // selections is the bridge's job (and the parser's, where
        // applicable). Catching it here would silently swallow a
        // contract violation that should surface in development.
        let center = NotificationCenter()
        var fired = false
        let token = center.addObserver(
            forName: .readerSelectionPopoverRequested,
            object: nil,
            queue: nil
        ) { _ in fired = true }
        defer { center.removeObserver(token) }

        SelectionPopoverRequest.post(selection: makeSelection(text: ""), on: center)
        #expect(fired)
    }
}

// MARK: - Dismiss policy (Codex Gate 4 round 1, Medium)

@Suite("Feature #60 WI-7c1 — SelectionPopoverDismissPolicy")
@MainActor
struct SelectionPopoverDismissPolicyTests {

    private func makeSelection() -> TextSelectionInfo {
        TextSelectionInfo(
            selectedText: "the rapidity of the infection",
            startUTF16: 0,
            endUTF16: 29
        )
    }

    @Test(".dispatched clears the pending selection (sheet dismisses)")
    func dispatchedDismisses() {
        let selection = makeSelection()
        let result = SelectionPopoverActionRouter.Result.dispatched(.readerHighlightRequested)
        let next = SelectionPopoverDismissPolicy.nextPending(
            after: result,
            currentSelection: selection
        )
        #expect(next == nil)
    }

    @Test(".dispatched on any reader notification clears (not coupled to a specific name)")
    func dispatchedAnyName() {
        let selection = makeSelection()
        // Sanity: the dismiss policy is "any dispatch dismisses" —
        // not "only highlight dismisses". Note + Translate routes
        // should also dismiss when WI-7b's deferred cases eventually
        // shrink to zero.
        #expect(SelectionPopoverDismissPolicy.nextPending(
            after: .dispatched(.readerAnnotationRequested),
            currentSelection: selection
        ) == nil)
        #expect(SelectionPopoverDismissPolicy.nextPending(
            after: .dispatched(.readerTranslateRequested),
            currentSelection: selection
        ) == nil)
    }

    @Test(".deferredNotYetWired(.askAI) keeps the sheet open (no production pipeline yet)")
    func deferredAskAIKeepsOpen() {
        let selection = makeSelection()
        let next = SelectionPopoverDismissPolicy.nextPending(
            after: .deferredNotYetWired(.askAI),
            currentSelection: selection
        )
        // Auto-dismiss on a deferred action would silently swallow
        // the tap. The contract pins: keep the sheet open until the
        // pipeline lands (router result flips to `.dispatched`).
        #expect(next == selection)
    }

    @Test(".deferredNotYetWired(.read) keeps the sheet open")
    func deferredReadKeepsOpen() {
        let selection = makeSelection()
        let next = SelectionPopoverDismissPolicy.nextPending(
            after: .deferredNotYetWired(.read),
            currentSelection: selection
        )
        #expect(next == selection)
    }
}
#endif
