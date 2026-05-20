// Purpose: Tests for SettingsHeaderViewModel — the @MainActor
// @Observable view model that fetches the Settings profile card's two
// numbers (book count, this-month reading seconds). Feature #67 WI-3.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("SettingsHeaderViewModel — feature #67 WI-3")
@MainActor
struct SettingsHeaderViewModelTests {

    // MARK: - LibraryStatsReading mock

    /// A configurable `LibraryStatsReading` double. `book count` is a
    /// fixed value; `sumReadingSeconds` returns the sum of seeded
    /// per-interval contributions whose key date falls in the queried
    /// interval, so the view model's month-window logic is exercised.
    private actor MockStats: LibraryStatsReading {
        enum Mode: Sendable {
            /// Normal operation — return seeded values.
            case ok
            /// Both reads throw.
            case failing
        }

        let bookCount: Int
        /// `(keyDate, seconds)` reading contributions — `sumReadingSeconds`
        /// includes a contribution iff its `keyDate` is inside the interval.
        let contributions: [(Date, Int)]
        let mode: Mode
        /// How many times each read was invoked — for idempotency tests.
        private(set) var countCalls = 0
        private(set) var sumCalls = 0

        init(bookCount: Int, contributions: [(Date, Int)] = [], mode: Mode = .ok) {
            self.bookCount = bookCount
            self.contributions = contributions
            self.mode = mode
        }

        struct StatsError: Error {}

        func countLibraryBooks() async throws -> Int {
            countCalls += 1
            if mode == .failing { throw StatsError() }
            return bookCount
        }

        func sumReadingSeconds(in interval: DateInterval) async throws -> Int {
            sumCalls += 1
            if mode == .failing { throw StatsError() }
            return contributions
                .filter { interval.start <= $0.0 && $0.0 < interval.end }
                .reduce(0) { $0 + $1.1 }
        }
    }

    // MARK: - Initial state

    @Test func freshViewModelHasZeroCounts() {
        let viewModel = SettingsHeaderViewModel()
        #expect(viewModel.bookCount == 0)
        #expect(viewModel.monthReadingSeconds == 0)
    }

    // MARK: - load — book count

    @Test func loadPopulatesBookCountFromBoundary() async {
        let viewModel = SettingsHeaderViewModel()
        await viewModel.load(persistence: MockStats(bookCount: 5))
        #expect(viewModel.bookCount == 5)
    }

    // MARK: - load — this-month reading seconds

    @Test func loadCountsOnlyThisMonthReadingSeconds() async {
        // One session this month, one last month — only this month counts.
        let now = Date()
        let calendar = Calendar.current
        let thisMonth = now
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let mock = MockStats(
            bookCount: 3,
            contributions: [(thisMonth, 1_800), (lastMonth, 9_999)]
        )
        let viewModel = SettingsHeaderViewModel()
        await viewModel.load(persistence: mock)
        #expect(viewModel.monthReadingSeconds == 1_800)
    }

    @Test func loadSumsMultipleThisMonthSessions() async {
        let now = Date()
        let mock = MockStats(
            bookCount: 2,
            contributions: [(now, 600), (now, 1_200), (now, 300)]
        )
        let viewModel = SettingsHeaderViewModel()
        await viewModel.load(persistence: mock)
        #expect(viewModel.monthReadingSeconds == 2_100)
    }

    // MARK: - Empty / nil-boundary path

    @Test func loadWithNilBoundaryLeavesZeros() async {
        let viewModel = SettingsHeaderViewModel()
        await viewModel.load(persistence: nil)
        #expect(viewModel.bookCount == 0)
        #expect(viewModel.monthReadingSeconds == 0)
    }

    @Test func loadWithEmptyLibraryLeavesZeros() async {
        let viewModel = SettingsHeaderViewModel()
        await viewModel.load(persistence: MockStats(bookCount: 0, contributions: []))
        #expect(viewModel.bookCount == 0)
        #expect(viewModel.monthReadingSeconds == 0)
    }

    // MARK: - Error path

    @Test func loadWithThrowingBoundaryLeavesZerosWithoutCrashing() async {
        let viewModel = SettingsHeaderViewModel()
        // A throwing boundary must not crash and must not corrupt state.
        await viewModel.load(persistence: MockStats(bookCount: 7, mode: .failing))
        #expect(viewModel.bookCount == 0)
        #expect(viewModel.monthReadingSeconds == 0)
    }

