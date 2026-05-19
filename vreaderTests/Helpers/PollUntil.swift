// Purpose: Deterministic async-wait test helper. Bug #236 — tests that
// `Task.sleep(<fixed duration>)` then assert the result of background or
// timeline-driven async work are flaky: the work runs on wall-clock
// dispatch (DispatchQueue.main.asyncAfter, detached Tasks) that lags
// under CPU contention, so a fixed sleep can elapse before the work
// completes. `pollUntil` waits for the actual signal with a generous
// timeout instead of guessing a duration.
//
// @coordinates-with: XCUITestMockSpeechSynthesizerTests.swift,
//   BackgroundIndexingCoordinatorTests.swift

import Foundation

/// Polls `condition` every `interval` until it returns `true` or
/// `timeout` elapses, then returns. Use in place of a fixed `Task.sleep`
/// before asserting on async / background work whose completion time is
/// load-dependent.
///
/// The poll exits as soon as `condition` holds, so a passing test is no
/// slower than the work itself; the generous default `timeout` only
/// bounds the wait when the machine is starved. The caller still asserts
/// the expected state afterward — `pollUntil` only removes the flaky
/// fixed-duration guess, it does not itself fail the test on timeout.
@MainActor
func pollUntil(
    timeout: Duration = .seconds(20),
    interval: Duration = .milliseconds(20),
    _ condition: () async -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: interval)
    }
}
