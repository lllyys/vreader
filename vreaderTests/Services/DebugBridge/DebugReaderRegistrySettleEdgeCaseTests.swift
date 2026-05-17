// Purpose: Render-settled edge-case tests for DebugReaderRegistry (bug
// #141). Covers the guard / rejection paths:
//   7. Stale-token write rejected — markReaderSettled with a token that
//      doesn't match the expected reader token is dropped (no resume, no
//      fast-path satisfied).
//   9a. Zero timeout throws settleTimeout immediately.
//   9b. Negative timeout throws settleTimeout (does NOT trap on the
//       `UInt64(timeout * 1e9)` conversion).
//   9c. Zero timeout still fast-paths when already settled — the
//       non-positive guard runs AFTER the fast-path check.
//
// Core happy-path settle + cleanup (unregister/reset/reopen) cases live in
// the sibling Settle{Core,Cleanup} suites.
// DEBUG-only — the registry and its settle machinery are #if DEBUG.

#if DEBUG

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("DebugReaderRegistry settle edge cases — bug #141")
struct DebugReaderRegistrySettleEdgeCaseTests {

    private func makeRegistry() -> DebugReaderRegistry {
        DebugReaderRegistry.shared.reset()
        return DebugReaderRegistry.shared
    }

    // MARK: - Case 7: stale-token write rejected

    @Test func case7_staleTokenMarkRejected() async throws {
        let registry = makeRegistry()
        let expected = UUID()
        let stale = UUID()
        registry.setExpectedReaderToken(expected)

        // A mark with the stale token must NOT satisfy a waiter on the
        // expected token, and must NOT establish a fast-path settled state.
        registry.markReaderSettled(for: "epub:yz1:8", token: stale)

        do {
            try await registry.awaitReaderSettled(
                for: "epub:yz1:8", token: expected, timeout: 0.2
            )
            Issue.record("stale-token mark should not satisfy expected-token wait")
        } catch DebugReaderProbeError.settleTimeout {
            // expected — stale mark dropped
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Case 9: non-positive timeout

    @Test func case9a_zeroTimeout_throwsSettleTimeout() async throws {
        let registry = makeRegistry()
        do {
            try await registry.awaitReaderSettled(
                for: "epub:zt:1", token: UUID(), timeout: 0
            )
            Issue.record("expected settleTimeout for zero timeout")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func case9b_negativeTimeout_throwsSettleTimeoutNotTrap() async throws {
        // A negative timeout must NOT trap on the `UInt64(timeout * 1e9)`
        // conversion — it must surface settleTimeout cleanly.
        let registry = makeRegistry()
        do {
            try await registry.awaitReaderSettled(
                for: "epub:nt:1", token: UUID(), timeout: -5.0
            )
            Issue.record("expected settleTimeout for negative timeout")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func case9c_zeroTimeout_stillFastPathsWhenSettled() async throws {
        // A zero timeout still returns immediately if already settled —
        // the non-positive guard runs AFTER the fast-path check.
        let registry = makeRegistry()
        let token = UUID()
        registry.markReaderSettled(for: "epub:zts:1", token: token)
        try await registry.awaitReaderSettled(
            for: "epub:zts:1", token: token, timeout: 0
        )
    }
}

#endif
