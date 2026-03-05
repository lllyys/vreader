// Purpose: Tests for ReadingSessionTracker — state machine, idempotency, grace resume,
// discard, 24h cap, crash recovery, periodic flush.

import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

/// Mock clock for deterministic time control in tests.
struct MockClock: MonotonicClockProtocol {
    var currentUptime: TimeInterval
    var currentWallClock: Date

    init(uptime: TimeInterval = 1000, wallClock: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.currentUptime = uptime
        self.currentWallClock = wallClock
    }

    func uptime() -> TimeInterval { currentUptime }
    func now() -> Date { currentWallClock }

    /// Returns a new clock advanced by the given seconds.
    func advanced(by seconds: TimeInterval) -> MockClock {
        MockClock(
            uptime: currentUptime + seconds,
            wallClock: currentWallClock.addingTimeInterval(seconds)
        )
    }
}

/// In-memory session store for testing.
@MainActor
final class MockSessionStore: SessionPersisting {
    private(set) var savedSessions: [ReadingSession] = []
    private(set) var discardedSessionIds: [UUID] = []
    private(set) var flushedDurations: [(UUID, Int)] = []
    var unclosedSessions: [ReadingSession] = []

    func saveSession(_ session: ReadingSession) throws {
        savedSessions.append(session)
    }

    func discardSession(id: UUID) throws {
        discardedSessionIds.append(id)
    }

    func flushDuration(sessionId: UUID, durationSeconds: Int) throws {
        flushedDurations.append((sessionId, durationSeconds))
    }

    func fetchUnclosedSessions() throws -> [ReadingSession] {
        unclosedSessions
    }
}

// MARK: - Fixtures

private let epubFP = DocumentFingerprint(
    contentSHA256: "tracker_test_epub_sha256_000000000000000000000000000000000000",
    fileByteCount: 5000,
    format: .epub
)

private let pdfFP = DocumentFingerprint(
    contentSHA256: "tracker_test_pdf_sha256_0000000000000000000000000000000000000",
    fileByteCount: 8000,
    format: .pdf
)

private let txtFP = DocumentFingerprint(
    contentSHA256: "tracker_test_txt_sha256_0000000000000000000000000000000000000",
    fileByteCount: 3000,
    format: .txt
)

// MARK: - Basic Lifecycle

@Suite("ReadingSessionTracker - Lifecycle")
@MainActor
struct ReadingSessionTrackerLifecycleTests {

    @Test func startCreatesActiveSession() throws {
        let store = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        #expect(tracker.state.isActive)
        #expect(store.savedSessions.count == 1)
        #expect(store.savedSessions.first?.bookFingerprintKey == epubFP.canonicalKey)
        #expect(store.savedSessions.first?.deviceId == "dev-1")
    }

    @Test func endClosesActiveSession() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        clock = clock.advanced(by: 60)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(tracker.state.isIdle)
        let saved = store.savedSessions.last
        #expect(saved?.endedAt != nil)
        #expect(saved?.durationSeconds == 60)
    }

    @Test func startThenEndThenStartCreatesNewSession() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let firstSessionId = tracker.currentSessionId

        clock = clock.advanced(by: 60)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        clock = clock.advanced(by: 10)
        tracker.updateClock(clock)
        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let secondSessionId = tracker.currentSessionId

        #expect(firstSessionId != secondSessionId)
        #expect(tracker.state.isActive)
    }
}

// MARK: - Idempotency

@Suite("ReadingSessionTracker - Idempotency")
@MainActor
struct ReadingSessionTrackerIdempotencyTests {

    @Test func doubleStartIsNoOp() throws {
        let store = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let firstId = tracker.currentSessionId
        let savedCountAfterFirst = store.savedSessions.count

        // Second start for same book should be no-op
        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let secondId = tracker.currentSessionId

        #expect(firstId == secondId)
        #expect(store.savedSessions.count == savedCountAfterFirst)
    }

    @Test func doubleEndIsNoOp() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        clock = clock.advanced(by: 30)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(tracker.state.isIdle)

