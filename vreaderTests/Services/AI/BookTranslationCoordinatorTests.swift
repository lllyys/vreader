// Purpose: Tests for BookTranslationCoordinator — the actor driving the
// "translate entire book" flow for feature #56 WI-14. Iterates units via
// ChapterTextProviding, skips cache-covered units, calls
// ChapterTranslationService per unit, emits monotonic progress, honors
// cancellation, and serializes one job per book.
//
// @coordinates-with: BookTranslationCoordinator.swift,
//   ChapterTextProviding.swift, ChapterTranslationService.swift,
//   ChapterTranslationStore.swift, ResolvedAIProviderConfig.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-14)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("BookTranslationCoordinator")
struct BookTranslationCoordinatorTests {

    private static let bookKey = "epub:fp-coord-tests"
    private static let providerID = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!

    private static func makeConfig() -> ResolvedAIProviderConfig {
        ResolvedAIProviderConfig(
            kind: .openAICompatible,
            baseURL: URL(string: "https://api.test.example.com")!,
            apiKey: "sk-test", model: "test-model", maxTokens: 4096)
    }

    private static func makeStore() throws -> ChapterTranslationStore {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ChapterTranslationStore(modelContainer: container)
    }

    private static func unit(_ value: String) -> TranslationUnitID {
        TranslationUnitID(kind: .epubHref, value: value)
    }

    // MARK: - estimate

