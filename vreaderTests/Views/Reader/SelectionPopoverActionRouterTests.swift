// Purpose: Feature #60 WI-7b + WI-7c5a — pins the routing contract
// between `SelectionPopoverAction` (the dispatch enum from WI-3) and
// the existing reader-bridge notification surface
// (`.readerHighlightRequested`, `.readerAnnotationRequested`,
// `.readerTranslateRequested`).
//
// The router is the pure-logic glue that the WI-7c production views
// call when the user taps a row in the popover. Keeping the mapping
// in a static helper — rather than inside a SwiftUI view body or
// coordinator — lets the contract be tested without touching UIKit
// or NotificationCenter globals.
//
// **WI-7c5a contract change**: `route` now takes a
// `SelectionPopoverRequestPayload` (selection + optional
// `requestToken`) instead of a bare `TextSelectionInfo`. When the
// payload carries a token, the router attaches it to the action
// notification's `userInfo["selectionRequestToken"]` as a `UUID` so
// a format with a non-UTF-16 anchor model (EPUB — WI-7c5b) can
// resolve which cached selection the action belongs to. The posted
// `object` stays a bare `TextSelectionInfo` so the existing TXT/MD
// `ReaderNotificationModifier` consumers are unaffected.
//
// **Deferred actions (`.askAI`, `.read`)**: feature #60's plan ships
// the View + router + WI-7c wiring sequentially. `.askAI` and
// `.read` have no production consumer yet. The router returns
// `.deferredNotYetWired` rather than silently no-opping, so test
// runs and future audits can prove a regression would surface.

import Testing
import Foundation
@testable import vreader

@Suite("Feature #60 WI-7b — SelectionPopoverActionRouter")
@MainActor
struct SelectionPopoverActionRouterTests {

    // MARK: - Setup

    private func makeSelection() -> TextSelectionInfo {
        TextSelectionInfo(
            selectedText: "the rapidity of the infection",
            startUTF16: 1024,
            endUTF16: 1053
        )
    }

