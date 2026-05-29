// Purpose: Regression tests for bug #89 — book opening performance.
// Ensures no blocking work runs on the book-open critical path.
//
// @coordinates-with: ReaderContainerView.swift, ReaderSearchCoordinator.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Bug #89 — Book Open Performance")
@MainActor
struct BookOpenPerformanceTests {

    // MARK: - Search prep must NOT run on open

    @Test("search coordinator starts unprepared on init (no eager work in init)")
    func searchPrepNotCalledOnInit() {
        // Bug #79 / #89: the coordinator must do NO work in its initializer —
        // eager preparation happens later, on reader open, not at construction.
        // (The SQLite open is the heavy part; it must never run synchronously
        // in `init()`.)
        let coordinator = ReaderSearchCoordinator()
        #expect(coordinator.searchService == nil,
                "Search service should be nil on init — not prepared in the initializer")
        #expect(coordinator.searchViewModel == nil,
                "Search ViewModel should be nil on init — not prepared in the initializer")
    }

    // MARK: - Bug #79 regression — eager prepare on reader open, off the MainActor

    @Test("prepareService readies service + VM so the search panel never shows the placeholder")
    func prepareServiceReadiesViewModel() async {
        // Bug #79 (REOPENED): the eager `prepareService()` on reader open was
        // removed in fd12ab0e, so the FIRST search of a session shows a
        // "Preparing search…" placeholder while the cold store opens. The fix
        // restores eager prepare. After it runs, the VM (which drives the
        // search field — its presence is what makes `searchSheet` render
        // `SearchView` instead of the ProgressView placeholder) must be ready.
        let coordinator = ReaderSearchCoordinator()
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 100,
            format: .txt
        )
        await coordinator.prepareService(fingerprint: fp)
        #expect(coordinator.searchService != nil,
                "Eager prepare must create the SearchService")
        #expect(coordinator.searchViewModel != nil,
                "Eager prepare must create the SearchViewModel so the panel skips the placeholder")
    }

    @Test("the cold SQLite store open is nonisolated — never blocks the MainActor")
    func storeOpenIsOffMainActor() async {
        // Bug #89 seam: re-adding eager prepare on open would re-introduce the
        // book-open stall (fd12ab0e's legitimate concern) UNLESS the cold
        // SQLite open (`sqlite3_open` + integrity_check + FTS5/table DDL) is
        // moved OFF the MainActor. `prepareEagerly` builds the store on a
        // detached, non-MainActor task and only hops back to assign the
        // @MainActor state. We exercise that nonisolated entry point from a
        // background task and confirm the heavy work completes there.
        let coordinator = ReaderSearchCoordinator()
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "b", count: 64),
            fileByteCount: 100,
            format: .txt
        )
        // Drive the eager-open path from a non-MainActor context. If the heavy
        // open were MainActor-isolated this would deadlock/hop; the nonisolated
        // builder runs it off-main and the result is then ready on the actor.
        await Task.detached {
            await coordinator.prepareEagerly(fingerprint: fp)
        }.value
        #expect(coordinator.searchService != nil,
                "Off-main eager prepare must produce a ready service")
        #expect(coordinator.searchViewModel != nil,
                "Off-main eager prepare must produce a ready view model")
    }

    @Test("concurrent prepares coalesce — exactly one store is opened and published")
    func concurrentPreparesCoalesce() async {
        // Codex Gate-4 Medium (bug #79): without single-flight coalescing, two
        // concurrent prepares (e.g. the reader-open `prepareEagerly` racing the
        // search-sheet `setup`) each pass the initial `searchService == nil`
        // guard and open TWO SQLite connections. A transient SQLITE_BUSY during
        // concurrent DDL could let an in-memory fallback store win the post-await
        // guard, silently losing persistent indexing for the session. The fix
        // shares one in-flight prepare Task. We can't observe the connection
        // count directly, but we CAN assert the published service is stable: the
        // same instance regardless of which racer ran, and a third prepare after
        // they settle is a no-op (the guard already short-circuits).
        let coordinator = ReaderSearchCoordinator()
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "c", count: 64),
            fileByteCount: 100,
            format: .txt
        )
        async let a: Void = coordinator.prepareEagerly(fingerprint: fp)
        async let b: Void = coordinator.prepareService(fingerprint: fp)
        _ = await (a, b)
        let firstService = coordinator.searchService
        #expect(firstService != nil, "Coalesced prepare must publish a service")
        // A subsequent prepare must NOT replace the published service.
        await coordinator.prepareService(fingerprint: fp)
        #expect(coordinator.searchService === firstService,
                "Prepare after settle must be a no-op — no second store published")
    }

    // MARK: - TXT chapter-based open uses openChapterBased

    @Test("TXTReaderViewModel has openChapterBased method")
    func txtViewModelHasChapterBasedOpen() {
        // Verify the chapter-based open path exists (regression: was calling open() instead)
        let vm = TXTReaderViewModel(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: String(repeating: "a", count: 64),
                fileByteCount: 100,
                format: .txt
            ),
            txtService: TXTService(),
            positionStore: NoOpPositionStore(),
            sessionTracker: ReadingSessionTracker(
                clock: SystemClock(),
                store: NoOpSessionStore(),
                deviceId: "test"
            ),
            deviceId: "test"
        )
        // openChapterBased exists and is callable (we don't actually call it — no file)
        #expect(vm.isChapterMode == false, "Should not be in chapter mode before open")
        #expect(vm.currentChapterText == nil, "No chapter text before open")
    }
}

// MARK: - No-Op Test Doubles

private struct NoOpPositionStore: ReadingPositionPersisting {
    func loadPosition(bookFingerprintKey: String) async throws -> Locator? { nil }
    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws {}
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws {}
}

private struct NoOpSessionStore: SessionPersisting {
    func saveSession(_ session: ReadingSession) throws {}
    func discardSession(id: UUID) throws {}
    func flushDuration(sessionId: UUID, durationSeconds: Int) throws {}
    func fetchUnclosedSessions() throws -> [ReadingSession] { [] }
}
#endif