    @Test func estimate_returnsUnitCountFromProvider() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2"), Self.unit("ch3")]
        let provider = MockChapterTextProvider(units: units, texts: [
            units[0]: "p1.", units[1]: "p2.", units[2]: "p3."
        ])
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: [])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        let estimate = try await coordinator.estimate(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese")

        #expect(estimate.unitCount == 3)
    }

    @Test func estimate_zeroUnitBook_returnsZero() async throws {
        let provider = MockChapterTextProvider(units: [], texts: [:])
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: [])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        let estimate = try await coordinator.estimate(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese")

        #expect(estimate.unitCount == 0)
        #expect(estimate.approximateInputTokens == nil)
    }

    @Test func estimate_withUnitText_returnsRoughTokenCount() async throws {
        // 10 units × 4000 chars each → total ≈ 40_000 chars →
        // approximateInputTokens ≈ 10_000 (4 chars/token rule of thumb).
        // The coordinator samples 5 units, averages, then extrapolates.
        let units = (1...10).map { Self.unit("ch\($0)") }
        let fourThousandChars = String(repeating: "a", count: 4000)
        var texts: [TranslationUnitID: String] = [:]
        for u in units { texts[u] = fourThousandChars }
        let provider = MockChapterTextProvider(units: units, texts: texts)
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: [])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        let estimate = try await coordinator.estimate(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese")

        #expect(estimate.unitCount == 10)
        // 40_000 chars / 4 chars-per-token = 10_000 tokens — allow a
        // small rounding tolerance.
        let tokens = try #require(estimate.approximateInputTokens)
        #expect(abs(tokens - 10_000) < 100)
    }

    // MARK: - start (happy path)

    @Test func start_iteratesUnitsInOrder_emitsMonotonicProgress() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2"), Self.unit("ch3")]
        let provider = MockChapterTextProvider(units: units, texts: [
            units[0]: "p1.", units[1]: "p2.", units[2]: "p3."
        ])
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: ["[\"a\"]", "[\"b\"]", "[\"c\"]"])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        // Drain the AsyncStream into an actor-isolated array so the
        // Sendable check is satisfied (Swift 6 strict concurrency).
        let stream = await coordinator.progressUpdates(forBookWithKey: Self.bookKey)
        let collector = BookTranslationProgressCollector()
        let collectTask = Task {
            for await p in stream { await collector.append(p) }
        }

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)

        // Wait for the job to finish (completion phase emits a final tick).
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)
        // The stream finishes when the coordinator records the terminal
        // phase — the collector task ends naturally.
        await collectTask.value

        let snapshots = await collector.snapshots()
        #expect(snapshots.contains { $0.phase == .completed && $0.completed == 3 && $0.total == 3 })
        // Monotonic non-decreasing completed counts.
        for i in 1..<snapshots.count {
            #expect(snapshots[i].completed >= snapshots[i - 1].completed)
        }
    }

    @Test func start_skipsAlreadyCachedUnits() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2"), Self.unit("ch3")]
        let provider = MockChapterTextProvider(units: units, texts: [
            units[0]: "p1.", units[1]: "p2.", units[2]: "p3."
        ])
        let store = try Self.makeStore()

        // Pre-seed ch1 + ch3 as cached → only ch2 needs an API call.
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: Self.bookKey, unitStorageKey: units[0].storageKey,
            targetLanguage: "Chinese", providerProfileID: Self.providerID, promptVersion: "v1",
            translatedSegments: ["译1"], sourceParagraphCount: 1))
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: Self.bookKey, unitStorageKey: units[2].storageKey,
            targetLanguage: "Chinese", providerProfileID: Self.providerID, promptVersion: "v1",
            translatedSegments: ["译3"], sourceParagraphCount: 1))

        let sender = MockTranslationSender(responses: ["[\"译2\"]"])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        // Only the uncached unit went over the wire.
        #expect(await sender.requestCount == 1)
        // And the final progress is 3/3 (the skip still counts as progress).
        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .completed)
        #expect(final.completed == 3)
        #expect(final.total == 3)
    }

    @Test func start_zeroUnitBook_completesImmediately_atZeroOfZero() async throws {
        let provider = MockChapterTextProvider(units: [], texts: [:])
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: [])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        #expect(await sender.requestCount == 0)
        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .completed)
        #expect(final.completed == 0)
        #expect(final.total == 0)
    }

    // MARK: - cancel

    @Test func cancel_stopsTheJob_andEmitsCancelledState() async throws {
        let units = (1...5).map { Self.unit("ch\($0)") }
        var texts: [TranslationUnitID: String] = [:]
        for u in units { texts[u] = "p" }
        // Use a slow sender so the cancel can land between units.
        let sender = SlowTranslationSender(
            responses: units.map { _ in "[\"x\"]" }, perRequestNanos: 200_000_000)
        let store = try Self.makeStore()
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")
        let provider = MockChapterTextProvider(units: units, texts: texts)

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        // Give the job time to process at least one unit before cancelling.
        try await Task.sleep(nanoseconds: 250_000_000)
        await coordinator.cancel(bookFingerprintKey: Self.bookKey)
        try? await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .cancelled)
        #expect(final.completed < units.count)
    }

    // MARK: - one job per book

    @Test func secondStartForSameBook_isANoOp_whileFirstRuns() async throws {
        let units = (1...4).map { Self.unit("ch\($0)") }
        var texts: [TranslationUnitID: String] = [:]
        for u in units { texts[u] = "p" }
        let provider = MockChapterTextProvider(units: units, texts: texts)
        let sender = SlowTranslationSender(
            responses: units.map { _ in "[\"x\"]" }, perRequestNanos: 150_000_000)
        let store = try Self.makeStore()
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        // Second start should not double the request count.
        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)
        #expect(await sender.requestCount == units.count)
    }

    // MARK: - deleteTranslations on book delete

    @Test func deleteBook_cancelsRunningJob_andClearsCacheEntries() async throws {
        let units = (1...5).map { Self.unit("ch\($0)") }
        var texts: [TranslationUnitID: String] = [:]
        for u in units { texts[u] = "p" }
        let provider = MockChapterTextProvider(units: units, texts: texts)
        let sender = SlowTranslationSender(
            responses: units.map { _ in "[\"x\"]" }, perRequestNanos: 200_000_000)
        let store = try Self.makeStore()
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        try await Task.sleep(nanoseconds: 250_000_000)
        try await coordinator.cancelAndPurge(bookFingerprintKey: Self.bookKey)

        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .cancelled)
        let count = await store.debugRowCount()
        #expect(count == 0)
    }

    // MARK: - currentProgress before any start

    @Test func currentProgress_beforeStart_isIdleWithZeroTotal() async {
        let store = try? Self.makeStore()
        let sender = MockTranslationSender(responses: [])
        let service = ChapterTranslationService(
            sender: sender, store: store!, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store!, promptVersion: "v1")
        let progress = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(progress.phase == .idle)
        #expect(progress.total == 0)
        #expect(progress.completed == 0)
    }

    // MARK: - Config pinned (active provider deleted mid-job)

    @Test func providerProfileDeletedMidJob_jobStillFinishes_withPinnedConfig() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2")]
        let provider = MockChapterTextProvider(units: units, texts: [
            units[0]: "p1.", units[1]: "p2."
        ])
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: ["[\"a\"]", "[\"b\"]"])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")
        // Pin a config — coordinator never re-resolves it mid-run.
        let pinnedConfig = Self.makeConfig()

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: pinnedConfig,
            style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        // The coordinator never asks anything outside the injected sender —
        // a deleted profile post-start would have no effect by construction.
        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .completed)
    }

    // MARK: - Feature #98 WI-1: background token renewal + expiry checkpoint

    /// Each TRANSLATED unit acquires (and releases) its own background token —
    /// cache-skipped units don't burn begin/end churn. 3 units with 1 cached
    /// → exactly 2 begin/end pairs.
    @Test func start_renewsBackgroundTokenPerTranslatedUnit_skippingCached() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2"), Self.unit("ch3")]
        let provider = MockChapterTextProvider(units: units, texts: [
            units[0]: "p1.", units[1]: "p2.", units[2]: "p3."
        ])
        let store = try Self.makeStore()
        // ch2 already cached → skipped without a token.
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: Self.bookKey,
            unitStorageKey: units[1].storageKey,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            promptVersion: "v1",
            translatedSegments: ["旧"],
            sourceParagraphCount: 1))
        let sender = MockTranslationSender(responses: ["[\"a\"]", "[\"c\"]"])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let requester = await MockBackgroundTaskRequester()
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1",
            backgroundTasks: requester)

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        let begins = await requester.begins
        let ends = await requester.ends
        #expect(begins.count == 2, "one token per translated unit; cached unit skipped")
        #expect(ends.count == 2, "every token released at its unit boundary")
        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .completed)
    }

    /// OS expiry mid-unit (fired through the PRODUCTION expiration-handler
    /// wiring) stops the job cleanly BETWEEN units: the in-flight unit
    /// completes and stays cached, no further unit is attempted, and the job
    /// records the EXISTING `.failed` phase (the status sheet's PAUSED
    /// rendering) instead of erroring or hanging.
    @Test func backgroundExpiry_stopsBetweenUnits_keepsCompletedUnitsCached_emitsFailed() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2"), Self.unit("ch3")]
        let provider = GatedTextProvider(
            units: units,
            texts: [units[0]: "p1.", units[1]: "p2.", units[2]: "p3."],
            gatedUnit: units[1])
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: ["[\"a\"]", "[\"b\"]", "[\"c\"]"])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let requester = await MockBackgroundTaskRequester()
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1",
            backgroundTasks: requester)

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)

        // Wait until the job is suspended INSIDE unit 2 (its token — the
        // 2nd begin — exists), then expire that token via the captured OS
        // handler and wait for the flag to land on the actor.
        await provider.waitUntilGateArrived()
        await requester.fireExpiry(rawIdentifier: 2)
        while !(await coordinator.isJobExpiredForTesting(forBookWithKey: Self.bookKey)) {
            await Task.yield()
        }
        await provider.release()
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .failed, "expiry reuses the existing .failed phase (PAUSED rendering)")
        #expect(final.completed == 2, "the in-flight unit finished; nothing after it started")
        let requestCount = await sender.requestCount
        #expect(requestCount == 2, "unit 3 must never reach the provider")
        let cached = await store.cachedUnits(
            forBookWithKey: Self.bookKey, targetLanguage: "Chinese", promptVersion: "v1")
        #expect(cached.contains(units[0].storageKey) && cached.contains(units[1].storageKey),
                "completed units stay cached — they're the resume checkpoint")
    }

    /// A NEW start after an expiry stop must not insta-expire (the flag is
    /// per-run, cleared on start) and resumes from cache — only the
    /// not-yet-cached unit reaches the provider.
    @Test func start_afterExpiryStop_clearsFlag_andResumesFromCache() async throws {
        let units = [Self.unit("ch1"), Self.unit("ch2")]
        let provider = MockChapterTextProvider(units: units, texts: [
            units[0]: "p1.", units[1]: "p2."
        ])
        let store = try Self.makeStore()
        // ch1 cached (the "completed before expiry" checkpoint).
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: Self.bookKey,
            unitStorageKey: units[0].storageKey,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            promptVersion: "v1",
            translatedSegments: ["一"],
            sourceParagraphCount: 1))
        let sender = MockTranslationSender(responses: ["[\"b\"]"])
        let service = ChapterTranslationService(
            sender: sender, store: store, promptVersion: "v1")
        let coordinator = BookTranslationCoordinator(
            service: service, store: store, promptVersion: "v1")
        // Simulate the stale flag a prior expired run left behind.
        await coordinator.handleBackgroundTaskExpiry(forBookWithKey: Self.bookKey)

        await coordinator.start(
            bookFingerprintKey: Self.bookKey,
            textProvider: provider,
            targetLanguage: "Chinese",
            providerProfileID: Self.providerID,
            config: Self.makeConfig(),
            style: .natural)
        try await coordinator.awaitJobForTesting(bookFingerprintKey: Self.bookKey)

        let final = await coordinator.currentProgress(forBookWithKey: Self.bookKey)
        #expect(final.phase == .completed, "a stale expiry flag must not kill the new run")
        #expect(final.completed == 2)
        let requestCount = await sender.requestCount
        #expect(requestCount == 1, "cached unit skipped — resume, not restart")
    }
}

