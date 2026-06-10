// Purpose: Feature #98 WI-1 — lifecycle tests for `BackgroundExecutionToken`,
// the RAII-style wrapper over `beginBackgroundTask`/`endBackgroundTask`
// behind the `BackgroundTaskRequesting` seam. Contract under test: begin on
// acquire, end exactly once on (possibly repeated) `end()`, expiry fires
// `onExpiry` then self-ends, and a denied request (`.invalid`) short-circuits
// to a no-op token.
//
// @coordinates-with: BackgroundExecutionToken.swift,
//   MockBackgroundTaskRequester.swift,
//   dev-docs/plans/20260611-feature-98-background-resilient-translation.md

import Testing
import Foundation
import UIKit
@testable import vreader

@MainActor
@Suite("BackgroundExecutionToken")
struct BackgroundExecutionTokenTests {

    @Test func acquire_beginsTask_andEndEndsIt() {
        let requester = MockBackgroundTaskRequester()
        let token = BackgroundExecutionToken.acquire(
            name: "test.translate", using: requester)

        #expect(requester.begins == ["test.translate"])
        #expect(requester.ends.isEmpty, "no end before release")

        token.end()
        #expect(requester.ends == [UIBackgroundTaskIdentifier(rawValue: 1)])
    }

    @Test func end_isIdempotent_singleEndDespiteDoubleRelease() {
        let requester = MockBackgroundTaskRequester()
        let token = BackgroundExecutionToken.acquire(
            name: "test.translate", using: requester)

        token.end()
        token.end()
        token.end()
        #expect(requester.ends.count == 1, "double-release must not double-end")
    }

    @Test func expiry_firesOnExpiry_thenSelfEnds() {
        let requester = MockBackgroundTaskRequester()
        var expiryFired = false
        let token = BackgroundExecutionToken.acquire(
            name: "test.translate", using: requester,
            onExpiry: { expiryFired = true })

        requester.fireExpiry(rawIdentifier: 1)

        #expect(expiryFired, "onExpiry must run when iOS expires the task")
        #expect(requester.ends == [UIBackgroundTaskIdentifier(rawValue: 1)],
                "the token must self-end inside the expiration handler — iOS kills apps that don't")

        // A later explicit end() (the normal completion path racing the
        // expiry) must not double-end.
        token.end()
        #expect(requester.ends.count == 1)
    }

    /// Gate-4 round-1 Medium: a token DROPPED without end() must still
    /// self-end at expiry — the expiration handler owns the end-state
    /// strongly, so iOS never sees an unended task even on the leak path.
    @Test func leakedToken_expiryStillEndsTheTask() {
        let requester = MockBackgroundTaskRequester()
        do {
            _ = BackgroundExecutionToken.acquire(
                name: "test.translate", using: requester)
        }  // token dropped here without end()

        requester.fireExpiry(rawIdentifier: 1)

        #expect(requester.ends == [UIBackgroundTaskIdentifier(rawValue: 1)],
                "the expiration handler must end the task even after the token was dropped")
    }

    @Test func deniedRequest_invalidIdentifier_endIsNoOp() {
        let requester = MockBackgroundTaskRequester()
        requester.denyRequests = true
        let token = BackgroundExecutionToken.acquire(
            name: "test.translate", using: requester)

        #expect(requester.begins.count == 1, "the begin is still attempted")
        token.end()
        #expect(requester.ends.isEmpty,
                ".invalid must never be passed to endBackgroundTask (UIKit asserts)")
    }
}