        // Second end should be no-op, no crash
        tracker.endSessionIfNeeded()
        #expect(tracker.state.isIdle)
    }

    @Test func endWhenNeverStartedIsNoOp() {
        let store = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        // Should not crash
        tracker.endSessionIfNeeded()
        #expect(tracker.state.isIdle)
        #expect(store.savedSessions.isEmpty)
    }

    @Test func startDifferentBookWhileActiveEndsOldStartsNew() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let firstId = tracker.currentSessionId

        clock = clock.advanced(by: 60)
        tracker.updateClock(clock)

        try tracker.startSessionIfNeeded(bookFingerprint: pdfFP)
        let secondId = tracker.currentSessionId

        #expect(firstId != secondId)
        #expect(tracker.state.isActive)
        // Old session should have been ended
        let ended = store.savedSessions.first(where: { $0.sessionId == firstId })
        #expect(ended?.endedAt != nil)
        #expect(ended?.durationSeconds == 60)
    }
}

// MARK: - Grace Resume

@Suite("ReadingSessionTracker - Grace Resume")
@MainActor
struct ReadingSessionTrackerGraceResumeTests {

    @Test func foregroundWithin30sResumesSameSession() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let sessionId = tracker.currentSessionId

        // Go to background
        clock = clock.advanced(by: 20)
        tracker.updateClock(clock)
        tracker.pause()
        #expect(tracker.state.isPausedGrace)

        // Foreground within 30s
        clock = clock.advanced(by: 10) // total pause = 10s < 30s
        tracker.updateClock(clock)
        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        #expect(tracker.currentSessionId == sessionId)
        #expect(tracker.state.isActive)
    }

    @Test func foregroundAtExactly30sResumesSameSession() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let sessionId = tracker.currentSessionId

        clock = clock.advanced(by: 10)
        tracker.updateClock(clock)
        tracker.pause()

        // Exactly at grace boundary
        clock = clock.advanced(by: 30)
        tracker.updateClock(clock)
        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        // 30s is the boundary — should still resume
        #expect(tracker.currentSessionId == sessionId)
        #expect(tracker.state.isActive)
    }

    @Test func foregroundAfter31sStartsNewSession() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let sessionId = tracker.currentSessionId

        clock = clock.advanced(by: 10)
        tracker.updateClock(clock)
        tracker.pause()

        // Past grace period
        clock = clock.advanced(by: 31)
        tracker.updateClock(clock)
        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        #expect(tracker.currentSessionId != sessionId)
        #expect(tracker.state.isActive)
    }

    @Test func foregroundDifferentBookDuringGraceEndsOldStartsNew() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        let epubSessionId = tracker.currentSessionId

        clock = clock.advanced(by: 10)
        tracker.updateClock(clock)
        tracker.pause()

        // Different book, within grace period
        clock = clock.advanced(by: 5)
        tracker.updateClock(clock)
        try tracker.startSessionIfNeeded(bookFingerprint: pdfFP)

        #expect(tracker.currentSessionId != epubSessionId)
        #expect(tracker.state.isActive)
    }

    @Test func endDuringGraceClosesSession() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        clock = clock.advanced(by: 20)
        tracker.updateClock(clock)
        tracker.pause()

        clock = clock.advanced(by: 5)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(tracker.state.isIdle)
    }
}

// MARK: - Discard (<5s)

@Suite("ReadingSessionTracker - Short Session Discard")
@MainActor
struct ReadingSessionTrackerDiscardTests {

    @Test func sessionUnder5sIsDiscarded() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        guard let sessionId = tracker.currentSessionId else {
            Issue.record("Expected active session")
            return
        }

        // Only 4 seconds elapsed
        clock = clock.advanced(by: 4)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(tracker.state.isIdle)
        #expect(store.discardedSessionIds.contains(sessionId))
    }

    @Test func sessionExactly5sIsKept() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        guard let sessionId = tracker.currentSessionId else {
            Issue.record("Expected active session")
            return
        }

        clock = clock.advanced(by: 5)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(tracker.state.isIdle)
        #expect(!store.discardedSessionIds.contains(sessionId))
        let saved = store.savedSessions.first(where: { $0.sessionId == sessionId && $0.endedAt != nil })
        #expect(saved != nil)
        #expect(saved?.durationSeconds == 5)
    }

    @Test func sessionExactly4_9sIsDiscarded() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        guard let sessionId = tracker.currentSessionId else {
            Issue.record("Expected active session")
            return
        }

        clock = clock.advanced(by: 4.9)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(store.discardedSessionIds.contains(sessionId))
    }

    @Test func zeroLengthSessionIsDiscarded() throws {
        let store = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        guard let sessionId = tracker.currentSessionId else {
            Issue.record("Expected active session")
            return
        }

        // End immediately, no time advance
        tracker.endSessionIfNeeded()

        #expect(store.discardedSessionIds.contains(sessionId))
    }
}

