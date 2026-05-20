// Purpose: Feature #56 WI-13 — pin the unit-scoped retry method
// `BilingualReadingViewModel.retryUnit(_:)`. The PDF offline panel
// (and any future per-format retry CTA) calls this to re-fetch ONE
// offline unit without nuking the rest of the book's cache.
//
// Why a dedicated test file instead of extending Behavior tests:
// keeps the WI-13 surface auditable as a single unit-of-change. The
// Behavior tests pin `resetTriggerState` (whole-book wipe) — this
// file pins the opposite, scoped semantics.
//
// @coordinates-with: BilingualReadingViewModel.swift,
//   BilingualReadingViewModel+Prefetch.swift,
//   ChapterTextProviding.swift, ChapterPrefetching.swift

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #56 WI-13 — BilingualReadingViewModel.retryUnit")
struct BilingualReadingViewModelRetryUnitTests {

    // MARK: - Test doubles (small, file-private — same shape as Behavior tests)

    private struct StubProvider: ChapterTextProviding {
        let units: [TranslationUnitID]
        func translationUnits() async throws -> [TranslationUnitID] { units }
        func sourceText(for unit: TranslationUnitID) async throws -> String {
            guard units.contains(unit) else {
                throw ChapterTextProviderError.unknownUnit(unit)
            }
            return "source for \(unit.value)"
        }
        func unit(containing locator: Locator) async -> TranslationUnitID? {
            guard !units.isEmpty, let offset = locator.charOffsetUTF16, offset >= 0
            else { return nil }
            return units[min(offset / 100, units.count - 1)]
        }
        func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
            guard let index = units.firstIndex(of: unit), index + 1 < units.count
            else { return nil }
            return units[index + 1]
        }
    }

    /// Returns a canned response; counts calls per unit.
    private actor SpyPrefetcher: ChapterPrefetching {
        enum Outcome: Sendable { case segments([String]); case offline }
        private let outcome: Outcome
        private(set) var calls: [TranslationUnitID] = []
        init(outcome: Outcome = .segments(["译文"])) {
            self.outcome = outcome
        }
        func translatedSegments(
            for unit: TranslationUnitID,
            targetLanguage: String,
            granularity: TranslationGranularity
        ) async throws -> [String] {
            calls.append(unit)
            switch outcome {
            case .segments(let s): return s
            case .offline: throw ChapterTranslationError.offline
            }
        }
        func callsFor(_ unit: TranslationUnitID) -> Int { calls.filter { $0 == unit }.count }
    }

    /// Sleeps until `release()` is called OR the task is cancelled.
    /// Counts calls; lets the test simulate an in-flight prefetch task
    /// at the moment Retry is tapped (the Gate-4 v5 round-1 L1
    /// branch — `retryUnit` must cancel the in-flight task before
    /// launching the fresh one). Uses a poll loop instead of a
    /// continuation to avoid the leak class that `CheckedContinuation`
    /// + cooperative cancellation hits when the cancel-and-resume
    /// races the await.
    private actor BlockingSpyPrefetcher: ChapterPrefetching {
        private(set) var calls: [TranslationUnitID] = []
        private(set) var observedCancellations: Int = 0
        private var released = false

        func translatedSegments(
            for unit: TranslationUnitID,
            targetLanguage: String,
            granularity: TranslationGranularity
        ) async throws -> [String] {
            calls.append(unit)
            // Cooperative-cancellation poll loop: yield repeatedly,
            // re-check Task.isCancelled and `released`. If cancelled,
            // record and throw; if released, return the canned result.
            while true {
                try Task.checkCancellation()
                if released { return ["译文"] }
                // Yield via a short sleep so other Tasks can run.
                do {
                    try await Task.sleep(nanoseconds: 5_000_000) // 5ms
                } catch {
                    observedCancellations += 1
                    throw error
                }
            }
        }

        func release() {
            released = true
        }

        func callsFor(_ unit: TranslationUnitID) -> Int { calls.filter { $0 == unit }.count }
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BilingualRetryUnit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let bookKey =
        "pdf:dd00112233445566778899aabbccddeeff00112233445566778899aabbccdd:4096"

    private static let twoUnits: [TranslationUnitID] = [
        TranslationUnitID(kind: .pdfPageRange, value: "0-0"),
        TranslationUnitID(kind: .pdfPageRange, value: "1-1"),
    ]

    private func makeEnabledVM(
        dir: URL, provider: StubProvider, prefetcher: SpyPrefetcher
    ) -> BilingualReadingViewModel {
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(provider)
        vm.attachPrefetcher(prefetcher)
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        return vm
    }

    // MARK: - Tests

    @Test func retryUnit_removesOnlyNamedUnitFromUnavailable() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.twoUnits), prefetcher: prefetcher)

        // Pretend two units went offline; retry only the first.
        vm.unavailableUnits = Set(Self.twoUnits)
        vm.retryUnit(Self.twoUnits[0])
        await vm.awaitPrefetchForTesting()

        // Unit 0 is no longer unavailable; unit 1 still is.
        #expect(!vm.unavailableUnits.contains(Self.twoUnits[0]))
        #expect(vm.unavailableUnits.contains(Self.twoUnits[1]))
    }

    @Test func retryUnit_leavesOtherUnitsCacheIntact() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.twoUnits), prefetcher: prefetcher)

        // Unit 1 already has a cached translation; unit 0 is offline.
        vm.translationsByUnit[Self.twoUnits[1]] = ["保留"]
        vm.unavailableUnits.insert(Self.twoUnits[0])

        vm.retryUnit(Self.twoUnits[0])
        await vm.awaitPrefetchForTesting()

        // Unit 1's cache is untouched (whereas resetTriggerState would
        // have wiped it — Gate-2 v5 round-1 H2).
        #expect(vm.translationsByUnit[Self.twoUnits[1]] == ["保留"])
    }

    @Test func retryUnit_reTriggersPrefetchForNamedUnit() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.twoUnits), prefetcher: prefetcher)
        vm.unavailableUnits.insert(Self.twoUnits[0])

        vm.retryUnit(Self.twoUnits[0])
        await vm.awaitPrefetchForTesting()

        // The fresh prefetch ran and produced segments — unit 0 now
        // carries a translation, unavailable cleared.
        #expect(vm.translationsByUnit[Self.twoUnits[0]] == ["译文"])
        #expect(await prefetcher.callsFor(Self.twoUnits[0]) == 1)
    }

    @Test func retryUnit_clearsLastTriggerUnitOnlyIfItMatches() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.twoUnits), prefetcher: prefetcher)
        // Suppose the trigger last acted on unit 1; retrying unit 0
        // must not clear the unrelated lastTriggerUnit.
        vm.lastTriggerUnit = Self.twoUnits[1]
        vm.unavailableUnits.insert(Self.twoUnits[0])
        vm.retryUnit(Self.twoUnits[0])
        #expect(vm.lastTriggerUnit == Self.twoUnits[1])

        // But retrying the unit that matches lastTriggerUnit clears it.
        vm.lastTriggerUnit = Self.twoUnits[1]
        vm.unavailableUnits.insert(Self.twoUnits[1])
        vm.retryUnit(Self.twoUnits[1])
        #expect(vm.lastTriggerUnit == nil)
    }

    @Test func retryUnit_isNoOpWhenDisabled() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(StubProvider(units: Self.twoUnits))
        vm.attachPrefetcher(prefetcher)
        // Disabled — no setEnabled(true).
        vm.unavailableUnits.insert(Self.twoUnits[0])

        vm.retryUnit(Self.twoUnits[0])
        await vm.awaitPrefetchForTesting()

        // unavailableUnits set wasn't mutated; prefetcher wasn't called.
        #expect(vm.unavailableUnits.contains(Self.twoUnits[0]))
        #expect(await prefetcher.callsFor(Self.twoUnits[0]) == 0)
    }

    @Test func retryUnit_cancelsInFlightTaskForSameUnit() async throws {
        // Gate-4 v5 round-1 L1 — the rare race where the user taps
        // Retry while a prefetch is still in flight. `retryUnit`
        // must cancel the prior task before launching the fresh one,
        // or both tasks would race to write into `translationsByUnit`.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocking = BlockingSpyPrefetcher()
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(StubProvider(units: Self.twoUnits))
        vm.attachPrefetcher(blocking)
        vm.setEnabled(true)
        vm.dismissSetupSheet()

        // Stage 1: simulate a prefetch already in flight for unit 0.
        // We start one through the public trigger path so VM state
        // (prefetchTasks / inFlightUnits) is real, not faked.
        await vm.handlePositionChange(
            Locator(
                bookFingerprint: DocumentFingerprint(
                    contentSHA256: String(repeating: "d", count: 64),
                    fileByteCount: 4096, format: .pdf),
                href: nil, progression: nil, totalProgression: nil,
                cfi: nil, page: nil, charOffsetUTF16: 0,
                charRangeStartUTF16: nil, charRangeEndUTF16: nil,
                textQuote: nil, textContextBefore: nil, textContextAfter: nil))
        // Yield long enough for `startPrefetch` to spin its Task.
        // (The blocking prefetcher will not return until release(),
        // so it sits in inFlightUnits.)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.inFlightUnits.contains(Self.twoUnits[0]))

        // Stage 2: tap Retry — the in-flight task must be cancelled.
        vm.retryUnit(Self.twoUnits[0])
        // Release any unwinding tasks.
        await blocking.release()
        await vm.awaitPrefetchForTesting()

        // The prior task observed cancellation; a fresh prefetch ran.
        let cancellations = await blocking.observedCancellations
        let calls = await blocking.callsFor(Self.twoUnits[0])
        #expect(cancellations >= 1)
        #expect(calls >= 2)  // initial + retry
    }

    @Test func retryUnit_isNoOpWhenNoPrefetcherAttached() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(StubProvider(units: Self.twoUnits))
        // No attachPrefetcher.
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        vm.unavailableUnits.insert(Self.twoUnits[0])

        vm.retryUnit(Self.twoUnits[0])
        // No crash, no mutation.
        #expect(vm.unavailableUnits.contains(Self.twoUnits[0]))
    }
}
