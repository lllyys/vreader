// Purpose: Bug #245 / GH #1070 — regression test for the missing
// `handlePositionChange` trigger in the TXT bilingual host wiring.
//
// EPUB / Foliate / PDF / MD all wire `vm.handlePositionChange(locator)` —
// either directly (EPUB / Foliate / PDF) or by posting
// `.readerPositionDidChange` (MD) so the bilingual VM's prefetch trigger
// fires and `translationsByUnit` populates from the disk cache (or a fresh
// remote fetch). TXT shipped without this trigger, so the in-memory dict
// stayed empty even after `ZCHAPTERTRANSLATION` rows were written —
// chapter text rendered English-only despite bilingual mode being ON and
// the disk cache being warm.
//
// This suite pins:
// - `TXTBilingualSurfacesModifier` exposes an `onPositionChanged: () -> Void`
//   callback (structural mirror of `PDFBilingualSurfacesModifier`).
// - `TXTReaderContainerView.triggerBilingualPositionChange(viewModel:locator:)`
//   populates `translationsByUnit` for the unit indicated by the locator
//   when the VM is enabled with a real TXT chapter-text provider and a
//   prefetcher returning canned segments.
//
// @coordinates-with: TXTReaderContainerView+Bilingual.swift,
//   BilingualReadingViewModel.swift,
//   BilingualReadingViewModel+Prefetch.swift,
//   TXTChapterTextProvider.swift,
//   dev-docs/verification/feature-56-20260520-round2.md (filing context)

#if canImport(UIKit)
import Testing
import Foundation
import SwiftUI
@testable import vreader

@MainActor
@Suite("Bug #245 — TXT bilingual position-change trigger")
struct TXTReaderContainerBilingualPositionTriggerTests {

    // MARK: - Test doubles

    /// Records every prefetch call; returns canned segments.
    private actor StubPrefetcher: ChapterPrefetching {
        private let segments: [String]
        private(set) var calls: [TranslationUnitID] = []

        init(segments: [String] = ["译文一", "译文二"]) {
            self.segments = segments
        }

        func translatedSegments(
            for unit: TranslationUnitID,
            targetLanguage: String,
            granularity: TranslationGranularity
        ) async throws -> [String] {
            calls.append(unit)
            return segments
        }

        func callCount() -> Int { calls.count }
        func callsFor(_ unit: TranslationUnitID) -> Int {
            calls.filter { $0 == unit }.count
        }
    }

    // MARK: - Structural pin — modifier exposes `onPositionChanged`

    @Test("TXTBilingualSurfacesModifier exposes onPositionChanged callback")
    func modifierHasOnPositionChanged() {
        // Bug #245 root cause: the TXT modifier was missing this callback
        // (PDF / EPUB / Foliate all have one). This is a compile-time
        // structural assertion — RED before the field is added.
        nonisolated(unsafe) var positionChangeFired = false
        let modifier = TXTBilingualSurfacesModifier(
            bookFingerprintKey: "txt:fixture",
            chapterIndexNonce: 1,
            textContentReady: true,
            currentChapterIdxNonce: 0,
            ensureViewModel: {},
            onMoreBilingualToggle: {},
            onPositionChanged: { positionChangeFired = true },
            onReTranslateApplied: { _, _ in },
            showSetupSheet: .constant(false),
            sheetView: { AnyView(EmptyView()) },
            onSheetDismiss: {}
        )
        // Fire the callback to confirm the wiring is exposed end-to-end.
        modifier.onPositionChanged()
        #expect(positionChangeFired)
        // Silence the modifier-unused warning — the structural assertion
        // is the existence of the initializer with this argument shape.
        _ = modifier
    }

    // MARK: - Behavior — static helper drives the VM trigger

    @Test("triggerBilingualPositionChange populates translationsByUnit for the locator's chapter")
    func triggerPopulatesTranslations() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fingerprint = Self.fingerprint
        let chapters = Self.chapters
        let fullText = chapters.map { String(repeating: "A", count: $0.textLengthUTF16) }
            .joined()

        let provider = TXTChapterTextProvider(
            fingerprint: fingerprint, fullText: fullText, chapters: chapters)
        let prefetcher = StubPrefetcher(segments: ["第一句", "第二句"])

        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        vm.attachProvider(provider)
        vm.attachPrefetcher(prefetcher)
        vm.setEnabled(true)
        vm.dismissSetupSheet()