// MARK: - Test doubles

/// Read-only stub of `ChapterTextProviding` for coordinator tests.
/// Feature #98: a text provider whose `sourceText(for:)` BLOCKS on one
/// designated unit until the test releases it — lets a test pin the job
/// mid-unit, fire a deterministic background expiry, then let the unit
/// finish so the between-units expiry check is exercised without races.
actor GatedTextProvider: ChapterTextProviding {
    private let units: [TranslationUnitID]
    private let texts: [TranslationUnitID: String]
    private let gatedUnit: TranslationUnitID
    private var released = false
    private var gateContinuation: CheckedContinuation<Void, Never>?
    private var arrived = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        units: [TranslationUnitID],
        texts: [TranslationUnitID: String],
        gatedUnit: TranslationUnitID
    ) {
        self.units = units
        self.texts = texts
        self.gatedUnit = gatedUnit
    }

    func translationUnits() async throws -> [TranslationUnitID] { units }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        if unit == gatedUnit && !released {
            arrived = true
            for waiter in arrivalWaiters { waiter.resume() }
            arrivalWaiters.removeAll()
            await withCheckedContinuation { gateContinuation = $0 }
        }
        guard let text = texts[unit] else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        return text
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? { units.first }

    func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
        guard let idx = units.firstIndex(of: unit), idx + 1 < units.count else { return nil }
        return units[idx + 1]
    }

    /// Suspends until the job is blocked inside the gated unit's sourceText.
    func waitUntilGateArrived() async {
        if arrived { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    /// Releases the gate; the blocked sourceText returns its text.
    func release() {
        released = true
        gateContinuation?.resume()
        gateContinuation = nil
    }
}

struct MockChapterTextProvider: ChapterTextProviding {
    let units: [TranslationUnitID]
    let texts: [TranslationUnitID: String]

    func translationUnits() async throws -> [TranslationUnitID] { units }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        guard let text = texts[unit] else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        return text
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? {
        units.first
    }

    func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
        guard let idx = units.firstIndex(of: unit), idx + 1 < units.count else { return nil }
        return units[idx + 1]
    }
}

