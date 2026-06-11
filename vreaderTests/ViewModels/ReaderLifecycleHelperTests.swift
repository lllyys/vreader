// Purpose: Tests for ReaderLifecycleHelper's feature #101 additions — the
// once-at-open book-totals attach, the combined time readout (nil before
// attach / nil before session time accrues), the first-session variant,
// the stats-store fetch at beginSession, the close() reset, and the
// `.readerSessionTimeDidChange` bus mirror.

import Foundation
import Testing
@testable import vreader

// MARK: - Stubs

private struct StubPositionStore: ReadingPositionPersisting {
    func loadPosition(bookFingerprintKey: String) async throws -> Locator? { nil }
    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws {}
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws {}
}

private struct StubSessionStore: SessionPersisting {
    func saveSession(_ session: ReadingSession) throws {}
    func discardSession(id: UUID) throws {}
    func flushDuration(sessionId: UUID, durationSeconds: Int) throws {}
    func fetchUnclosedSessions() throws -> [ReadingSession] { [] }
}

/// Feature #101 stats seam stub — returns a canned record (or nil).
private struct StubStatsProvider: BookReadingStatsProviding {
    let record: ReadingStatsRecord?
    func readingStats(forBookWithKey key: String) async throws -> ReadingStatsRecord? {
        record
    }
}

/// Gate-4 r1 High regression: a SLOW provider whose first call returns a
/// poison total — if a cancelled/stale first fetch still attaches, the
/// readout shows 3h 5m instead of the second call's 6h 40m.
private actor SlowCountingStatsProvider: BookReadingStatsProviding {
    private var calls = 0
    func readingStats(forBookWithKey key: String) async throws -> ReadingStatsRecord? {
        calls += 1
        let call = calls
        try await Task.sleep(for: .milliseconds(300))
        return statsRecord(
            key: key,
            totalSeconds: call == 1 ? 11_111 : 24_000,  // poison vs real
            sessionCount: 5
        )
    }
}

private func makeFingerprint() -> DocumentFingerprint {
    DocumentFingerprint(
        contentSHA256: String(repeating: "ab", count: 32),
        fileByteCount: 4096, format: .epub
    )
}

private func statsRecord(
    key: String, totalSeconds: Int, sessionCount: Int
) -> ReadingStatsRecord {
    ReadingStatsRecord(
        bookFingerprintKey: key, totalReadingSeconds: totalSeconds,
        sessionCount: sessionCount, lastReadAt: nil,
        averagePagesPerHour: nil, averageWordsPerMinute: nil,
        totalPagesRead: nil, totalWordsRead: nil, longestSessionSeconds: 0
    )
}

@MainActor
private func makeHelper(
    statsStore: (any BookReadingStatsProviding)? = nil
) -> ReaderLifecycleHelper {
    let fp = makeFingerprint()
    return ReaderLifecycleHelper(
        bookFingerprint: fp,
        positionService: ReaderPositionService(
            bookFingerprintKey: fp.canonicalKey,
            deviceId: "test",
            persistence: StubPositionStore()
        ),
        sessionTracker: ReadingSessionTracker(
            clock: SystemClock(), store: StubSessionStore(), deviceId: "test"
        ),
        positionStore: StubPositionStore(),
        statsStore: statsStore
    )
}

// MARK: - Tests

@Suite("ReaderLifecycleHelper time readout (feature #101)")
@MainActor
struct ReaderLifecycleHelperTimeReadoutTests {

    @Test func readoutIsNilBeforeTotalsAttach() async throws {
        let helper = makeHelper()  // no stats store → totals never attach
        try helper.beginSession()
        helper.updateTimeDisplays()
        #expect(helper.timeReadoutDisplay == nil)
        await helper.close(locator: nil)
    }

    @Test func readoutIsNilAfterAttachButBeforeSessionTimeAccrues() async throws {
        let helper = makeHelper()
        try helper.beginSession()
        helper.attachBookTotals(totalSecondsAtOpen: 24_000, isFirstSession: false)
        // Zero session seconds → combinedReadout nil → pages pinned.
        #expect(helper.timeReadoutDisplay == nil)
        await helper.close(locator: nil)
    }

