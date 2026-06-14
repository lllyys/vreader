// Purpose: Feature #60 WI-7c1 + WI-7c5a — pins the cross-boundary
// contract for the `.readerSelectionPopoverRequested` notification
// and the parse helper that turns the raw `Notification` into a
// typed `SelectionPopoverRequestPayload`. The SwiftUI sheet
// lifecycle inside `SelectionPopoverPresenterModifier` is
// integration / device-verify territory (sheet presents/dismisses
// are SwiftUI side-effects that don't unit-test cleanly). The
// unit-test surface this file pins is the public wire format that
// bridge swaps (WI-7c2–WI-7c5) post onto.
//
// **WI-7c5a contract change**: the notification `object` is now a
// `SelectionPopoverRequestPayload { selection, requestToken }`
// rather than a bare `TextSelectionInfo`. The token lets EPUB
// (WI-7c5b) round-trip a non-UTF-16 selection identity through the
// popover action pipeline. `payload(from:)` replaces the old
// `selection(from:)` and is migration-safe: a producer that still
// posts a bare `TextSelectionInfo` decodes as a tokenless payload.
//
// **Why a parse helper on the modifier's enum and not free-floating
// on `Notification`**: keeps the contract local to the presenter,
// mirroring `FoliateSelectionDispatcher.notificationUserInfo` /
// `FoliateMessageParser.parseSelection`. Bridges post via the
// helper's `post(selection:on:requestToken:)`; tests read it back
// via `payload(from:)`.

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

    @Test("payload(from:) round-trips a posted SelectionPopoverRequestPayload")
    func roundTrip() {
        let payload = SelectionPopoverRequestPayload(
            selection: makeSelection(),
            requestToken: nil
        )
        let note = Notification(
            name: .readerSelectionPopoverRequested,
            object: payload,
            userInfo: nil
        )
        let parsed = SelectionPopoverRequest.payload(from: note)
        #expect(parsed?.selection.selectedText == "the rapidity of the infection")
        #expect(parsed?.selection.startUTF16 == 1024)
        #expect(parsed?.selection.endUTF16 == 1053)
        #expect(parsed?.requestToken == nil)
    }

    @Test("payload(from:) carries the requestToken when one was posted")
    func roundTripWithToken() {
        let token = UUID()
        let payload = SelectionPopoverRequestPayload(
            selection: makeSelection(),
            requestToken: token
        )
        let note = Notification(
            name: .readerSelectionPopoverRequested,
            object: payload,
            userInfo: nil
        )
        let parsed = SelectionPopoverRequest.payload(from: note)
        #expect(parsed?.requestToken == token)
    }

    @Test("payload(from:) wraps a legacy bare TextSelectionInfo with a nil token")
    func legacyBareSelectionDecodes() {
        // Migration tolerance: a producer (or test) that posts a
        // bare `TextSelectionInfo` — the pre-WI-7c5a wire shape —
        // must still decode, as a tokenless request. This keeps
        // the WI-7c5a contract change from being a flag-day break.
        let note = Notification(
            name: .readerSelectionPopoverRequested,
            object: makeSelection(text: "legacy", start: 1, end: 7),
            userInfo: nil
        )
        let parsed = SelectionPopoverRequest.payload(from: note)
        #expect(parsed?.selection.selectedText == "legacy")
        #expect(parsed?.requestToken == nil)
    }

    @Test("payload(from:) returns nil when object is not a recognised shape")
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
        #expect(SelectionPopoverRequest.payload(from: note) == nil)
    }

    @Test("payload(from:) returns nil when object is nil")
    func nilObject() {
        let note = Notification(
            name: .readerSelectionPopoverRequested,
            object: nil,
            userInfo: nil
        )
        #expect(SelectionPopoverRequest.payload(from: note) == nil)
    }

    // MARK: - Post helper

    @Test("post(selection:on:) posts a payload with a nil token")
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
        let parsed = try #require(SelectionPopoverRequest.payload(from: note))
        #expect(parsed.selection.selectedText == "hello")
        #expect(parsed.selection.startUTF16 == 5)
        #expect(parsed.selection.endUTF16 == 10)
        #expect(parsed.requestToken == nil)
    }

    @Test("post(selection:on:requestToken:) posts a payload carrying the token")
    func postWithToken() throws {
        let center = NotificationCenter()
        var captured: Notification?
        let observer = center.addObserver(
            forName: .readerSelectionPopoverRequested,
            object: nil,
            queue: nil
        ) { note in captured = note }
        defer { center.removeObserver(observer) }

        let requestToken = UUID()
        SelectionPopoverRequest.post(
            selection: makeSelection(text: "epub para", start: 0, end: 9),
            on: center,
            requestToken: requestToken
        )

        let note = try #require(captured)
        let parsed = try #require(SelectionPopoverRequest.payload(from: note))
        #expect(parsed.selection.selectedText == "epub para")
        #expect(parsed.requestToken == requestToken)
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

// MARK: - Request payload value semantics (WI-7c5a)

@Suite("Feature #60 WI-7c5a — SelectionPopoverRequestPayload value semantics")
@MainActor
struct SelectionPopoverRequestPayloadTests {

    private func makeSelection(_ text: String = "abc") -> TextSelectionInfo {
        TextSelectionInfo(selectedText: text, startUTF16: 0, endUTF16: text.utf16.count)
    }

    @Test("Two payloads with the same selection + token are Equatable-equal")
    func equalWhenSameTokenAndSelection() {
        let token = UUID()
        let a = SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: token)
        let b = SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: token)
        #expect(a == b)
    }

    @Test("Payloads with different tokens are not equal")
    func unequalWhenDifferentToken() {
        let a = SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: UUID())
        let b = SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: UUID())
        #expect(a != b)
    }

    @Test("A nil-token payload differs from an otherwise-identical tokened payload")
    func nilTokenDiffersFromTokened() {
        let tokenless = SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: nil)
        let tokened = SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: UUID())
        #expect(tokenless != tokened)
    }
}

