// Purpose: Tests for TXTReaderViewModel's continuous-scroll mode (Bug #180
// re-scoped fix, WI-5/6/8). Covers `openContinuous`, offset-derived
// `currentChapterIdx`, cross-boundary scroll, locator construction, TOC-jump
// retargeting, and saved-position restore.
//
// Tests live in vreaderTests/ViewModels/ to mirror the source path.

import Testing
import Foundation
@testable import vreader

@Suite("TXTReaderViewModel — continuous scroll")
@MainActor
struct TXTReaderViewModelContinuousTests {

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: "continuous_test_sha256_000000000000000000000000000000000000000000",
        fileByteCount: 5000,
        format: .txt
    )
    private static let testURL = URL(fileURLWithPath: "/tmp/continuous-test.txt")

    // 3 chapters of known UTF-16 lengths. Chapter text bodies are sized so the
    // whole-book offsets are easy to assert against.
    private static let ch1 = String(repeating: "A", count: 100)
    private static let ch2 = String(repeating: "B", count: 150)
    private static let ch3 = String(repeating: "C", count: 120)

    /// Builds a 3-chapter open result whose concatenated text is ch1+ch2+ch3.
    private static func makeOpenResult() -> TXTChapterOpenResult {
        let allText = ch1 + ch2 + ch3
        let data = Data(allText.utf8)
        let ch1Len = ch1.utf16.count   // 100
        let ch2Len = ch2.utf16.count   // 150
        let ch3Len = ch3.utf16.count   // 120
        let chapters = [
            TXTChapter(index: 0, title: "Chapter One", startByte: 0,
                       endByte: Int64(ch1Len),
                       globalStartUTF16: 0, textLengthUTF16: ch1Len),
            TXTChapter(index: 1, title: "Chapter Two", startByte: Int64(ch1Len),
                       endByte: Int64(ch1Len + ch2Len),
                       globalStartUTF16: ch1Len, textLengthUTF16: ch2Len),
            TXTChapter(index: 2, title: "Chapter Three",
                       startByte: Int64(ch1Len + ch2Len),
                       endByte: Int64(ch1Len + ch2Len + ch3Len),
                       globalStartUTF16: ch1Len + ch2Len, textLengthUTF16: ch3Len),
        ]
        let index = TXTChapterIndex(
            chapters: chapters, totalBytes: Int64(data.count),
            detectedEncoding: "UTF-8",
            totalTextLengthUTF16: ch1Len + ch2Len + ch3Len
        )
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)
        return TXTChapterOpenResult(
            chapterIndex: index, contentLoader: loader,
            fileByteCount: Int64(data.count), detectedEncoding: "UTF-8"
        )
    }

    private static func makeVM(
        result: TXTChapterOpenResult? = nil
    ) async -> (TXTReaderViewModel, MockPositionStore) {
        let service = MockTXTService()
        if let result { await service.setChapterOpenResult(result) }
        let positionStore = MockPositionStore()
        let tracker = ReadingSessionTracker(
            clock: MockClock(), store: MockSessionStore(), deviceId: "test-device"
        )
        let vm = TXTReaderViewModel(
            bookFingerprint: fingerprint, txtService: service,
            positionStore: positionStore, sessionTracker: tracker,
            deviceId: "test-device", positionSaveDebounceNs: 0
        )
        return (vm, positionStore)
    }

    // MARK: - openContinuous

    @Test func openContinuousBuildsChapterOffsetIndexAndChunks() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.isContinuousMode == true)
        #expect(vm.chapterOffsetIndex != nil)
        #expect(vm.chapterOffsetIndex?.chapters.count == 3)
        #expect(vm.continuousChunks != nil)
        #expect(vm.continuousChunks?.isEmpty == false)
    }

    @Test func openContinuousConcatenatedChunksEqualWholeBook() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        let joined = vm.continuousChunks?.joined()
        #expect(joined == Self.ch1 + Self.ch2 + Self.ch3)
    }

    @Test func openContinuousSetsTotalLength() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.totalTextLengthUTF16 == 100 + 150 + 120)
    }

    @Test func openContinuousChunkOffsetsAreCumulative() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        let offsets = vm.continuousChunkStartOffsets ?? []
        let chunks = vm.continuousChunks ?? []
        #expect(offsets.count == chunks.count)
        #expect(offsets.first == 0)
        var cumulative = 0
        for (i, chunk) in chunks.enumerated() {
            #expect(offsets[i] == cumulative)
            cumulative += chunk.utf16.count
        }
    }

    // MARK: - currentChapterIdx derived from offset

    @Test func updateScrollPositionDerivesChapterAtBoundary() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        // Global offset 100 is exactly chapter 1's start.
        vm.updateScrollPosition(charOffsetUTF16: 100)
        #expect(vm.currentChapterIdx == 1)
    }

    @Test func updateScrollPositionDerivesChapterMidChapter() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        vm.updateScrollPosition(charOffsetUTF16: 50)   // ch0
        #expect(vm.currentChapterIdx == 0)
        vm.updateScrollPosition(charOffsetUTF16: 200)  // ch1 ([100,250))
        #expect(vm.currentChapterIdx == 1)
        vm.updateScrollPosition(charOffsetUTF16: 300)  // ch2 ([250,370))
        #expect(vm.currentChapterIdx == 2)
    }

    @Test func updateScrollPositionDerivesLastChapter() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        vm.updateScrollPosition(charOffsetUTF16: 369)
        #expect(vm.currentChapterIdx == 2)
    }

    @Test func scrollingAcrossBoundaryFlipsChapterByOne() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        vm.updateScrollPosition(charOffsetUTF16: 99)   // last offset of ch0
        #expect(vm.currentChapterIdx == 0)
        vm.updateScrollPosition(charOffsetUTF16: 100)  // first offset of ch1
        #expect(vm.currentChapterIdx == 1)
        #expect(vm.currentChapterTitle == "Chapter Two")
    }

    @Test func updateScrollPositionSetsLocalAndGlobalOffsets() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        // Global offset 175 → chapter 1, local 75.
        vm.updateScrollPosition(charOffsetUTF16: 175)
        #expect(vm.currentOffsetUTF16 == 175)
        #expect(vm.currentChapterLocalUTF16 == 75)
        #expect(vm.currentChapterIdx == 1)
    }

    // MARK: - makeLocator in continuous mode

    @Test func makeLocatorEmitsTxtChapterHrefWithDerivedIdxLocal() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        vm.updateScrollPosition(charOffsetUTF16: 175)  // ch1 local 75
        let locator = vm.makeLocator()
        #expect(locator.href == "txtchapter:1:75")
        #expect(locator.charOffsetUTF16 == 175)
    }

    @Test func makeLocatorAtChapterStartHasLocalZero() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        vm.updateScrollPosition(charOffsetUTF16: 250)  // ch2 start
        let locator = vm.makeLocator()
        #expect(locator.href == "txtchapter:2:0")
        #expect(locator.charOffsetUTF16 == 250)
    }

    // MARK: - TOC jump retargeting (WI-6)
    //
    // In continuous mode the container's `onNavigate` publishes the TOC
    // entry's already-document-global `charOffsetUTF16` straight to
    // `uiState.scrollToOffset` (plan §3.3) — the chunked bridge's
    // `scrollToGlobalOffset` then binary-searches the containing chunk. The
    // chapter is derived afterward from where the scroll lands, so there is
    // no VM-level TOC-jump helper to unit-test here; `chapterContaining`
    // (TXTChapterOffsetIndexTests) covers the offset→chapter derivation.

    // MARK: - chapterScrollFraction in continuous mode (WI-8)

    @Test func chapterScrollFractionZeroAtChapterStart() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        vm.updateScrollPosition(charOffsetUTF16: 100)  // ch1 start
        #expect(vm.chapterScrollFraction == 0.0)
    }

    @Test func chapterScrollFractionNearOneAtChapterEnd() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        // ch1 spans [100,250) length 150; offset 249 → local 149 → 0.993.
        vm.updateScrollPosition(charOffsetUTF16: 249)
        #expect(abs(vm.chapterScrollFraction - (149.0 / 150.0)) < 0.0001)
    }

    // MARK: - restore (WI-8)

    @Test func openContinuousRestoresViaTxtChapterHref() async {
        let (vm, store) = await Self.makeVM(result: Self.makeOpenResult())
        // Saved position: chapter 2, local offset 20 → global 250 + 20 = 270.
        let locator = Locator(
            bookFingerprint: Self.fingerprint, href: "txtchapter:2:20",
            progression: nil, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 99999, charRangeStartUTF16: nil,
            charRangeEndUTF16: nil, textQuote: nil, textContextBefore: nil,
            textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                         locator: locator)
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.continuousRestoreGlobalOffset == 270)
        #expect(vm.currentChapterIdx == 2)
        #expect(vm.currentOffsetUTF16 == 270)
    }

    @Test func openContinuousRestoresViaLegacyGlobalOffset() async {
        let (vm, store) = await Self.makeVM(result: Self.makeOpenResult())
        // Legacy locator: bare global offset 175 (chapter 1).
        guard let locator = LocatorFactory.txtPosition(
            fingerprint: Self.fingerprint, charOffsetUTF16: 175
        ) else {
            Issue.record("Failed to create locator")
            return
        }
        await store.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                         locator: locator)
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.continuousRestoreGlobalOffset == 175)
        #expect(vm.currentChapterIdx == 1)
    }

    @Test func openContinuousNoSavedPositionStartsAtZero() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.continuousRestoreGlobalOffset == nil)
        #expect(vm.currentOffsetUTF16 == 0)
        #expect(vm.currentChapterIdx == 0)
    }

    // MARK: - close clears continuous state

    @Test func closeClearsContinuousState() async {
        let (vm, _) = await Self.makeVM(result: Self.makeOpenResult())
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.isContinuousMode == true)
        await vm.close()
        #expect(vm.isContinuousMode == false)
        #expect(vm.chapterOffsetIndex == nil)
        #expect(vm.continuousChunks == nil)
    }

    // MARK: - single-chapter fallback

    @Test func openContinuousSingleChapterFallsBackToNonContinuous() async {
        // Codex round-1 audit fix [High]: a book with <2 chapters never swaps
        // chapters, so `openContinuous` must NOT route it through the
        // continuous surface — it falls back to the legacy chapter-based path.
        // This preserves the plan's "non-chaptered TXT unchanged" invariant
        // (`openChapterBased` synthesizes exactly one chapter for short
        // non-chaptered text).
        let text = String(repeating: "X", count: 200)
        let data = Data(text.utf8)
        let chapters = [TXTChapter(
            index: 0, title: "Only", startByte: 0, endByte: Int64(data.count),
            globalStartUTF16: 0, textLengthUTF16: text.utf16.count
        )]
        let index = TXTChapterIndex(
            chapters: chapters, totalBytes: Int64(data.count),
            detectedEncoding: "UTF-8", totalTextLengthUTF16: text.utf16.count
        )
        let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)
        let result = TXTChapterOpenResult(
            chapterIndex: index, contentLoader: loader,
            fileByteCount: Int64(data.count), detectedEncoding: "UTF-8"
        )
        let (vm, _) = await Self.makeVM(result: result)
        await vm.openContinuous(url: Self.testURL)
        // Single chapter → continuous surface NOT built; legacy chapter path.
        #expect(vm.isContinuousMode == false)
        #expect(vm.chapterOffsetIndex == nil)
        // Still opened (the legacy chapter path loaded the one chapter).
        #expect(vm.currentChapterText == text)
    }
}