        // Sanity: dict is empty before the trigger fires.
        let unit0 = TranslationUnitID(kind: .txtChapterIndex, value: "0")
        #expect(vm.translations(for: unit0) == nil)

        // Drive the trigger via the static helper that the TXT bilingual
        // extension exposes (the new GREEN code). The helper launches a
        // Task that calls `vm.handlePositionChange(locator)`, so we yield
        // once to let it start, then drain the prefetch tasks.
        let locator = Self.locator(charOffset: 0, fingerprint: fingerprint)
        TXTReaderContainerView.triggerBilingualPositionChange(
            viewModel: vm, locator: locator
        )
        // Yield repeatedly until the outer Task has at least entered
        // `handlePositionChange` and queued a prefetch — `awaitPrefetchForTesting`
        // only awaits tasks that already exist in `prefetchTasks`.
        for _ in 0..<50 {
            await Task.yield()
            if await prefetcher.callCount() > 0 { break }
        }
        await vm.awaitPrefetchForTesting()

        // Disk-cache-hit equivalent: the prefetcher (stand-in for
        // ChapterTranslationService + cache hit) returns segments, which
        // the VM stores in translationsByUnit — the dict the renderer
        // reads via `vm.translations(for:)`.
        #expect(vm.translations(for: unit0) == ["第一句", "第二句"])
        #expect(await prefetcher.callsFor(unit0) == 1)
    }

    @Test("trigger is a no-op when viewModel is nil")
    func triggerNilVMIsNoOp() async {
        // The trigger guards `viewModel ?? return` — calling with nil
        // must not crash and must not start any work.
        let locator = Self.locator(charOffset: 0, fingerprint: Self.fingerprint)
        TXTReaderContainerView.triggerBilingualPositionChange(
            viewModel: nil, locator: locator
        )
        // Nothing to assert on output — the contract is "does not crash".
    }

    @Test("trigger is a no-op when locator is nil")
    func triggerNilLocatorIsNoOp() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = StubPrefetcher()
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        let provider = TXTChapterTextProvider(
            fingerprint: Self.fingerprint, fullText: "ABC", chapters: Self.chapters)
        vm.attachProvider(provider)
        vm.attachPrefetcher(prefetcher)
        vm.setEnabled(true)
        vm.dismissSetupSheet()

        TXTReaderContainerView.triggerBilingualPositionChange(
            viewModel: vm, locator: nil
        )
        await vm.awaitPrefetchForTesting()

        #expect(await prefetcher.callCount() == 0)
    }

    @Test("trigger is a no-op when VM is disabled")
    func triggerDisabledVMIsNoOp() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefetcher = StubPrefetcher()
        let vm = BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
        let provider = TXTChapterTextProvider(
            fingerprint: Self.fingerprint, fullText: "ABC", chapters: Self.chapters)
        vm.attachProvider(provider)
        vm.attachPrefetcher(prefetcher)
        // NOT enabled — the trigger must short-circuit.

        let locator = Self.locator(charOffset: 0, fingerprint: Self.fingerprint)
        TXTReaderContainerView.triggerBilingualPositionChange(
            viewModel: vm, locator: locator
        )
        await vm.awaitPrefetchForTesting()

        #expect(await prefetcher.callCount() == 0)
    }

    // MARK: - Fixtures

    private static let bookKey =
        "txt:cc00112233445566778899aabbccddeeff00112233445566778899aabbccdd:4096"

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: String(repeating: "c", count: 64),
        fileByteCount: 4096,
        format: .txt)

    /// Two chapters with deterministic UTF-16 offsets so
    /// `TXTChapterTextProvider.unit(containing:)` resolves an offset of
    /// 0 to chapter index 0 and an offset of 200 to chapter index 1.
    private static let chapters: [TXTChapter] = [
        TXTChapter(
            index: 0, title: "Chapter 1",
            startByte: 0, endByte: 100,
            globalStartUTF16: 0, textLengthUTF16: 100
        ),
        TXTChapter(
            index: 1, title: "Chapter 2",
            startByte: 100, endByte: 200,
            globalStartUTF16: 100, textLengthUTF16: 100
        )
    ]

    private static func locator(
        charOffset: Int, fingerprint: DocumentFingerprint
    ) -> Locator {
        Locator(
            bookFingerprint: fingerprint, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: charOffset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TXTBilingualPositionTrigger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
#endif