    /// Tokenless payload — the TXT/MD/chunked producer shape.
    private func makePayload() -> SelectionPopoverRequestPayload {
        SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: nil)
    }

    /// Tokened payload — the EPUB producer shape (WI-7c5b).
    private func makeTokenedPayload(_ token: UUID) -> SelectionPopoverRequestPayload {
        SelectionPopoverRequestPayload(selection: makeSelection(), requestToken: token)
    }

    /// Isolated NotificationCenter (not `.default`) so tests don't
    /// observe spurious traffic from concurrent app state.
    private func makeIsolatedCenter() -> NotificationCenter {
        NotificationCenter()
    }

    // MARK: - Result-enum surface

    @Test("Result.dispatched carries the posted Notification.Name")
    func dispatchedCarriesNotificationName() {
        let center = makeIsolatedCenter()
        let result = SelectionPopoverActionRouter.route(
            action: .note,
            payload: makePayload(),
            notificationCenter: center
        )
        #expect(result == .dispatched(.readerAnnotationRequested))
    }

    @Test("Result.deferredNotYetWired carries the unwired action")
    func deferredReturnsAction() {
        let center = makeIsolatedCenter()
        let askResult = SelectionPopoverActionRouter.route(
            action: .askAI,
            payload: makePayload(),
            notificationCenter: center
        )
        #expect(askResult == .deferredNotYetWired(.askAI))

        let readResult = SelectionPopoverActionRouter.route(
            action: .read,
            payload: makePayload(),
            notificationCenter: center
        )
        #expect(readResult == .deferredNotYetWired(.read))
    }

    // MARK: - Highlight color routing

    @Test("highlight(.yellow) posts .readerHighlightRequested with selection + color")
    func yellowHighlightRoutes() throws {
        let received = try captureNotification(name: .readerHighlightRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .highlight(.yellow),
                payload: makePayload(),
                notificationCenter: center
            )
        }
        let info = try #require(received.object as? TextSelectionInfo)
        #expect(info.selectedText == "the rapidity of the infection")
        #expect(info.startUTF16 == 1024)
        #expect(info.endUTF16 == 1053)
        #expect(received.userInfo?["color"] as? String == "yellow")
    }

    @Test("highlight(.pink) posts color='pink' in userInfo")
    func pinkHighlightCarriesColor() throws {
        let received = try captureNotification(name: .readerHighlightRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .highlight(.pink),
                payload: makePayload(),
                notificationCenter: center
            )
        }
        #expect(received.userInfo?["color"] as? String == "pink")
    }

    @Test("highlight(.green) posts color='green' in userInfo")
    func greenHighlightCarriesColor() throws {
        let received = try captureNotification(name: .readerHighlightRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .highlight(.green),
                payload: makePayload(),
                notificationCenter: center
            )
        }
        #expect(received.userInfo?["color"] as? String == "green")
    }

    @Test("highlight(.blue) posts color='blue' in userInfo")
    func blueHighlightCarriesColor() throws {
        let received = try captureNotification(name: .readerHighlightRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .highlight(.blue),
                payload: makePayload(),
                notificationCenter: center
            )
        }
        #expect(received.userInfo?["color"] as? String == "blue")
    }

    // MARK: - Note + Translate routing

    @Test("note posts .readerAnnotationRequested with selection (no userInfo for a tokenless payload)")
    func noteRoutes() throws {
        let received = try captureNotification(name: .readerAnnotationRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .note,
                payload: makePayload(),
                notificationCenter: center
            )
        }
        let info = try #require(received.object as? TextSelectionInfo)
        #expect(info.selectedText == "the rapidity of the infection")
        // Tokenless payload + no color → no userInfo at all.
        #expect(received.userInfo == nil)
    }

    @Test("translate posts .readerTranslateRequested with selection")
    func translateRoutes() throws {
        let received = try captureNotification(name: .readerTranslateRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .translate,
                payload: makePayload(),
                notificationCenter: center
            )
        }
        let info = try #require(received.object as? TextSelectionInfo)
        #expect(info.endUTF16 == 1053)
    }

    // MARK: - Request-token pass-through (WI-7c5a)

    @Test("highlight with a tokened payload attaches selectionRequestToken (UUID) to userInfo")
    func highlightCarriesRequestToken() throws {
        let requestToken = UUID()
        let received = try captureNotification(name: .readerHighlightRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .highlight(.yellow),
                payload: makeTokenedPayload(requestToken),
                notificationCenter: center
            )
        }
        // The token rides as a `UUID` — not a String — because the
        // notification is in-process; there is no Codable boundary.
        #expect(received.userInfo?["selectionRequestToken"] as? UUID == requestToken)
        // The color contract is unaffected by the token.
        #expect(received.userInfo?["color"] as? String == "yellow")
    }

    @Test("note with a tokened payload attaches selectionRequestToken to userInfo")
    func noteCarriesRequestToken() throws {
        let requestToken = UUID()
        let received = try captureNotification(name: .readerAnnotationRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .note,
                payload: makeTokenedPayload(requestToken),
                notificationCenter: center
            )
        }
        #expect(received.userInfo?["selectionRequestToken"] as? UUID == requestToken)
    }

    @Test("translate with a tokened payload attaches selectionRequestToken to userInfo")
    func translateCarriesRequestToken() throws {
        let requestToken = UUID()
        let received = try captureNotification(name: .readerTranslateRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .translate,
                payload: makeTokenedPayload(requestToken),
                notificationCenter: center
            )
        }
        #expect(received.userInfo?["selectionRequestToken"] as? UUID == requestToken)
    }

    @Test("a tokenless payload attaches NO selectionRequestToken key")
    func tokenlessPayloadOmitsTokenKey() throws {
        // Negative pin: TXT/MD/chunked producers pass a nil token;
        // the router must not invent a key. EPUB's WI-7c5b consumer
        // distinguishes "this action belongs to my cached selection"
        // by the presence of the key.
        let received = try captureNotification(name: .readerHighlightRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .highlight(.yellow),
                payload: makePayload(),
                notificationCenter: center
            )
        }
        #expect(received.userInfo?["selectionRequestToken"] == nil)
    }

    // MARK: - Deferred .askAI / .read do not post

    @Test("askAI does NOT post any of the routed notifications")
    func askAINeverPosts() {
        let center = makeIsolatedCenter()
        let fired = noRoutedNotificationFires(on: center) {
            _ = SelectionPopoverActionRouter.route(
                action: .askAI,
                payload: makePayload(),
                notificationCenter: center
            )
        }
        #expect(!fired)
    }

    @Test("read does NOT post any of the routed notifications")
    func readNeverPosts() {
        let center = makeIsolatedCenter()
        let fired = noRoutedNotificationFires(on: center) {
            _ = SelectionPopoverActionRouter.route(
                action: .read,
                payload: makePayload(),
                notificationCenter: center
            )
        }
        #expect(!fired)
    }

    // MARK: - Observation helpers (synchronous — NotificationCenter
    // posts on the same thread for non-queued observers, so we
    // capture and resume in-line.)

    /// Adds a same-thread observer, runs `emit`, returns the captured
    /// notification. Throws if no post lands during `emit`.
    private func captureNotification(
        name: Notification.Name,
        emit: (NotificationCenter) -> Void
    ) throws -> Notification {
        let center = makeIsolatedCenter()
        var captured: Notification?
        let token = center.addObserver(
            forName: name,
            object: nil,
            queue: nil  // nil queue = synchronous, same-thread delivery
        ) { note in
            captured = note
        }
        defer { center.removeObserver(token) }
        emit(center)
        guard let note = captured else {
            throw ObserveError.notificationNotFired(name)
        }
        return note
    }

    /// Returns true iff any of the three routed notifications fired
    /// during `block`. Used for the deferred-action assertions.
    private func noRoutedNotificationFires(
        on center: NotificationCenter,
        _ block: () -> Void
    ) -> Bool {
        var fired = false
        let names: [Notification.Name] = [
            .readerHighlightRequested,
            .readerAnnotationRequested,
            .readerTranslateRequested,
        ]
        let tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                fired = true
            }
        }
        defer { tokens.forEach { center.removeObserver($0) } }
        block()
        return fired
    }

    private enum ObserveError: Error {
        case notificationNotFired(Notification.Name)
    }
}
