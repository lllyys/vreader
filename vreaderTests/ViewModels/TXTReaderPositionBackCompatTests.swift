// Purpose: Backward-compatibility tests for TXT saved-position restore over
// the continuous-scroll surface (Bug #180 re-scoped fix, WI-8). Verifies that
// positions saved by older (pre-fix / PR #681) builds restore correctly, and
// that a position saved by the new continuous build round-trips identically.
//
// Tests live in vreaderTests/ViewModels/ to mirror the source path.

import Testing
import Foundation
@testable import vreader

@Suite("TXTReaderViewModel — continuous-scroll position back-compat")
@MainActor
struct TXTReaderPositionBackCompatTests {

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: "backcompat_test_sha256_0000000000000000000000000000000000000000000",
        fileByteCount: 4000,
        format: .txt
    )
    private static let testURL = URL(fileURLWithPath: "/tmp/backcompat-test.txt")

    private static let ch1 = String(repeating: "P", count: 120)
    private static let ch2 = String(repeating: "Q", count: 180)
    private static let ch3 = String(repeating: "R", count: 100)

    private static func makeOpenResult() -> TXTChapterOpenResult {
        let allText = ch1 + ch2 + ch3
        let data = Data(allText.utf8)
        let ch1Len = ch1.utf16.count   // 120
        let ch2Len = ch2.utf16.count   // 180
        let ch3Len = ch3.utf16.count   // 100
        let chapters = [
            TXTChapter(index: 0, title: "Ch One", startByte: 0,
                       endByte: Int64(ch1Len),
                       globalStartUTF16: 0, textLengthUTF16: ch1Len),
            TXTChapter(index: 1, title: "Ch Two", startByte: Int64(ch1Len),
                       endByte: Int64(ch1Len + ch2Len),
                       globalStartUTF16: ch1Len, textLengthUTF16: ch2Len),
            TXTChapter(index: 2, title: "Ch Three",
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
        result: TXTChapterOpenResult
    ) async -> (TXTReaderViewModel, MockPositionStore) {
        let service = MockTXTService()
        await service.setChapterOpenResult(result)
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

    @Test func oldTxtChapterHrefRestoresToCorrectContinuousOffset() async {
        let (vm, store) = await Self.makeVM(result: Self.makeOpenResult())
        // A pre-fix build saved `txtchapter:1:50` — chapter 1, local 50.
        // Continuous global = chapter-1 start (120) + 50 = 170.
        let locator = Locator(
            bookFingerprint: Self.fingerprint, href: "txtchapter:1:50",
            progression: nil, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 170, charRangeStartUTF16: nil,
            charRangeEndUTF16: nil, textQuote: nil, textContextBefore: nil,
            textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                         locator: locator)
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.continuousRestoreGlobalOffset == 170)
        #expect(vm.currentChapterIdx == 1)
        #expect(vm.currentOffsetUTF16 == 170)
    }

    @Test func legacyBareGlobalOffsetLocatorRestoresViaResolver() async {
        let (vm, store) = await Self.makeVM(result: Self.makeOpenResult())
        // A legacy locator with no href, bare global offset 250 (chapter 1).
        guard let locator = LocatorFactory.txtPosition(
            fingerprint: Self.fingerprint, charOffsetUTF16: 250
        ) else {
            Issue.record("Failed to create legacy locator")
            return
        }
        await store.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                         locator: locator)
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.continuousRestoreGlobalOffset == 250)
        // Global 250 is inside chapter 1 ([120,300)).
        #expect(vm.currentChapterIdx == 1)
    }

    @Test func newContinuousBuildPositionRoundTripsIdentically() async {
        // Open continuous, scroll to a known offset, capture the saved locator,
        // reopen with that locator, and confirm the restore offset matches.
        let (vm1, store) = await Self.makeVM(result: Self.makeOpenResult())
        await vm1.openContinuous(url: Self.testURL)
        // Scroll to global 330 → chapter 2 ([300,400)), local 30.
        vm1.updateScrollPosition(charOffsetUTF16: 330)
        let saved = vm1.makeLocator()
        #expect(saved.href == "txtchapter:2:30")
        #expect(saved.charOffsetUTF16 == 330)
        await store.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                         locator: saved)

        // Reopen a fresh VM with the saved locator.
        let (vm2, _) = await Self.makeVM(result: Self.makeOpenResult())
        // vm2 shares the same fingerprint; seed already done on a shared store
        // would not carry — seed vm2's own store.
        await vm2.openContinuous(url: Self.testURL)
        // vm2's store has no seeded position, so verify the round-trip via a
        // VM that DOES read the seeded store.
        let (vm3, store3) = await Self.makeVM(result: Self.makeOpenResult())
        await store3.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                          locator: saved)
        await vm3.openContinuous(url: Self.testURL)
        #expect(vm3.continuousRestoreGlobalOffset == 330)
        #expect(vm3.currentChapterIdx == 2)
        #expect(vm3.currentOffsetUTF16 == 330)
    }

    @Test func restoreAtExactChapterEndDerivesChapterFromGlobalOffset() async {
        // Codex round-1 audit fix [Medium]: `resolveChapterPosition` can clamp
        // a saved local offset to the chapter's textLengthUTF16 at an exact
        // chapter end. A saved `txtchapter:0:120` (chapter 0 length 120 → local
        // clamps to 120) yields global = 0 + 120 = 120, which is chapter 1's
        // start. The VM must DERIVE currentChapterIdx from the global offset
        // (→ chapter 1), not trust the saved idx 0.
        let (vm, store) = await Self.makeVM(result: Self.makeOpenResult())
        let locator = Locator(
            bookFingerprint: Self.fingerprint, href: "txtchapter:0:120",
            progression: nil, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 120, charRangeStartUTF16: nil,
            charRangeEndUTF16: nil, textQuote: nil, textContextBefore: nil,
            textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                         locator: locator)
        await vm.openContinuous(url: Self.testURL)
        #expect(vm.continuousRestoreGlobalOffset == 120)
        #expect(vm.currentOffsetUTF16 == 120)
        // Global 120 is chapter 1's start ([120,300)), NOT chapter 0.
        #expect(vm.currentChapterIdx == 1)
        #expect(vm.currentChapterLocalUTF16 == 0)
        // makeLocator must reflect the derived chapter, not the saved idx 0.
        #expect(vm.makeLocator().href == "txtchapter:1:0")
    }

    @Test func positionAtChapterZeroStartDoesNotForceRestoreScroll() async {
        // A saved position at global offset 0 → no restore scroll needed.
        let (vm, store) = await Self.makeVM(result: Self.makeOpenResult())
        let locator = Locator(
            bookFingerprint: Self.fingerprint, href: "txtchapter:0:0",
            progression: nil, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 0, charRangeStartUTF16: nil,
            charRangeEndUTF16: nil, textQuote: nil, textContextBefore: nil,
            textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: Self.fingerprint.canonicalKey,
                         locator: locator)
        await vm.openContinuous(url: Self.testURL)
        // Offset 0 → restoreGlobalOffset stays nil (nothing to scroll to).
        #expect(vm.continuousRestoreGlobalOffset == nil)
        #expect(vm.currentChapterIdx == 0)
    }
}