    // MARK: - Idempotency

    @Test func loadCalledTwiceIsStable() async {
        let mock = MockStats(bookCount: 4, contributions: [(Date(), 1_000)])
        let viewModel = SettingsHeaderViewModel()
        await viewModel.load(persistence: mock)
        await viewModel.load(persistence: mock)
        // Last-write-wins — a second .task-driven load produces the same
        // state, never doubled.
        #expect(viewModel.bookCount == 4)
        #expect(viewModel.monthReadingSeconds == 1_000)
    }

    /// A `LibraryStatsReading` double whose `countLibraryBooks` blocks
    /// on an explicit gate, so a test can hold one `load` mid-flight
    /// while a second `load` overtakes it. It also signals when a call
    /// has *entered* `countLibraryBooks`, so the test can sequence
    /// deterministically rather than relying on a bare `Task.yield()`.
    private actor GatedStats: LibraryStatsReading {
        let bookCount: Int
        /// Continuations parked by `countLibraryBooks` calls, awaiting `release()`.
        private var parked: [CheckedContinuation<Void, Never>] = []
        private var releaseRequested = false
        /// Set once `countLibraryBooks` has been entered; resumes any
        /// `waitUntilEntered()` awaiter.
        private var entered = false
        private var entryWaiters: [CheckedContinuation<Void, Never>] = []

        init(bookCount: Int) { self.bookCount = bookCount }

        /// Suspends until a `countLibraryBooks` call has been entered.
        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { entryWaiters.append($0) }
        }

        /// Unblocks every parked (and every future) `countLibraryBooks` call.
        func release() {
            releaseRequested = true
            for continuation in parked { continuation.resume() }
            parked.removeAll()
        }

        func countLibraryBooks() async throws -> Int {
            entered = true
            for waiter in entryWaiters { waiter.resume() }
            entryWaiters.removeAll()
            if !releaseRequested {
                await withCheckedContinuation { parked.append($0) }
            }
            return bookCount
        }

        func sumReadingSeconds(in interval: DateInterval) async throws -> Int {
            0
        }
    }

    @Test func slowEarlierLoadDoesNotOverwriteANewerLoad() async {
        // The whole point of `latestRequestID`: a stale earlier request
        // resolving after a newer one must NOT clobber the newer values.
        let viewModel = SettingsHeaderViewModel()
        let slow = GatedStats(bookCount: 111)   // request 1 — blocked
        let fast = MockStats(bookCount: 222)    // request 2 — completes first

        // Start the slow load. It claims latestRequestID = 1, then parks
        // inside countLibraryBooks.
        let slowLoad = Task { await viewModel.load(persistence: slow) }
        // Deterministically wait until request 1 has entered the boundary
        // — so it has definitely claimed its request id before request 2.
        await slow.waitUntilEntered()

        // The fast load overtakes: it claims latestRequestID = 2 and
        // applies request 2's values.
        await viewModel.load(persistence: fast)
        #expect(viewModel.bookCount == 222)

        // Release the slow load — request 1 finishes last but is stale.
        await slow.release()
        await slowLoad.value

        // Request 1's value (111) must NOT have overwritten request 2's (222).
        #expect(viewModel.bookCount == 222)
    }

    // MARK: - Real PersistenceActor

    @Test func loadAgainstRealPersistenceActorReadsSeededData() async throws {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Seed two books.
        for i in 0..<2 {
            var hex = ""
            let bytes = Array("realbook\(i)".utf8)
            var j = 0
            while hex.count < 64 {
                hex += String(format: "%02x", bytes[j % bytes.count] &+ UInt8(j))
                j += 1
            }
            let fp = DocumentFingerprint(
                contentSHA256: String(hex.prefix(64)), fileByteCount: 1024, format: .epub
            )
            context.insert(Book(
                fingerprint: fp,
                title: "Real Book \(i)",
                provenance: ImportProvenance(
                    source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil
                )
            ))
            // A reading session this month for each book.
            context.insert(ReadingSession(
                bookFingerprint: fp, startedAt: Date(), durationSeconds: 1_500
            ))
        }
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let viewModel = SettingsHeaderViewModel()
        await viewModel.load(persistence: actor)
        #expect(viewModel.bookCount == 2)
        #expect(viewModel.monthReadingSeconds == 3_000)
    }
}
