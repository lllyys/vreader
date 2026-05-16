// Purpose: Feature #60 WI-7b — pins the routing contract between
// `SelectionPopoverAction` (the dispatch enum from WI-3) and the
// existing reader-bridge notification surface
// (`.readerHighlightRequested`, `.readerAnnotationRequested`,
// `.readerTranslateRequested`).
//
// The router is the pure-logic glue that the future WI-7c production
// view (which captures the long-press selection and presents
// `SelectionPopoverView` from WI-7a) will call when the user taps a
// row in the popover. Keeping the mapping in a static helper —
// rather than inside a SwiftUI view body or coordinator — lets the
// contract be tested without touching UIKit or NotificationCenter
// globals.
//
// **Deferred actions (`.askAI`, `.read`)**: feature #60's plan ships
// the View + router + WI-7c wiring sequentially. `.askAI` and
// `.read` have no production consumer yet (no `.readerAskAIRequested`
// or `.readerReadAloudRequested` exists in `ReaderNotifications`).
// The router returns `.deferredNotYetWired` rather than silently
// no-opping, so test runs and future audits can prove a regression
// would surface (instead of hiding behind a `default: break`).

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
            selection: makeSelection(),
            notificationCenter: center
        )
        #expect(result == .dispatched(.readerAnnotationRequested))
    }

    @Test("Result.deferredNotYetWired carries the unwired action")
    func deferredReturnsAction() {
        let center = makeIsolatedCenter()
        let askResult = SelectionPopoverActionRouter.route(
            action: .askAI,
            selection: makeSelection(),
            notificationCenter: center
        )
        #expect(askResult == .deferredNotYetWired(.askAI))

        let readResult = SelectionPopoverActionRouter.route(
            action: .read,
            selection: makeSelection(),
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
                selection: makeSelection(),
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
                selection: makeSelection(),
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
                selection: makeSelection(),
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
                selection: makeSelection(),
                notificationCenter: center
            )
        }
        #expect(received.userInfo?["color"] as? String == "blue")
    }

    // MARK: - Note + Translate routing

    @Test("note posts .readerAnnotationRequested with selection (no userInfo)")
    func noteRoutes() throws {
        let received = try captureNotification(name: .readerAnnotationRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .note,
                selection: makeSelection(),
                notificationCenter: center
            )
        }
        let info = try #require(received.object as? TextSelectionInfo)
        #expect(info.selectedText == "the rapidity of the infection")
        // Note has no color/userInfo — pure object payload.
        #expect(received.userInfo == nil || received.userInfo?["color"] == nil)
    }

    @Test("translate posts .readerTranslateRequested with selection")
    func translateRoutes() throws {
        let received = try captureNotification(name: .readerTranslateRequested) { center in
            _ = SelectionPopoverActionRouter.route(
                action: .translate,
                selection: makeSelection(),
                notificationCenter: center
            )
        }
        let info = try #require(received.object as? TextSelectionInfo)
        #expect(info.endUTF16 == 1053)
    }

    // MARK: - Deferred .askAI / .read do not post

    @Test("askAI does NOT post any of the routed notifications")
    func askAINeverPosts() {
        let center = makeIsolatedCenter()
        let fired = noRoutedNotificationFires(on: center) {
            _ = SelectionPopoverActionRouter.route(
                action: .askAI,
                selection: makeSelection(),
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
                selection: makeSelection(),
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
