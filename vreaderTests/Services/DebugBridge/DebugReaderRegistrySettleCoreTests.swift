// Purpose: Core render-settled tests for DebugReaderRegistry (bug #141).
// Covers the happy-path settle machinery:
//   1. Already-settled fast path — awaitReaderSettled returns immediately.
//   2. Suspend-then-resume — markReaderSettled wakes a pending waiter.
//   3. Timeout — no markReaderSettled before deadline throws settleTimeout.
//   4. Two waiters, different timeouts — token-based ownership; neither
//      resumes the other's continuation.
//   5. Multiple waiters on the same (key, token) — one mark resumes all.
//   7b. Matching-token mark accepted when an expected token is set.
//   8. Settle keyed by (fingerprintKey, token) — a mark for a different
//      key/token does not satisfy a waiter on this key/token.
//
// Cleanup (unregister/reset/reopen) and edge cases (stale token,
// non-positive timeout) live in the sibling Settle{Cleanup,EdgeCase}
// suites. DEBUG-only — the registry and its settle machinery are #if DEBUG.

#if DEBUG

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("DebugReaderRegistry settle core — bug #141")
struct DebugReaderRegistrySettleCoreTests {

    private func makeRegistry() -> DebugReaderRegistry {
        DebugReaderRegistry.shared.reset()
        return DebugReaderRegistry.shared
    }

    // MARK: - Case 1: already-settled fast path

    @Test func case1_alreadySettled_returnsImmediately() async throws {
        let registry = makeRegistry()
        let token = UUID()
        registry.markReaderSettled(for: "epub:abc:1024", token: token)

        // Should return without suspending — a tight timeout still passes.
        try await registry.awaitReaderSettled(
            for: "epub:abc:1024", token: token, timeout: 0.05
        )
    }

    // MARK: - Case 2: suspend then resume

    @Test func case2_markResumesPendingWaiter() async throws {
        let registry = makeRegistry()
        let token = UUID()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            registry.markReaderSettled(for: "epub:def:2048", token: token)
        }

        // No fast path — must suspend until the mark above fires.
        try await registry.awaitReaderSettled(
            for: "epub:def:2048", token: token, timeout: 2.0
        )
    }

    // MARK: - Case 3: timeout

    @Test func case3_noMark_throwsSettleTimeout() async throws {
        let registry = makeRegistry()
        let token = UUID()

        do {
            try await registry.awaitReaderSettled(
                for: "epub:ghi:512", token: token, timeout: 0.2
            )
            Issue.record("expected settleTimeout")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Case 4: two waiters, different timeouts (token isolation)

    @Test func case4_twoWaitersDifferentTimeouts_eachResumesOwn() async throws {
        let registry = makeRegistry()
        let token = UUID()

        // Neither is marked — both must time out independently without
        // resuming each other's continuation.
        async let resultA: Result<Void, Error> = {
            do {
                try await registry.awaitReaderSettled(
                    for: "epub:jkl:256", token: token, timeout: 0.15
                )
                return .success(())
            } catch {
                return .failure(error)
            }
        }()
        async let resultB: Result<Void, Error> = {
            do {
                try await registry.awaitReaderSettled(
                    for: "epub:jkl:256", token: token, timeout: 0.30
                )
                return .success(())
            } catch {
                return .failure(error)
            }
        }()

        let (a, b) = await (resultA, resultB)
        switch a {
        case .success: Issue.record("waiter A should have timed out")
        case .failure(let e):
            #expect((e as? DebugReaderProbeError) == .settleTimeout)
        }
        switch b {
        case .success: Issue.record("waiter B should have timed out")
        case .failure(let e):
            #expect((e as? DebugReaderProbeError) == .settleTimeout)
        }
    }

    // MARK: - Case 5: multiple waiters, single mark resumes all

    @Test func case5_multipleWaiters_singleMarkResumesAll() async throws {
        let registry = makeRegistry()
        let token = UUID()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            registry.markReaderSettled(for: "epub:mno:128", token: token)
        }

        async let r1: Void = registry.awaitReaderSettled(
            for: "epub:mno:128", token: token, timeout: 2.0
        )
        async let r2: Void = registry.awaitReaderSettled(
            for: "epub:mno:128", token: token, timeout: 2.0
        )
        try await (r1, r2)
    }

    // MARK: - Case 7b: matching-token mark accepted when expected token set

    @Test func case7b_matchingTokenMarkAccepted() async throws {
        let registry = makeRegistry()
        let token = UUID()
        registry.setExpectedReaderToken(token)
        registry.markReaderSettled(for: "epub:yz2:8", token: token)

        // Matching token — fast path satisfied.
        try await registry.awaitReaderSettled(
            for: "epub:yz2:8", token: token, timeout: 0.05
        )
    }

    // MARK: - Case 8: settle keyed by (fingerprintKey, token)

    @Test func case8_settleKeyedByKeyAndToken() async throws {
        let registry = makeRegistry()
        let tokenA = UUID()
        let tokenB = UUID()

        // Mark settled for key1/tokenA — a waiter on key1/tokenB must
        // still suspend (different token).
        registry.markReaderSettled(for: "epub:k1:1", token: tokenA)
        do {
            try await registry.awaitReaderSettled(
                for: "epub:k1:1", token: tokenB, timeout: 0.2
            )
            Issue.record("mark for tokenA should not satisfy tokenB wait")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }

        // And a waiter on a different key must also suspend.
        do {
            try await registry.awaitReaderSettled(
                for: "epub:k2:2", token: tokenA, timeout: 0.2
            )
            Issue.record("mark for key1 should not satisfy key2 wait")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}

#endif
