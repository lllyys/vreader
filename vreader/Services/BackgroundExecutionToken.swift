// Purpose: Feature #98 — a single-use handle over UIKit's
// `beginBackgroundTask`/`endBackgroundTask` so in-flight translation work
// survives the ~30s grace window iOS grants after backgrounding, behind a
// protocol seam tests can record against.
//
// Key decisions:
// - **Explicit `end()` is the contract.** `deinit` only logs a leak in DEBUG —
//   calling back into the requester from a nonisolated deinit is a Swift 6
//   isolation hazard (Gate-2 audit, feature #98 plan).
// - `.invalid` from the requester (iOS denied background time) degrades to a
//   no-op token: `end()` does nothing, behavior matches today's un-wrapped
//   code. UIKit asserts on `endBackgroundTask(.invalid)`, so the guard is
//   load-bearing, not defensive decoration.
// - On expiry the token runs the caller's `onExpiry` and then self-ends —
//   iOS terminates apps whose expiration handlers don't end their tasks.
//
// @coordinates-with: ChapterReTranslateViewModel.swift,
//   BookTranslationCoordinator.swift,
//   dev-docs/plans/20260611-feature-98-background-resilient-translation.md

import Foundation
import OSLog
import UIKit
import os

// MARK: - Requester seam

/// The slice of `UIApplication` the token needs. Production conforms
/// `UIApplication`; tests inject a recorder.
@MainActor
protocol BackgroundTaskRequesting: AnyObject, Sendable {
    func beginTask(
        name: String,
        expirationHandler: @escaping @MainActor () -> Void
    ) -> UIBackgroundTaskIdentifier

    func endTask(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: BackgroundTaskRequesting {
    func beginTask(
        name: String,
        expirationHandler: @escaping @MainActor () -> Void
    ) -> UIBackgroundTaskIdentifier {
        beginBackgroundTask(withName: name) {
            // UIKit documents the expiration handler runs on the main
            // thread; hop formally so the @MainActor closure is callable.
            MainActor.assumeIsolated { expirationHandler() }
        }
    }

    func endTask(_ identifier: UIBackgroundTaskIdentifier) {
        endBackgroundTask(identifier)
    }
}

// MARK: - Expiry latch

/// A one-way latch the main-actor expiration handler SETS synchronously and
/// a job loop READS synchronously between work units (Gate-4 round-2 Medium:
/// a fire-and-forget actor hop from the handler can lose the race against
/// the loop's next check, starting another unit after iOS already expired
/// the window). Lock-backed, `Sendable`, no suspension on either side.
final class BackgroundExpiryLatch: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: false)

    /// Sets the latch. Idempotent; never resets.
    func set() {
        storage.withLock { $0 = true }
    }

    var isSet: Bool {
        storage.withLock { $0 }
    }
}

// MARK: - Token

/// One acquired background-execution window. `@MainActor` (and therefore
/// `Sendable`) so an actor-side job can hold it across awaits and release it
/// with `await token.end()`.
@MainActor
final class BackgroundExecutionToken {

    /// Shared end-state, captured STRONGLY by the expiration handler (Gate-4
    /// round-1 Medium): a token dropped without `end()` must still self-end
    /// at expiry — iOS terminates apps whose handlers don't end their tasks.
    /// Both `end()` and the handler consume it idempotently.
    @MainActor
    private final class EndState {
        // nonisolated(unsafe): mutated only on the main actor; the DEBUG
        // leak log in the token's nonisolated deinit reads it best-effort.
        nonisolated(unsafe) var identifier: UIBackgroundTaskIdentifier = .invalid
        let requester: any BackgroundTaskRequesting

        init(requester: any BackgroundTaskRequesting) {
            self.requester = requester
        }

        func end() {
            guard identifier != .invalid else { return }
            let id = identifier
            identifier = .invalid
            requester.endTask(id)
        }
    }

    private let state: EndState
    // nonisolated: the DEBUG leak log runs from deinit (nonisolated context).
    private nonisolated static let log = Logger(
        subsystem: "com.vreader.app", category: "BackgroundExecutionToken")

    private init(state: EndState) {
        self.state = state
    }

    /// Begins a background task and returns its token. `onExpiry` runs on the
    /// main actor when iOS expires the window; the window self-ends right
    /// after it — even if the token itself was already dropped, because the
    /// handler holds the end-state strongly. A denied request (`.invalid`)
    /// returns a no-op token.
    static func acquire(
        name: String,
        using requester: any BackgroundTaskRequesting,
        onExpiry: @escaping @MainActor () -> Void = {}
    ) -> BackgroundExecutionToken {
        let state = EndState(requester: requester)
        state.identifier = requester.beginTask(name: name) {
            onExpiry()
            state.end()
        }
        return BackgroundExecutionToken(state: state)
    }

    /// Ends the background task. Idempotent — the normal completion path and
    /// the expiry self-end may both call it; only the first reaches UIKit.
    func end() {
        state.end()
    }

    deinit {
        #if DEBUG
        // Best-effort contract check only — the expiry handler's strong
        // end-state capture already guarantees the window can't outlive
        // expiry, leaked token or not.
        if state.identifier != .invalid {
            Self.log.error("BackgroundExecutionToken leaked without end() — the background window stays open until expiry")
        }
        #endif
    }
}