// MARK: - 24h Cap

@Suite("ReadingSessionTracker - 24h Cap")
@MainActor
struct ReadingSessionTrackerCapTests {

    @Test func sessionOver24hIsCapped() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        // Advance 25 hours
        clock = clock.advanced(by: 25 * 3600)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        // The session's duration should be capped at 24h (86400s)
        let ended = store.savedSessions.last(where: { $0.endedAt != nil })
        #expect(ended != nil)
        #expect(ended?.durationSeconds ?? 0 <= 86400)
    }

    @Test func sessionExactly24hIsKept() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        clock = clock.advanced(by: 86400) // exactly 24h
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        let ended = store.savedSessions.last(where: { $0.endedAt != nil })
        #expect(ended?.durationSeconds == 86400)
    }
}

// MARK: - Crash Recovery

@Suite("ReadingSessionTracker - Crash Recovery")
@MainActor
struct ReadingSessionTrackerCrashRecoveryTests {

    @Test func recoverClosesStaleSessions() throws {
        let store = MockSessionStore()
        let clock = MockClock()

        // Simulate stale session from previous app launch
        let staleSession = ReadingSession(
            bookFingerprint: epubFP,
            startedAt: Date(timeIntervalSince1970: 1_699_990_000),
            endedAt: nil, // never closed
            durationSeconds: 300,
            deviceId: "dev-1"
        )
        store.unclosedSessions = [staleSession]

        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")
        try tracker.recoverStaleSessions()

        // Stale session should be closed with isRecovered = true
        let recovered = store.savedSessions.first(where: { $0.sessionId == staleSession.sessionId })
        #expect(recovered != nil)
        #expect(recovered?.isRecovered == true)
        #expect(recovered?.endedAt != nil)
        // Duration should use the last flushed value (300s)
        #expect(recovered?.durationSeconds == 300)
    }

    @Test func recoverWithNoStaleSessions() throws {
        let store = MockSessionStore()
        let clock = MockClock()

        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")
        try tracker.recoverStaleSessions()

        // No sessions to recover, nothing saved
        #expect(store.savedSessions.isEmpty)
    }

    @Test func recoverMultipleStaleSessions() throws {
        let store = MockSessionStore()
        let clock = MockClock()

        let stale1 = ReadingSession(
            bookFingerprint: epubFP,
            startedAt: Date(timeIntervalSince1970: 1_699_990_000),
            endedAt: nil,
            durationSeconds: 100,
            deviceId: "dev-1"
        )
        let stale2 = ReadingSession(
            bookFingerprint: pdfFP,
            startedAt: Date(timeIntervalSince1970: 1_699_995_000),
            endedAt: nil,
            durationSeconds: 200,
            deviceId: "dev-1"
        )
        store.unclosedSessions = [stale1, stale2]

        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")
        try tracker.recoverStaleSessions()

        let recoveredIds = store.savedSessions.filter { $0.isRecovered }.map(\.sessionId)
        #expect(recoveredIds.contains(stale1.sessionId))
        #expect(recoveredIds.contains(stale2.sessionId))
    }
}

// MARK: - Record Progress

@Suite("ReadingSessionTracker - Record Progress")
@MainActor
struct ReadingSessionTrackerProgressTests {

    @Test func recordProgressWhenIdleIsNoOp() {
        let store = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        let locator = Locator(
            bookFingerprint: epubFP,
            href: "ch1.xhtml", progression: 0.5, totalProgression: 0.1,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        // Should not crash when idle
        tracker.recordProgress(locator: locator)
        #expect(tracker.state.isIdle)
    }

    @Test func recordProgressWhenActiveUpdatesLocator() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        let locator = Locator(
            bookFingerprint: epubFP,
            href: "ch3.xhtml", progression: 0.8, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )

        clock = clock.advanced(by: 10)
        tracker.updateClock(clock)
        tracker.recordProgress(locator: locator)

        #expect(tracker.currentEndLocator?.href == "ch3.xhtml")
    }
}

