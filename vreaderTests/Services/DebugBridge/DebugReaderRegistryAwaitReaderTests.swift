// Purpose: Tests for DebugReaderRegistry.awaitReader — covers the 5-case
// race matrix the v3/v4 plan called out (feature #49 WI-7a):
//   1. Reader already registered — fast-path returns immediately.
//   2. Reader registers AFTER awaiter installs — awaiter resumes.
//   3. Awaiter times out before any matching reader registers.
//   4. Two awaiters with different timeouts — token-based ownership ensures
//      neither resumes the other's continuation.
//   5. Multiple awaiters on the same key — all resume on a single register.
//
// All assertions use Swift Testing's #expect for clarity. Tests run on
// MainActor because the registry is @MainActor.

#if DEBUG

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("DebugReaderRegistry.awaitReader — feature #49 WI-7a")
struct DebugReaderRegistryAwaitReaderTests {

    /// Test-only fake probe satisfying the protocol.
    final class FakeProbe: DebugReaderProbe {
        let fingerprintKey: String
        let format: String
        var currentPositionString: String? = nil

        init(fingerprintKey: String, format: String = "txt") {
            self.fingerprintKey = fingerprintKey
            self.format = format
        }

        func awaitSettle(timeout: TimeInterval) async throws {}
        func evaluateJavaScript(_ script: String) async throws -> Data {
            throw DebugReaderProbeError.evalUnsupported(format: format)
        }
    }

    /// Each test gets its OWN isolated registry instance — not the
    /// `DebugReaderRegistry.shared` singleton. Bug #228: Swift Testing runs
    /// `@Test` methods in parallel, so a concurrent test's `shared.reset()`
    /// resumes every pending `waiters` entry with `.awaitReaderTimeout` —
    /// spuriously failing a sibling test suspended on `awaitReader`. (Same
    /// defect class as bug #227, which isolated the sibling `settle` suites;
    /// this is the `awaitReader`/`waiters` path.) An isolated instance per
    /// test removes that shared mutable state. A fresh instance starts
    /// empty — no `reset()` needed.
    private func makeRegistry() -> DebugReaderRegistry {
        DebugReaderRegistry.makeIsolatedForTests()
    }

    // MARK: - Case 1: fast path (reader already registered)

    @Test func case1_alreadyRegistered_returnsImmediately() async throws {
        let registry = makeRegistry()
        let probe = FakeProbe(fingerprintKey: "txt:abc:1024")
        registry.register(probe)

        let resolved = try await registry.awaitReader(
            fingerprintKey: "txt:abc:1024",
            timeout: 5.0
        )
        #expect(resolved.fingerprintKey == "txt:abc:1024")
    }

    // MARK: - Case 2: register after await installs

    @Test func case2_registerAfterInstall_resumesWaiter() async throws {
        let registry = makeRegistry()
        let probe = FakeProbe(fingerprintKey: "txt:def:2048")

        // Schedule the register on next runloop turn so the await call
        // installs first. Using Task.detached so it runs concurrently
        // with the await.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            registry.register(probe)
        }

