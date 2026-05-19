// Purpose: Render-settled cleanup tests for DebugReaderRegistry (bug #141).
// Covers settle-state teardown on reader lifecycle transitions:
//   6a. unregister clears settled state — a later await suspends again
//       rather than fast-pathing on stale settled state.
//   6b. reset clears settled state.
//   6c. reset cancels pending settle waiters with settleTimeout.
//   10. unregister cancels a pending settle waiter (resumes with timeout,
//       doesn't hang to the deadline).
//   11. same-key reopen race — reader A replaced by reader B for the same
//       book; A's late unregister clears A's stale state but preserves B's.
//   11b. A's late unregister does NOT cancel a waiter on B's token.
//
// Core happy-path settle + non-positive-timeout / stale-token edge cases
// live in the sibling Settle{Core,EdgeCase} suites.
// DEBUG-only — the registry and its settle machinery are #if DEBUG.

#if DEBUG

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("DebugReaderRegistry settle cleanup — bug #141")
struct DebugReaderRegistrySettleCleanupTests {

    /// Each test gets its OWN isolated registry instance — not the
    /// `DebugReaderRegistry.shared` singleton. Bug #227: Swift Testing runs
    /// `@Test` methods in parallel, so when a test (e.g. `case11b`) kept a
    /// `settleWaiter` suspended across a ~100ms window, a concurrent test's
    /// `shared.reset()` wiped `settleWaiters` and resumed the waiter with a
    /// spurious `.settleTimeout`. An isolated instance per test removes the
    /// shared mutable state, making every case deterministic under
    /// parallel execution. A fresh instance starts empty — no `reset()`
    /// needed.
    private func makeRegistry() -> DebugReaderRegistry {
        DebugReaderRegistry.makeIsolatedForTests()
    }

    // MARK: - Case 6a: unregister clears settled state

    @Test func case6a_unregisterClearsSettledState() async throws {
        let registry = makeRegistry()
        let token = UUID()
        let probe = SettleStubProbe(key: "epub:pqr:64", fmt: "epub")
        registry.register(probe)
        registry.markReaderSettled(for: "epub:pqr:64", token: token)
        registry.unregister(probe)

        // Settled state for that key was cleared — awaiting again must
        // suspend (and time out) rather than fast-path on stale state.
        do {
            try await registry.awaitReaderSettled(
                for: "epub:pqr:64", token: token, timeout: 0.2
            )
            Issue.record("expected settleTimeout after unregister cleared state")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Case 6b: reset clears settled state

    @Test func case6b_resetClearsSettledState() async throws {
        let registry = makeRegistry()
        let token = UUID()
        registry.markReaderSettled(for: "epub:stu:32", token: token)
        registry.reset()

        do {
            try await registry.awaitReaderSettled(
                for: "epub:stu:32", token: token, timeout: 0.2
            )
            Issue.record("expected settleTimeout after reset cleared state")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Case 6c: reset cancels pending settle waiters

    @Test func case6c_resetCancelsPendingSettleWaiters() async throws {
        let registry = makeRegistry()
        let token = UUID()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            registry.reset()
        }

        do {
            try await registry.awaitReaderSettled(
                for: "epub:vwx:16", token: token, timeout: 5.0
            )
            Issue.record("expected settleTimeout from reset")
        } catch DebugReaderProbeError.settleTimeout {
            // expected — reset resumes pending settle waiters with timeout
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Case 10: unregister cancels a pending settle waiter

    @Test func case10_unregisterCancelsPendingWaiter() async throws {
        let registry = makeRegistry()
        let token = UUID()
        let probe = SettleStubProbe(key: "epub:upw:1", fmt: "epub")
        registry.register(probe)

        // Install a waiter (no mark), then unregister the probe while the
        // waiter is suspended — the waiter must resume with settleTimeout
        // rather than hang to its 5s deadline.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            registry.unregister(probe)
        }
        do {
            try await registry.awaitReaderSettled(
                for: "epub:upw:1", token: token, timeout: 5.0
            )
            Issue.record("expected settleTimeout from unregister")
        } catch DebugReaderProbeError.settleTimeout {
            // expected — unregister resumes the pending waiter
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Case 11: same-key reopen race — old reader's late unregister
    // must not clear the incoming reader's settle state.

    @Test func case11_sameKeyReopen_oldUnregisterPreservesNewReaderSettle() async throws {
        let registry = makeRegistry()
        let key = "epub:reopen:1"
        let tokenA = UUID()
        let tokenB = UUID()

        // Reader A mounts: expected token = A, A settles.
        let probeA = SettleStubProbe(key: key, fmt: "epub")
        registry.setExpectedReaderToken(tokenA)
        registry.register(probeA)
        registry.markReaderSettled(for: key, token: tokenA)

        // Reader B mounts for the SAME book before A's onDisappear:
        // expected token flips to B, B settles.
        let probeB = SettleStubProbe(key: key, fmt: "epub")
        registry.setExpectedReaderToken(tokenB)
        registry.register(probeB)
        registry.markReaderSettled(for: key, token: tokenB)

        // A's late onDisappear fires. A is no longer activeReader (B is),
        // so the old code skipped settle cleanup entirely — but A's
        // cleanup must run AND must preserve B's (key, tokenB) settle
        // state (B is the expected token).
        registry.unregister(probeA)

        // B is still settled — a zero-timeout await fast-paths.
        try await registry.awaitReaderSettled(for: key, token: tokenB, timeout: 0)

        // A's stale settle state was cleared — awaiting on tokenA suspends
        // and times out.
        do {
            try await registry.awaitReaderSettled(for: key, token: tokenA, timeout: 0.2)
            Issue.record("reader A's stale settle state should have been cleared")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func case11b_sameKeyReopen_oldUnregisterCancelsOnlyOwnWaiter() async throws {
        let registry = makeRegistry()
        let key = "epub:reopen2:1"
        let tokenA = UUID()
        let tokenB = UUID()

        let probeA = SettleStubProbe(key: key, fmt: "epub")
        registry.setExpectedReaderToken(tokenA)
        registry.register(probeA)

        let probeB = SettleStubProbe(key: key, fmt: "epub")
        registry.setExpectedReaderToken(tokenB)
        registry.register(probeB)

        // A waiter on B's token is pending. A's late unregister must NOT
        // resume it (B is the live reader) — only B's own mark should.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            registry.unregister(probeA)
            try? await Task.sleep(nanoseconds: 50_000_000)
            registry.markReaderSettled(for: key, token: tokenB)
        }
        // If A's unregister wrongly cancelled B's waiter, this throws.
        // It should instead resolve via B's mark.
        try await registry.awaitReaderSettled(for: key, token: tokenB, timeout: 2.0)
    }
}

#endif
