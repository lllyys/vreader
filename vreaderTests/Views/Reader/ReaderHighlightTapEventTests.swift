// Purpose: Tests for `ReaderHighlightTapEvent` payload + the
// `.readerHighlightTapped` notification (Feature #53 / GH #596).
// Foundational WI-1 — verifies value-type semantics, Sendable conformance
// (implicit via @Sendable closure tests), and notification round-trip.
//
// @coordinates-with: ReaderNotifications.swift

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("ReaderHighlightTapEvent")
struct ReaderHighlightTapEventTests {

    @Test
    func eventIsValueTypeAndEquatable() {
        let id = UUID()
        let rect = CGRect(x: 10, y: 20, width: 80, height: 18)
        let a = ReaderHighlightTapEvent(highlightID: id, sourceRect: rect)
        let b = ReaderHighlightTapEvent(highlightID: id, sourceRect: rect)
        #expect(a == b)
    }

    @Test
    func eventsWithDifferentIDsAreNotEqual() {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let a = ReaderHighlightTapEvent(highlightID: UUID(), sourceRect: rect)
        let b = ReaderHighlightTapEvent(highlightID: UUID(), sourceRect: rect)
        #expect(a != b)
    }

    @Test
    func eventsWithDifferentRectsAreNotEqual() {
        let id = UUID()
        let a = ReaderHighlightTapEvent(
            highlightID: id,
            sourceRect: CGRect(x: 10, y: 20, width: 80, height: 18)
        )
        let b = ReaderHighlightTapEvent(
            highlightID: id,
            sourceRect: CGRect(x: 11, y: 20, width: 80, height: 18)
        )
        #expect(a != b)
    }

    @Test
    func sourceRectIsPreservedThroughNotificationRoundTrip() async {
        let id = UUID()
        let rect = CGRect(x: 42.5, y: 13.25, width: 100, height: 22)
        let posted = ReaderHighlightTapEvent(highlightID: id, sourceRect: rect)

        let tokenBox = TapTokenBox()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let token = NotificationCenter.default.addObserver(
                forName: .readerHighlightTapped,
                object: nil,
                queue: .main
            ) { notification in
                guard let received = notification.object as? ReaderHighlightTapEvent else {
                    Issue.record("notification.object was not ReaderHighlightTapEvent")
                    cont.resume()
                    return
                }
                #expect(received.highlightID == id)
                #expect(received.sourceRect == rect)
                cont.resume()
            }
            tokenBox.token = token

            NotificationCenter.default.post(
                name: .readerHighlightTapped,
                object: posted
            )
        }
        if let t = tokenBox.token { NotificationCenter.default.removeObserver(t) }
    }
}

/// Thread-safe holder for an NSObjectProtocol observer token. Lets the test
/// install the token after the closure that uses it is constructed, avoiding
/// Swift 6 capture-of-Sendable-self pitfalls.
private final class TapTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _token: NSObjectProtocol?
    var token: NSObjectProtocol? {
        get { lock.lock(); defer { lock.unlock() }; return _token }
        set { lock.lock(); _token = newValue; lock.unlock() }
    }
}
