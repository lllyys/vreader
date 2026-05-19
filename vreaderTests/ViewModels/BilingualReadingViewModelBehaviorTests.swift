// Purpose: Feature #56 WI-7b — tests for BilingualReadingViewModel's
// behavioral layer: the unit-aware prefetch trigger, epoch/cancellation,
// `.readerBilingualDidChange` posting, and the offline silent-source-fallback.
//
// Uses a mock `ChapterTextProviding` (the unit/Locator resolver) and a mock
// `ChapterPrefetching` (the translation seam) so the behavior is fully
// unit-testable before any format WI wires a real provider.
//
// @coordinates-with: BilingualReadingViewModel.swift, ChapterTextProviding.swift,
//   ChapterPrefetching.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-7b)

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("BilingualReadingViewModel — behavioral layer (WI-7b)")
struct BilingualReadingViewModelBehaviorTests {

    // MARK: - Test doubles

    /// A `ChapterTextProviding` over a fixed ordered unit list. `unit(containing:)`
    /// maps a `charOffsetUTF16` locator to a unit by index (offset / 100).
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
            let index = min(offset / 100, units.count - 1)
            return units[index]
        }

        func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
            guard let index = units.firstIndex(of: unit), index + 1 < units.count
            else { return nil }
            return units[index + 1]
        }
    }

    /// A `ChapterTextProviding` whose FIRST `unit(after:)` call blocks until
    /// `release()` is called; later calls return immediately. Lets a test
    /// interleave a disable / a second `handlePositionChange` inside the
    /// suspension the first `handlePositionChange` takes before it mutates
    /// trigger state.
    private actor SuspendingNextProvider: ChapterTextProviding {
        nonisolated let units: [TranslationUnitID]
        private var waiter: CheckedContinuation<Void, Never>?
        private var released = false
        private var firstCallSeen = false
        private(set) var unitAfterCallCount = 0

        init(units: [TranslationUnitID]) { self.units = units }

        nonisolated func translationUnits() async throws -> [TranslationUnitID] { units }

        nonisolated func sourceText(for unit: TranslationUnitID) async throws -> String {
            "source for \(unit.value)"
        }

        nonisolated func unit(containing locator: Locator) async -> TranslationUnitID? {
            guard !units.isEmpty, let offset = locator.charOffsetUTF16, offset >= 0
            else { return nil }
            return units[min(offset / 100, units.count - 1)]
        }

        func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
            unitAfterCallCount += 1
            // Only the FIRST call blocks (until released) — later calls (the
            // interleaving second `handlePositionChange`) proceed immediately.
            if !firstCallSeen {
                firstCallSeen = true
                if !released {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        waiter = cont
                    }
                }
            }
            guard let index = units.firstIndex(of: unit), index + 1 < units.count
            else { return nil }
            return units[index + 1]
        }

        /// Releases the pending first `unit(after:)` call.
        func release() {
            released = true
            waiter?.resume()
            waiter = nil
        }
    }

    /// Records every prefetch call; returns canned segments or throws.
    private actor SpyPrefetcher: ChapterPrefetching {
        enum Outcome: Sendable { case segments([String]); case offline; case providerFailed }
        private let outcome: Outcome
        /// Optional delay so a test can interleave a second position change
        /// before the first prefetch resolves.
        private let delayNanos: UInt64
        /// When > 0, the first N calls throw `providerFailed`; later calls
        /// honor `outcome`. Lets a test drive a transient-failure-then-retry.
        private var failFirstNCalls: Int
        private(set) var calls: [TranslationUnitID] = []

        init(outcome: Outcome = .segments(["译文"]),
             delayNanos: UInt64 = 0,
             failFirstNCalls: Int = 0) {
            self.outcome = outcome
            self.delayNanos = delayNanos
            self.failFirstNCalls = failFirstNCalls
        }

        func translatedSegments(
            for unit: TranslationUnitID,
            targetLanguage: String,
            granularity: TranslationGranularity
        ) async throws -> [String] {
            calls.append(unit)
            if delayNanos > 0 { try await Task.sleep(nanoseconds: delayNanos) }
            if failFirstNCalls > 0 {
                failFirstNCalls -= 1
                throw ChapterTranslationError.providerFailed("transient")
            }
            switch outcome {
            case .segments(let s): return s
            case .offline: throw ChapterTranslationError.offline
            case .providerFailed: throw ChapterTranslationError.providerFailed("boom")
            }
        }

        func callCount() -> Int { calls.count }
        func callsFor(_ unit: TranslationUnitID) -> Int { calls.filter { $0 == unit }.count }
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BilingualVMBehavior-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let bookKey =
        "epub:bb00112233445566778899aabbccddeeff00112233445566778899aabbccdd:2048"

    private static func fingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "b", count: 64),
            fileByteCount: 2048, format: .epub)
    }

    private static func locator(charOffset: Int) -> Locator {
        Locator(
            bookFingerprint: fingerprint(), href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: charOffset, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
    }

    private static let threeUnits: [TranslationUnitID] = [
        TranslationUnitID(kind: .epubHref, value: "ch0"),
        TranslationUnitID(kind: .epubHref, value: "ch1"),
        TranslationUnitID(kind: .epubHref, value: "ch2"),
    ]

    /// An enabled VM wired with the given doubles.
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

    // MARK: - Prefetch trigger + unit dedupe

    @Test func repeatedPositionChangeWithinOneUnit_triggersExactlyOnePrefetch() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        // Three position changes all inside unit ch0 (offsets 0/40/80 -> index 0).
        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.handlePositionChange(Self.locator(charOffset: 40))
        await vm.handlePositionChange(Self.locator(charOffset: 80))
        await vm.awaitPrefetchForTesting()

        // ch0 prefetched exactly once despite three position changes.
        #expect(await prefetcher.callsFor(Self.threeUnits[0]) == 1)
    }

    @Test func unitChange_prefetchesCurrentAndNext() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        // A position inside unit ch1 (offset 150 -> index 1).
        await vm.handlePositionChange(Self.locator(charOffset: 150))
        await vm.awaitPrefetchForTesting()

        // Current (ch1) + next (ch2) are both prefetched.
        #expect(await prefetcher.callsFor(Self.threeUnits[1]) == 1)
        #expect(await prefetcher.callsFor(Self.threeUnits[2]) == 1)
    }

    @Test func lastUnit_prefetchesOnlyCurrent_noNext() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        // A position inside the last unit ch2 (offset 250 -> index 2).
        await vm.handlePositionChange(Self.locator(charOffset: 250))
        await vm.awaitPrefetchForTesting()

        #expect(await prefetcher.callsFor(Self.threeUnits[2]) == 1)
        #expect(await prefetcher.callCount() == 1)  // no next unit
    }

    @Test func successfulPrefetch_storesTranslationsByUnit() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher(outcome: .segments(["第一句", "第二句"]))
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()

        #expect(vm.translations(for: Self.threeUnits[0]) == ["第一句", "第二句"])
    }

    @Test func alreadyTranslatedUnit_isNotReFetched() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)
        // Pre-seed ch0's translation.
        vm.setTranslations(["cached"], for: Self.threeUnits[0])

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()

        // ch0 already cached -> not re-fetched; ch1 (next) still fetched once.
        #expect(await prefetcher.callsFor(Self.threeUnits[0]) == 0)
        #expect(await prefetcher.callsFor(Self.threeUnits[1]) == 1)
    }

    // MARK: - Disabled / not-attached guards

    @Test func positionChangeWhileDisabled_doesNotPrefetch() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(StubProvider(units: Self.threeUnits))
        vm.attachPrefetcher(prefetcher)
        // NOT enabled.
        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()
        #expect(await prefetcher.callCount() == 0)
    }

    @Test func positionChangeBeforeProviderAttached_doesNotCrashOrPrefetch() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachPrefetcher(prefetcher)
        vm.setEnabled(true)
        // No provider attached.
        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()
        #expect(await prefetcher.callCount() == 0)
    }

    // MARK: - Offline silent-source-fallback

    @Test func offlineCacheMiss_recordsUnavailable_noSyntheticTranslation() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher(outcome: .offline)
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()

        // The unit is recorded unavailable; no synthetic translation is stored.
        #expect(vm.isUnavailable(Self.threeUnits[0]))
        #expect(vm.translations(for: Self.threeUnits[0]) == nil)
    }

    @Test func providerFailure_leavesUnitUnfetched_notUnavailable() async throws {
        // A transient provider error (not offline) must NOT mark the unit
        // unavailable — a later position change should be free to retry.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher(outcome: .providerFailed)
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()

        #expect(vm.isUnavailable(Self.threeUnits[0]) == false)
        #expect(vm.translations(for: Self.threeUnits[0]) == nil)
    }

    // MARK: - Disable / book-change resets

    @Test func disable_clearsTranslationsAndResetsTriggerState() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()
        #expect(vm.translations(for: Self.threeUnits[0]) != nil)

        vm.setEnabled(false)
        #expect(vm.translationsByUnit.isEmpty)

        // After disable, the same position is a fresh trigger when re-enabled
        // (lastTriggerUnit was reset) — it prefetches ch0 again.
        vm.setEnabled(true)
        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()
        #expect(await prefetcher.callsFor(Self.threeUnits[0]) == 2)
    }

    @Test func disable_recordedUnavailableUnitsAreCleared() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher(outcome: .offline)
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()
        #expect(vm.isUnavailable(Self.threeUnits[0]))

        vm.setEnabled(false)
        #expect(vm.isUnavailable(Self.threeUnits[0]) == false)
    }

    // MARK: - Epoch / cancellation

    @Test func staleEpochResult_isDiscarded_afterDisable() async throws {
        // A prefetch in flight when the user disables must not write its
        // result into a now-disabled VM.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher(
            outcome: .segments(["stale"]), delayNanos: 80_000_000)  // 80ms
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        // Disable while the prefetch is still sleeping.
        vm.setEnabled(false)
        await vm.awaitPrefetchForTesting()

        // The stale result was discarded — disable already cleared the dict.
        #expect(vm.translationsByUnit.isEmpty)
    }

    @Test func unitChange_cancelsPriorEpochPrefetch() async throws {
        // A real unit change bumps the epoch; an in-flight prefetch from the
        // prior epoch is cancelled and its result discarded.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher(
            outcome: .segments(["e0"]), delayNanos: 60_000_000)  // 60ms
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        // First trigger: unit ch0. Then immediately move to ch2 before ch0's
        // prefetch resolves.
        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.handlePositionChange(Self.locator(charOffset: 250))
        await vm.awaitPrefetchForTesting()

        // The current unit after the churn is ch2 — its translation landed.
        #expect(vm.translations(for: Self.threeUnits[2]) != nil)
    }

    // MARK: - Retry after transient failure (Codex audit round 1)

    @Test func transientFailure_retriesOnNextPositionChangeInSameUnit() async throws {
        // A transient provider failure must leave the unit retryable WITHOUT
        // the reader having to leave and re-enter it — a later position
        // change still inside the same unit re-triggers the prefetch.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // First call to each unit fails transiently; the retry succeeds.
        let prefetcher = SpyPrefetcher(
            outcome: .segments(["译"]), failFirstNCalls: 1)
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        // Position inside ch0 — prefetch fails transiently.
        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()
        #expect(vm.translations(for: Self.threeUnits[0]) == nil)

        // A second position change STILL inside ch0 re-triggers the prefetch
        // (the failed unit is no longer deduped away) — this time it succeeds.
        await vm.handlePositionChange(Self.locator(charOffset: 50))
        await vm.awaitPrefetchForTesting()
        #expect(vm.translations(for: Self.threeUnits[0]) == ["译"])
    }

    // MARK: - Empty book

    @Test func emptyBook_positionChangeIsNoOp() async throws {
        // A book with zero units — `unit(containing:)` returns nil — must not
        // crash or prefetch.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: []), prefetcher: prefetcher)

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()
        #expect(await prefetcher.callCount() == 0)
        #expect(vm.translationsByUnit.isEmpty)
    }

    // MARK: - Stale-launch race (Codex audit round 1 — High)

    @Test func disableDuringUnitAfterSuspension_doesNotStartStalePrefetch() async throws {
        // `handlePositionChange` resolves `unit(after:)` (a suspension point)
        // BEFORE mutating epoch/lastTriggerUnit. If the VM is disabled during
        // that suspension, the now-stale invocation must NOT start prefetches.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        // A provider whose `unit(after:)` blocks until the test releases it.
        let slowProvider = SuspendingNextProvider(units: Self.threeUnits)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(slowProvider)
        vm.attachPrefetcher(prefetcher)
        vm.setEnabled(true)
        vm.dismissSetupSheet()

        // Launch handlePositionChange; it will suspend inside `unit(after:)`.
        let handling = Task { await vm.handlePositionChange(Self.locator(charOffset: 0)) }
        // Give the task a moment to reach the suspension, then disable.
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        vm.setEnabled(false)
        // Release `unit(after:)` so the stale invocation resumes.
        await slowProvider.release()
        await handling.value
        await vm.awaitPrefetchForTesting()

        // The stale invocation re-validated `isEnabled` after the suspension
        // and started nothing.
        #expect(await prefetcher.callCount() == 0)
        #expect(vm.translationsByUnit.isEmpty)
    }

    @Test func interleavedPositionChanges_laterUnitWins_notTheStaleOlderOne() async throws {
        // Codex audit round 2: two `handlePositionChange` calls interleave
        // across the `unit(after:)` suspension. Call A (ch0) suspends; call B
        // (ch2) resumes first and sets the trigger. When A resumes it must NOT
        // start stale ch0 prefetches — the monotonic request token, not the
        // unit comparison, defeats this (ch0 != ch2 alone would let A through).
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let slowProvider = SuspendingNextProvider(units: Self.threeUnits)
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(slowProvider)
        vm.attachPrefetcher(prefetcher)
        vm.setEnabled(true)
        vm.dismissSetupSheet()

        // Call A — position inside ch0. Suspends in the first `unit(after:)`.
        let callA = Task { await vm.handlePositionChange(Self.locator(charOffset: 0)) }
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        // Call B — position inside ch2. Its `unit(after:)` does not block.
        await vm.handlePositionChange(Self.locator(charOffset: 250))
        // Release A's suspended `unit(after:)`; A resumes — and must stop.
        await slowProvider.release()
        await callA.value
        await vm.awaitPrefetchForTesting()

        // B won: ch2 is translated. A's stale ch0/ch1 prefetches never ran.
        #expect(vm.translations(for: Self.threeUnits[2]) != nil)
        #expect(await prefetcher.callsFor(Self.threeUnits[0]) == 0)
        #expect(await prefetcher.callsFor(Self.threeUnits[1]) == 0)
    }

    // MARK: - Notification

    @Test func successfulPrefetch_postsReaderBilingualDidChange() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(
            dir: dir, provider: StubProvider(units: Self.threeUnits), prefetcher: prefetcher)

        nonisolated(unsafe) var receivedKeys: [String] = []
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualDidChange, object: nil, queue: .main
        ) { note in
            if let key = note.userInfo?["fingerprintKey"] as? String {
                receivedKeys.append(key)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await vm.handlePositionChange(Self.locator(charOffset: 0))
        await vm.awaitPrefetchForTesting()

        // At least one change posted for this book.
        #expect(receivedKeys.contains(Self.bookKey))
    }

    @Test func toggle_postsReaderBilingualDidChange() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)

        nonisolated(unsafe) var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualDidChange, object: nil, queue: .main
        ) { note in
            if (note.userInfo?["fingerprintKey"] as? String) == Self.bookKey { count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.setEnabled(true)   // a renderer must react: clear/inject
        vm.setEnabled(false)
        #expect(count >= 2)
    }
}
