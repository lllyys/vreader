// Purpose: Tests for FoliateDebugSeekFractionObserver.forward — the Bug #267
// load-bearing hop that re-posts a harness `.debugBridgeSeekFraction` onto the
// spike's key-filtered `.foliateRequestSeekFraction` channel, injecting the
// active book's fingerprintKey. The spike's seek observer filters by key, so a
// typo in the notification name or the "fingerprintKey" payload would silently
// break the seek — this suite pins both.
//
// The type is DEBUG-only (#if DEBUG); vreaderTests builds against the Debug app
// so the symbol is available, and the suite is gated to match.
//
// @coordinates-with: FoliateDebugSeekFractionObserver.swift,
//   DebugBridgeNotifications.swift, ReaderNotifications.swift, GH #1157

#if DEBUG

import XCTest
@testable import vreader

@MainActor
final class FoliateDebugSeekFractionObserverTests: XCTestCase {

    func test_forward_rePostsFoliateSeekFractionWithFractionAndKey() {
        let exp = expectation(description: "foliateRequestSeekFraction posted")
        nonisolated(unsafe) var receivedFraction: Double?
        nonisolated(unsafe) var receivedKey: String?
        let token = NotificationCenter.default.addObserver(
            forName: .foliateRequestSeekFraction, object: nil, queue: .main
        ) { note in
            receivedFraction = note.userInfo?["fraction"] as? Double
            receivedKey = note.userInfo?["fingerprintKey"] as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let input = Notification(
            name: .debugBridgeSeekFraction, object: nil, userInfo: ["fraction": 0.5]
        )
        FoliateDebugSeekFractionObserver.forward(input, fingerprintKey: "azw3:abc:128650")

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(receivedFraction, 0.5)
        XCTAssertEqual(receivedKey, "azw3:abc:128650", "must inject the container's key so the spike's key-filtered observer fires")
    }

    func test_forward_withNoFraction_isNoOp() {
        let exp = expectation(description: "no forward expected")
        exp.isInverted = true
        let token = NotificationCenter.default.addObserver(
            forName: .foliateRequestSeekFraction, object: nil, queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        let input = Notification(name: .debugBridgeSeekFraction, object: nil, userInfo: [:])
        FoliateDebugSeekFractionObserver.forward(input, fingerprintKey: "azw3:abc:1")

        wait(for: [exp], timeout: 0.5)
    }
}

#endif
