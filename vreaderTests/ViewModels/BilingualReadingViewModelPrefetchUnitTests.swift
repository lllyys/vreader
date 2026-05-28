// Purpose: Feature #71 WI-7 (Gate-4 round-2 HIGH 1) — pin the
// unit-scoped prefetch method `BilingualReadingViewModel.prefetchUnitIfNeeded(_:)`.
//
// Continuous-scroll EPUB stitches multiple chapter sections into one
// document; each section materializes independently and may be
// OFF-SCREEN relative to the visible locator. The whole-book
// `handlePositionChange` trigger resolves prefetch targets from the
// CURRENT visible locator and dedupes against `lastTriggerUnit`, so it
// cannot be reused to prefetch an arbitrary adjacent section's unit
// without clobbering the trigger state.
//
// `prefetchUnitIfNeeded(_:)` is the minimal unit-scoped seam: prefetch
// ONE explicit unit, reusing the existing `startPrefetch` internals,
// WITHOUT touching `lastTriggerUnit` / `triggerRequestSeq` / the
// visible-locator trigger. This file pins that scoping.
//
// @coordinates-with: BilingualReadingViewModel.swift,
//   BilingualReadingViewModel+Prefetch.swift,
//   EPUBReaderContainerView+ContinuousBilingual.swift (the caller)

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #71 WI-7 — BilingualReadingViewModel.prefetchUnitIfNeeded")
struct BilingualReadingViewModelPrefetchUnitTests {

    private struct StubProvider: ChapterTextProviding {
        let units: [TranslationUnitID]
        func translationUnits() async throws -> [TranslationUnitID] { units }
        func sourceText(for unit: TranslationUnitID) async throws -> String {
            "source for \(unit.value)"
        }
        func unit(containing locator: Locator) async -> TranslationUnitID? {
            guard let href = locator.href else { return nil }
            return units.first { $0.value == href }
        }
        func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
            guard let i = units.firstIndex(of: unit), i + 1 < units.count else { return nil }
            return units[i + 1]
        }
    }

    private actor SpyPrefetcher: ChapterPrefetching {
        private(set) var calls: [TranslationUnitID] = []
        func translatedSegments(
            for unit: TranslationUnitID,
            targetLanguage: String,
            granularity: TranslationGranularity
        ) async throws -> [String] {
            calls.append(unit)
            return ["译文-\(unit.value)"]
        }
        func callsFor(_ unit: TranslationUnitID) -> Int { calls.filter { $0 == unit }.count }
        var total: Int { calls.count }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BilingualPrefetchUnit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let bookKey =
        "epub:aa00112233445566778899aabbccddeeff00112233445566778899aabbccdd:4096"

    private static let units: [TranslationUnitID] = [
        TranslationUnitID(kind: .epubHref, value: "ch0.xhtml"),
        TranslationUnitID(kind: .epubHref, value: "ch1.xhtml"),
        TranslationUnitID(kind: .epubHref, value: "ch2.xhtml"),
    ]

    private func makeEnabledVM(dir: URL, prefetcher: SpyPrefetcher) -> BilingualReadingViewModel {
        let vm = BilingualReadingViewModel(bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(StubProvider(units: Self.units))
        vm.attachPrefetcher(prefetcher)
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        return vm
    }

    @Test func prefetchUnitIfNeeded_fetchesNamedUnit() async throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(dir: dir, prefetcher: prefetcher)
        vm.prefetchUnitIfNeeded(Self.units[1])
        await vm.awaitPrefetchForTesting()
        #expect(vm.translationsByUnit[Self.units[1]] == ["译文-ch1.xhtml"])
        #expect(await prefetcher.callsFor(Self.units[1]) == 1)
    }

    @Test func prefetchUnitIfNeeded_doesNotTouchTriggerState() async throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(dir: dir, prefetcher: prefetcher)
        // Simulate the visible-locator trigger having acted on unit 0.
        vm.lastTriggerUnit = Self.units[0]
        let seqBefore = vm.triggerRequestSeq
        // Prefetch an OFF-SCREEN adjacent section's unit.
        vm.prefetchUnitIfNeeded(Self.units[2])
        await vm.awaitPrefetchForTesting()
        // The whole-book trigger state must be untouched — a continuous
        // off-screen section prefetch must not move the dedupe anchor.
        #expect(vm.lastTriggerUnit == Self.units[0])
        #expect(vm.triggerRequestSeq == seqBefore)
    }

    @Test func prefetchUnitIfNeeded_noOpWhenAlreadyCached() async throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = makeEnabledVM(dir: dir, prefetcher: prefetcher)
        vm.translationsByUnit[Self.units[1]] = ["已缓存"]
        vm.prefetchUnitIfNeeded(Self.units[1])
        await vm.awaitPrefetchForTesting()
        #expect(vm.translationsByUnit[Self.units[1]] == ["已缓存"])
        #expect(await prefetcher.callsFor(Self.units[1]) == 0)
    }

    @Test func prefetchUnitIfNeeded_noOpWhenDisabled() async throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = SpyPrefetcher()
        let vm = BilingualReadingViewModel(bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(StubProvider(units: Self.units))
        vm.attachPrefetcher(prefetcher)
        // Disabled.
        vm.prefetchUnitIfNeeded(Self.units[1])
        await vm.awaitPrefetchForTesting()
        #expect(await prefetcher.total == 0)
    }
}