// MARK: - Periodic Flush

@Suite("ReadingSessionTracker - Periodic Flush")
@MainActor
struct ReadingSessionTrackerFlushTests {

    @Test func flushReportsDuration() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        guard let sessionId = tracker.currentSessionId else {
            Issue.record("Expected active session")
            return
        }

        clock = clock.advanced(by: 60)
        tracker.updateClock(clock)
        try tracker.periodicFlush()

        #expect(store.flushedDurations.count == 1)
        #expect(store.flushedDurations.first?.0 == sessionId)
        #expect(store.flushedDurations.first?.1 == 60)
    }

    @Test func flushWhenIdleIsNoOp() throws {
        let store = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.periodicFlush()
        #expect(store.flushedDurations.isEmpty)
    }
}

// MARK: - Duration Monotonic Clock

@Suite("ReadingSessionTracker - Monotonic Duration")
@MainActor
struct ReadingSessionTrackerMonotonicTests {

    @Test func durationUsesUptimeNotWallClock() throws {
        let store = MockSessionStore()
        // Start with uptime=1000, wallClock=arbitrary
        var clock = MockClock(uptime: 1000, wallClock: Date(timeIntervalSince1970: 1_700_000_000))
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        // Advance uptime by 120s but wall clock by 300s (simulating clock adjustment)
        clock = MockClock(
            uptime: 1120,
            wallClock: Date(timeIntervalSince1970: 1_700_000_300)
        )
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        // Duration should be 120 (uptime delta), not 300 (wall clock delta)
        let ended = store.savedSessions.last(where: { $0.endedAt != nil })
        #expect(ended?.durationSeconds == 120)
    }
}

// MARK: - Multi-format canonical

@Suite("ReadingSessionTracker - Format Agnostic")
@MainActor
struct ReadingSessionTrackerFormatAgnosticTests {

    @Test func worksWithEPUB() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        clock = clock.advanced(by: 60)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(store.savedSessions.last?.bookFingerprint.format == .epub)
    }

    @Test func worksWithPDF() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: pdfFP)
        clock = clock.advanced(by: 60)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(store.savedSessions.last?.bookFingerprint.format == .pdf)
    }

    @Test func worksWithTXT() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: txtFP)
        clock = clock.advanced(by: 60)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        #expect(store.savedSessions.last?.bookFingerprint.format == .txt)
    }
}

// MARK: - Grace + Discard Interaction

@Suite("ReadingSessionTracker - Grace + Discard Interaction")
@MainActor
struct ReadingSessionTrackerGraceDiscardTests {

    @Test func graceResumedSessionExcludesPauseTime() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        // Active for 3s, then pause
        clock = clock.advanced(by: 3)
        tracker.updateClock(clock)
        tracker.pause()

        // Grace for 10s (within 30s), then resume same book
        clock = clock.advanced(by: 10)
        tracker.updateClock(clock)
        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        // Active for 4 more seconds
        clock = clock.advanced(by: 4)
        tracker.updateClock(clock)
        tracker.endSessionIfNeeded()

        // Duration = 3 (before pause) + 4 (after resume) = 7, excluding pause time
        let ended = store.savedSessions.last(where: { $0.endedAt != nil })
        #expect(ended?.durationSeconds == 7)
    }

    @Test func graceExpiredSessionUnder5sIsDiscarded() throws {
        let store = MockSessionStore()
        var clock = MockClock()
        let tracker = ReadingSessionTracker(clock: clock, store: store, deviceId: "dev-1")

        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)
        guard let firstId = tracker.currentSessionId else {
            Issue.record("Expected active session")
            return
        }

        // Active for 3s, then pause
        clock = clock.advanced(by: 3)
        tracker.updateClock(clock)
        tracker.pause()

        // Grace expired (31s)
        clock = clock.advanced(by: 31)
        tracker.updateClock(clock)

        // Start same book — should close old (3s < 5s → discard) and start new
        try tracker.startSessionIfNeeded(bookFingerprint: epubFP)

        #expect(store.discardedSessionIds.contains(firstId))
        #expect(tracker.currentSessionId != firstId)
    }
}