// MARK: - Dismiss policy (Codex Gate 4 round 1, Medium)

@Suite("Feature #60 WI-7c1 — SelectionPopoverDismissPolicy")
@MainActor
struct SelectionPopoverDismissPolicyTests {

    private func makePayload() -> SelectionPopoverRequestPayload {
        SelectionPopoverRequestPayload(
            selection: TextSelectionInfo(
                selectedText: "the rapidity of the infection",
                startUTF16: 0,
                endUTF16: 29
            ),
            requestToken: nil
        )
    }

    @Test(".dispatched clears the pending payload (sheet dismisses)")
    func dispatchedDismisses() {
        let payload = makePayload()
        let result = SelectionPopoverActionRouter.Result.dispatched(.readerHighlightRequested)
        let next = SelectionPopoverDismissPolicy.nextPending(
            after: result,
            currentPayload: payload
        )
        #expect(next == nil)
    }

    @Test(".dispatched on any reader notification clears (not coupled to a specific name)")
    func dispatchedAnyName() {
        let payload = makePayload()
        // Sanity: the dismiss policy is "any dispatch dismisses" —
        // not "only highlight dismisses". Note + Translate routes
        // should also dismiss when WI-7b's deferred cases eventually
        // shrink to zero.
        #expect(SelectionPopoverDismissPolicy.nextPending(
            after: .dispatched(.readerAnnotationRequested),
            currentPayload: payload
        ) == nil)
        #expect(SelectionPopoverDismissPolicy.nextPending(
            after: .dispatched(.readerTranslateRequested),
            currentPayload: payload
        ) == nil)
    }

    @Test("Feature #78: .dispatched(.readerAskAIRequested) dismisses the sheet")
    func dispatchedAskAIDismisses() {
        let payload = makePayload()
        // Feature #78 wired .askAI → .dispatched, so per the "any dispatch
        // dismisses" policy the popover now closes when the user taps Ask AI
        // (the AI panel takes over). Previously it was .deferredNotYetWired
        // and kept the sheet open.
        let next = SelectionPopoverDismissPolicy.nextPending(
            after: .dispatched(.readerAskAIRequested),
            currentPayload: payload
        )
        #expect(next == nil)
    }

    @Test("Feature #78: .dispatched(.readerReadAloudRequested) dismisses the sheet")
    func dispatchedReadDismisses() {
        let payload = makePayload()
        let next = SelectionPopoverDismissPolicy.nextPending(
            after: .dispatched(.readerReadAloudRequested),
            currentPayload: payload
        )
        #expect(next == nil)
    }
}

// MARK: - Outside-tap grace (Bug #351)

@Suite("Bug #351 — SelectionPopoverOutsideTapPolicy")
@MainActor
struct SelectionPopoverOutsideTapPolicyTests {

    // Bug #351: the #338 outside-tap dismissal (a simultaneous
    // SpatialTapGesture) fires on the selection's OWN terminal
    // finger-up — which lands on the text, outside the bottom card —
    // so a quick release dismisses the card the instant it appears.
    // The grace window ignores any outside tap that arrives within
    // `presentGrace` of the card being presented (that tap is the
    // selection's release, not a deliberate dismiss). A lingering
    // touch isn't a tap so it never reaches this path; a genuine
    // later dismiss tap lands after the grace.

    private let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test("An outside tap WITHIN the grace window does NOT dismiss (the selection's own release)")
    func tapWithinGraceIsIgnored() {
        let tap = t0.addingTimeInterval(0.05)  // instant release
        #expect(SelectionPopoverOutsideTapPolicy.shouldDismiss(
            presentedAt: t0, tapTime: tap) == false)
    }

    @Test("An outside tap AFTER the grace window dismisses (a deliberate dismiss)")
    func tapAfterGraceDismisses() {
        let tap = t0.addingTimeInterval(1.0)
        #expect(SelectionPopoverOutsideTapPolicy.shouldDismiss(
            presentedAt: t0, tapTime: tap) == true)
    }

    @Test("A tap exactly at the grace boundary dismisses (>= grace)")
    func tapAtBoundaryDismisses() {
        let tap = t0.addingTimeInterval(SelectionPopoverOutsideTapPolicy.presentGrace)
        #expect(SelectionPopoverOutsideTapPolicy.shouldDismiss(
            presentedAt: t0, tapTime: tap) == true)
    }

    @Test("A nil present-time falls back to dismissing (no grace to apply)")
    func nilPresentTimeDismisses() {
        #expect(SelectionPopoverOutsideTapPolicy.shouldDismiss(
            presentedAt: nil, tapTime: t0) == true)
    }

    @Test("The grace is long enough to cover an instant release but short enough to stay responsive")
    func graceMagnitudeIsReasonable() {
        #expect(SelectionPopoverOutsideTapPolicy.presentGrace >= 0.25)
        #expect(SelectionPopoverOutsideTapPolicy.presentGrace <= 0.5)
    }
}
#endif