        let resolved = try await registry.awaitReader(
            fingerprintKey: "txt:def:2048",
            timeout: 2.0
        )
        #expect(resolved.fingerprintKey == "txt:def:2048")
    }

    // MARK: - Case 3: timeout

    @Test func case3_noMatchingReader_throwsTimeout() async throws {
        let registry = makeRegistry()

        do {
            _ = try await registry.awaitReader(
                fingerprintKey: "nonexistent",
                timeout: 0.2
            )
            Issue.record("expected timeout")
        } catch DebugReaderRegistryError.awaitReaderTimeout(let key) {
            #expect(key == "nonexistent")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Case 4: two waiters, different timeouts (token isolation)

    @Test func case4_twoWaitersDifferentTimeouts_eachResumesOwnContinuation() async throws {
        let registry = makeRegistry()
        let probe = FakeProbe(fingerprintKey: "txt:ghi:512")

        // Waiter A times out first (short), waiter B times out later (long).
        // We DON'T register a probe — both should time out independently
        // without resuming each other.
        async let resultA: Result<DebugReaderProbe, Error> = {
            do {
                let p = try await registry.awaitReader(fingerprintKey: "txt:ghi:512", timeout: 0.15)
                return .success(p)
            } catch {
                return .failure(error)
            }
        }()
        async let resultB: Result<DebugReaderProbe, Error> = {
            do {
                let p = try await registry.awaitReader(fingerprintKey: "txt:ghi:512", timeout: 0.30)
                return .success(p)
            } catch {
                return .failure(error)
            }
        }()

        let (a, b) = await (resultA, resultB)

        // Both should time out (no register occurred).
        switch a {
        case .success: Issue.record("waiter A should have timed out")
        case .failure(let e):
            #expect((e as? DebugReaderRegistryError) == .awaitReaderTimeout(fingerprintKey: "txt:ghi:512"))
        }
        switch b {
        case .success: Issue.record("waiter B should have timed out")
        case .failure(let e):
            #expect((e as? DebugReaderRegistryError) == .awaitReaderTimeout(fingerprintKey: "txt:ghi:512"))
        }
        _ = probe // keep alive (not registered)
    }

    // MARK: - Case 5: multiple waiters, single register resumes all

    @Test func case5_multipleWaiters_singleRegisterResumesAll() async throws {
        let registry = makeRegistry()
        let probe = FakeProbe(fingerprintKey: "txt:jkl:256")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            registry.register(probe)
        }

        async let r1 = try registry.awaitReader(fingerprintKey: "txt:jkl:256", timeout: 2.0)
        async let r2 = try registry.awaitReader(fingerprintKey: "txt:jkl:256", timeout: 2.0)

        let (p1, p2) = try await (r1, r2)
        #expect(p1.fingerprintKey == "txt:jkl:256")
        #expect(p2.fingerprintKey == "txt:jkl:256")
    }

    // MARK: - Reset cancels pending waiters

    @Test func reset_cancelsPendingWaitersWithTimeoutError() async throws {
        let registry = makeRegistry()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            registry.reset()
        }

        do {
            _ = try await registry.awaitReader(
                fingerprintKey: "will-never-register",
                timeout: 5.0
            )
            Issue.record("expected timeout from reset")
        } catch DebugReaderRegistryError.awaitReaderTimeout {
            // expected — reset cancels with the same error type
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Bug #228: per-test registry isolation

    /// Bug #228 — the parallel-test isolation defect this fix closes.
    ///
    /// Before the fix, `makeRegistry()` returned `DebugReaderRegistry.shared`.
    /// Swift Testing runs `@Test` methods in parallel, so two test contexts
    /// holding "their own" registry actually shared one mutable object: a
    /// concurrent context's `reset()` resumes EVERY pending `waiters` entry
    /// with `.awaitReaderTimeout`, spuriously failing a sibling test that
    /// suspended on `awaitReader`. This test reproduces that interference
    /// deterministically by standing up the two contexts itself: context B
    /// suspends an `awaitReader` waiter; context A then calls `reset()`.
    ///
    /// Pre-fix (`makeRegistry()` → `.shared`): `registryA === registryB`, so
    /// A's `reset()` cancels B's suspended waiter — B resolves with a
    /// spurious `.awaitReaderTimeout` and the test fails.
    ///
    /// Post-fix (`makeRegistry()` → `makeIsolatedForTests()`): the two are
    /// distinct instances, A's `reset()` cannot reach B's `waiters`, and B's
    /// own `register(_:)` resolves its waiter with the real probe.
    @Test func bug228_concurrentResetOnSiblingRegistry_doesNotCancelOwnWaiter() async throws {
        let registryA = makeRegistry()
        let registryB = makeRegistry()

        // Structural guarantee: each test owns a distinct registry. This
        // assertion alone fails on the pre-fix code (both are `.shared`).
        #expect(registryA !== registryB)

        let probeB = FakeProbe(fingerprintKey: "txt:bug228:4096")

        // Background: mimic a concurrent sibling test calling `reset()` on
        // ITS registry (A), then this test's own registry (B) registering
        // the matching probe. With shared state, A's reset fires first and
        // cancels B's waiter; with isolation, only B's register resolves it.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms — A first
            registryA.reset()
            try? await Task.sleep(nanoseconds: 30_000_000) // 60ms — then B
            registryB.register(probeB)
        }

        let resolved = try await registryB.awaitReader(
            fingerprintKey: "txt:bug228:4096",
            timeout: 2.0
        )
        // Resolves with the real probe from B's register — NOT a spurious
        // timeout from A's reset.
        #expect(resolved.fingerprintKey == "txt:bug228:4096")
    }
}

#endif