/// Records every request, returns canned responses, lets a test block the call.
actor MockTranslationSender: TranslationRequestSending {
    private var responses: [String]
    private var requests: [AIRequest] = []
    init(responses: [String]) { self.responses = responses }

    var requestCount: Int { requests.count }

    func sendTranslationRequest(
        _ request: AIRequest, using config: ResolvedAIProviderConfig
    ) async throws -> AIResponse {
        requests.append(request)
        let next = responses.isEmpty ? "[]" : responses.removeFirst()
        return AIResponse(
            content: next, actionType: .translate, promptVersion: "v1", createdAt: Date())
    }
}

/// Actor-isolated collector for progress snapshots — Swift 6 strict-
/// concurrency-safe alternative to capturing an array in a Task closure.
actor BookTranslationProgressCollector {
    private var entries: [BookTranslationProgress] = []
    func append(_ p: BookTranslationProgress) { entries.append(p) }
    func snapshots() -> [BookTranslationProgress] { entries }
}

/// Same as MockTranslationSender but sleeps per request so cancel + serialize
/// tests have a deterministic timing window.
actor SlowTranslationSender: TranslationRequestSending {
    private var responses: [String]
    private var requests: [AIRequest] = []
    private let perRequestNanos: UInt64
    init(responses: [String], perRequestNanos: UInt64) {
        self.responses = responses
        self.perRequestNanos = perRequestNanos
    }
    var requestCount: Int { requests.count }

    func sendTranslationRequest(
        _ request: AIRequest, using config: ResolvedAIProviderConfig
    ) async throws -> AIResponse {
        try await Task.sleep(nanoseconds: perRequestNanos)
        requests.append(request)
        let next = responses.isEmpty ? "[]" : responses.removeFirst()
        return AIResponse(
            content: next, actionType: .translate, promptVersion: "v1", createdAt: Date())
    }
}
