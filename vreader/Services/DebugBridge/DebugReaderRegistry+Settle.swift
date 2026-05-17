// Purpose: Render-settled signal for DebugReaderRegistry (bug #141). Lets
// `vreader-debug://settle` block until a reader has reached a real
// render-complete state instead of the 100ms `Task.sleep` placeholder in
// `DebugReaderProbeAdapter.awaitSettle`.
//
// Wiring: per-format hosts call `markReaderSettled(for:token:)` once the
// render is genuinely complete — EPUB from `EPUBWebViewBridge.Coordinator
// .webView(_:didFinish:)` (WKWebView page-load), AZW3/MOBI from the Foliate
// `relocate` message handler (foliate-js fires `relocate` only after the
// book is paginated and the first location is rendered — `didFinish` is
// just the HTML shell). `ReaderContainerView.onAppear` wires
// `probe.settleStrategy` to `awaitReaderSettled(...)` for `.epub` / `.azw3`.
//
// State (`settledKeys`, `settleWaiters`) is stored on `DebugReaderRegistry`
// itself — Swift extensions cannot add stored properties — and cleared by
// the registry's `unregister(_:)` / `reset()`.
//
// @coordinates-with DebugReaderRegistry.swift, DebugReaderProbeAdapter.swift,
//   EPUBWebViewBridgeCoordinator.swift, FoliateViewCoordinator.swift,
//   FoliateSpikeView.swift, ReaderContainerView.swift
// DEBUG-only.

#if DEBUG

import Foundation

extension DebugReaderRegistry {

    /// Record that the reader for `(fingerprintKey, token)` has reached a
    /// real render-complete state, and resume every pending settle waiter
    /// on that exact key.
    ///
    /// Applies the same stale-write guard as `setActiveEPUBWebView`: when an
    /// `expectedReaderToken` is set and the incoming `token` doesn't match,
    /// the call is a stale render-complete callback from an outgoing reader
    /// and is silently dropped — it must neither establish a fast-path
    /// settled flag nor resume a waiter belonging to the current reader.
    ///
    /// Idempotent: marking an already-settled key again is a harmless
    /// no-op (the key is already in `settledKeys`; there are no waiters
    /// left to resume).
    func markReaderSettled(for fingerprintKey: String, token: UUID) {
        if let expected = expectedReaderTokenForTests, expected != token {
            return // stale render-complete callback; ignore
        }
        let key = SettleKey(fingerprintKey: fingerprintKey, token: token)
        settledKeys.insert(key)
        // Resume every waiter on this exact key.
        if let bucket = settleWaiters[key], !bucket.isEmpty {
            settleWaiters[key] = nil
            for waiter in bucket {
                waiter.continuation.resume()
            }
        }
    }

    /// Suspend until the reader for `(fingerprintKey, token)` has signalled
    /// render-complete via `markReaderSettled`, or throw `settleTimeout`.
    ///
    /// Fast path: if the key is already settled, returns immediately.
    /// Otherwise installs a token-identified waiter and suspends; the
    /// waiter is resumed by `markReaderSettled`, or removed-and-failed by
    /// the timeout `Task`. Token-based ownership ensures two concurrent
    /// waiters on the same key with different timeouts each resume their
    /// OWN continuation (mirrors `awaitReader`'s `Waiter` machinery).
    ///
    /// - Throws: `DebugReaderProbeError.settleTimeout` if no
    ///   `markReaderSettled` for this key arrives before the deadline.
    func awaitReaderSettled(
        for fingerprintKey: String,
        token: UUID,
        timeout: TimeInterval
    ) async throws {
        let key = SettleKey(fingerprintKey: fingerprintKey, token: token)
        // Fast path: already settled.
        if settledKeys.contains(key) {
            return
        }
        // A non-positive timeout can never produce a render-complete
        // wait — and `UInt64(timeout * 1e9)` would trap for a negative
        // value. Surface `settleTimeout` immediately instead.
        guard timeout > 0 else {
            throw DebugReaderProbeError.settleTimeout
        }

        let waiterToken = UUID()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.removeAndTimeoutSettle(key: key, waiterToken: waiterToken)
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let waiter = SettleWaiter(token: waiterToken, continuation: continuation)
                settleWaiters[key, default: []].append(waiter)
            }
            // Resumed by markReaderSettled — cancel the now-moot timeout.
            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }

    /// Internal: remove a specific settle waiter (by token) and resume it
    /// with `settleTimeout`. Identified by token so concurrent waiters on
    /// the same key don't resume each other's continuations.
    private func removeAndTimeoutSettle(key: SettleKey, waiterToken: UUID) {
        guard var bucket = settleWaiters[key],
              let idx = bucket.firstIndex(where: { $0.token == waiterToken }) else {
            return
        }
        let waiter = bucket.remove(at: idx)
        if bucket.isEmpty {
            settleWaiters[key] = nil
        } else {
            settleWaiters[key] = bucket
        }
        waiter.continuation.resume(throwing: DebugReaderProbeError.settleTimeout)
    }

    /// Internal: drop render-settled state for `fingerprintKey` and resume
    /// any pending settle waiters on that key with a timeout error. Called
    /// from `unregister(_:)` so a leaving reader's settled flag can't
    /// fast-path a freshly-mounted reader on the same key, and an in-flight
    /// `settle` doesn't hang past the reader's life.
    ///
    /// - Parameter preservingToken: when non-nil, `(fingerprintKey,
    ///   preservingToken)` is left untouched. This protects an INCOMING
    ///   reader's settle state during the same-key reopen race: reader A
    ///   is replaced by reader B (same book, new token), then A's late
    ///   `unregister` fires — A must clear its OWN stale state without
    ///   clobbering B's. B's token is the registry's `expectedReaderToken`
    ///   at that moment. Pass `nil` to clear every token for the key
    ///   (used when the leaving probe is genuinely the last reader).
    func clearSettleState(
        forFingerprintKey fingerprintKey: String,
        preservingToken: UUID? = nil
    ) {
        settledKeys = settledKeys.filter {
            $0.fingerprintKey != fingerprintKey || $0.token == preservingToken
        }
        let matching = settleWaiters.filter {
            $0.key.fingerprintKey == fingerprintKey && $0.key.token != preservingToken
        }
        for (key, bucket) in matching {
            settleWaiters[key] = nil
            for waiter in bucket {
                waiter.continuation.resume(throwing: DebugReaderProbeError.settleTimeout)
            }
        }
    }
}

#endif