    @Test func readoutCombinesSessionAndLiveTotalAfterAttach() async throws {
        let helper = makeHelper()
        try helper.beginSession()
        helper.attachBookTotals(totalSecondsAtOpen: 24_000, isFirstSession: false)
        // Let ≥1s of real session time accrue (the helper reads wall clock
        // for the active segment; there is no injectable clock seam).
        try await Task.sleep(for: .milliseconds(1_200))
        helper.updateTimeDisplays()
        let readout = try #require(helper.timeReadoutDisplay)
        // 1-59s of session → "<1m read"; total 24000+1s → "6h 40m total".
        #expect(readout == "<1m read \u{B7} 6h 40m total")
        await helper.close(locator: nil)
    }

    @Test func firstSessionVariantAfterAttach() async throws {
        let helper = makeHelper()
        try helper.beginSession()
        helper.attachBookTotals(totalSecondsAtOpen: 0, isFirstSession: true)
        try await Task.sleep(for: .milliseconds(1_200))
        helper.updateTimeDisplays()
        let readout = try #require(helper.timeReadoutDisplay)
        #expect(readout == "<1m read \u{B7} first session")
        await helper.close(locator: nil)
    }

    @Test func beginSessionFetchesTotalsFromStatsStore() async throws {
        let fpKey = makeFingerprint().canonicalKey
        let helper = makeHelper(statsStore: StubStatsProvider(
            record: statsRecord(key: fpKey, totalSeconds: 36_000, sessionCount: 12)))
        try helper.beginSession()
        // The attach rides a Task spawned in beginSession — give it a beat,
        // then let session time accrue so the readout materializes.
        try await Task.sleep(for: .milliseconds(1_200))
        helper.updateTimeDisplays()
        let readout = try #require(helper.timeReadoutDisplay)
        // 36000s total + ~1s live → still "10h" (drops minutes at ≥10h).
        #expect(readout == "<1m read \u{B7} 10h total")
        await helper.close(locator: nil)
    }

    @Test func statsStoreNilRecordMeansFirstSession() async throws {
        // A never-read book has NO stats row: record nil → totals 0,
        // sessionCount 0 → first-session variant.
        let helper = makeHelper(statsStore: StubStatsProvider(record: nil))
        try helper.beginSession()
        try await Task.sleep(for: .milliseconds(1_200))
        helper.updateTimeDisplays()
        let readout = try #require(helper.timeReadoutDisplay)
        #expect(readout == "<1m read \u{B7} first session")
        await helper.close(locator: nil)
    }

    @Test func closeResetsTimeReadout() async throws {
        let helper = makeHelper()
        try helper.beginSession()
        helper.attachBookTotals(totalSecondsAtOpen: 24_000, isFirstSession: false)
        try await Task.sleep(for: .milliseconds(1_200))
        helper.updateTimeDisplays()
        #expect(helper.timeReadoutDisplay != nil)
        await helper.close(locator: nil)
        #expect(helper.timeReadoutDisplay == nil)
        #expect(helper.sessionTimeDisplay == nil)
    }

    @Test func staleFetchFromClosedSessionDoesNotPoisonReopen() async throws {
        // Gate-4 r1 High: begin → close (before the slow fetch lands) →
        // begin again. The first (cancelled/stale-generation) fetch's
        // poison total must be dropped; the second session attaches the
        // real total.
        let helper = makeHelper(statsStore: SlowCountingStatsProvider())
        try helper.beginSession()
        await helper.close(locator: nil)   // first fetch still in flight
        try helper.beginSession()           // refetches (totals were reset)
        try await Task.sleep(for: .milliseconds(1_500))
        helper.updateTimeDisplays()
        let readout = try #require(helper.timeReadoutDisplay)
        // 24_000s = "6h 40m"; the poison 11_111s would read "3h 5m".
        #expect(readout == "<1m read \u{B7} 6h 40m total")
        await helper.close(locator: nil)
    }

    @Test func updateTimeDisplaysPostsSessionTimeNotification() async throws {
        let helper = makeHelper()
        try helper.beginSession()
        try await Task.sleep(for: .milliseconds(1_200))

        // Posted synchronously on the main actor from updateTimeDisplays —
        // the observer block runs on the posting thread before post returns.
        nonisolated(unsafe) var received: [AnyHashable: Any]?
        let token = NotificationCenter.default.addObserver(
            forName: .readerSessionTimeDidChange, object: nil, queue: nil
        ) { note in
            received = note.userInfo
        }
        defer { NotificationCenter.default.removeObserver(token) }

        helper.updateTimeDisplays()
        let info = try #require(received)
        #expect(info["fingerprintKey"] as? String == makeFingerprint().canonicalKey)
        #expect(info["display"] as? String == "<1m read")
        await helper.close(locator: nil)
    }
}
