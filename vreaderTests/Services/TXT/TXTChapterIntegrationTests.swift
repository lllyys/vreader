// Purpose: Integration tests for WI-5 — chapter-based lazy loading.
// Tests the full open→load→navigate→close cycle using mocks.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTFileLoader.swift, TXTServiceProtocol.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let chapterFingerprint = DocumentFingerprint(
    contentSHA256: "chapter_int_test_sha256_00000000000000000000000000000000000000000",
    fileByteCount: 5000,
    format: .txt
)

private let chapterTestURL = URL(fileURLWithPath: "/tmp/chapter-test.txt")

// Chapter texts for testing
private let ch1Text = "Chapter 1 content with some words."
private let ch2Text = "Chapter 2 has different text here."
private let ch3Text = "Chapter 3 is the final chapter."

/// Builds a TXTChapterOpenResult with 3 chapters from in-memory text.
private func makeChapterOpenResult() -> TXTChapterOpenResult {
    let allText = ch1Text + ch2Text + ch3Text
    let allData = Data(allText.utf8)
    let ch1Len = Data(ch1Text.utf8).count
    let ch2Len = Data(ch2Text.utf8).count

    let ch1UTF16 = (ch1Text as NSString).length
    let ch2UTF16 = (ch2Text as NSString).length
    let ch3UTF16 = (ch3Text as NSString).length
    let totalUTF16 = ch1UTF16 + ch2UTF16 + ch3UTF16

    let chapters = [
        TXTChapter(
            index: 0, title: "Chapter 1",
            startByte: 0, endByte: Int64(ch1Len),
            globalStartUTF16: 0, textLengthUTF16: ch1UTF16
        ),
        TXTChapter(
            index: 1, title: "Chapter 2",
            startByte: Int64(ch1Len), endByte: Int64(ch1Len + ch2Len),
            globalStartUTF16: ch1UTF16, textLengthUTF16: ch2UTF16
        ),
        TXTChapter(
            index: 2, title: "Chapter 3",
            startByte: Int64(ch1Len + ch2Len), endByte: Int64(allData.count),
            globalStartUTF16: ch1UTF16 + ch2UTF16, textLengthUTF16: ch3UTF16
        ),
    ]

    let index = TXTChapterIndex(
        chapters: chapters,
        totalBytes: Int64(allData.count),
        detectedEncoding: "UTF-8",
        totalTextLengthUTF16: totalUTF16
    )

    let loader = TXTChapterContentLoader(fileData: allData, encoding: .utf8)

    return TXTChapterOpenResult(
        chapterIndex: index,
        contentLoader: loader,
        fileByteCount: Int64(allData.count),
        detectedEncoding: "UTF-8"
    )
}

/// Builds a single-chapter TXTChapterOpenResult.
private func makeSingleChapterResult() -> TXTChapterOpenResult {
    let text = "Only one chapter in this file."
    let data = Data(text.utf8)
    let utf16Len = (text as NSString).length

    let chapters = [
        TXTChapter(
            index: 0, title: "Chapter 1",
            startByte: 0, endByte: Int64(data.count),
            globalStartUTF16: 0, textLengthUTF16: utf16Len
        ),
    ]

    let index = TXTChapterIndex(
        chapters: chapters,
        totalBytes: Int64(data.count),
        detectedEncoding: "UTF-8",
        totalTextLengthUTF16: utf16Len
    )

    let loader = TXTChapterContentLoader(fileData: data, encoding: .utf8)

    return TXTChapterOpenResult(
        chapterIndex: index,
        contentLoader: loader,
        fileByteCount: Int64(data.count),
        detectedEncoding: "UTF-8"
    )
}

/// Builds an empty-file TXTChapterOpenResult.
private func makeEmptyChapterResult() -> TXTChapterOpenResult {
    let index = TXTChapterIndex(
        chapters: [],
        totalBytes: 0,
        detectedEncoding: "UTF-8",
        totalTextLengthUTF16: 0
    )
    let loader = TXTChapterContentLoader(fileData: Data(), encoding: .utf8)
    return TXTChapterOpenResult(
        chapterIndex: index,
        contentLoader: loader,
        fileByteCount: 0,
        detectedEncoding: "UTF-8"
    )
}

// MARK: - Helpers

@MainActor
private func makeChapterVM(
    fingerprint: DocumentFingerprint = chapterFingerprint,
    chapterResult: TXTChapterOpenResult? = nil,
    chapterOpenError: TXTServiceError? = nil,
    fullTextMetadata: TXTFileMetadata? = nil
) async -> (TXTReaderViewModel, MockTXTService, MockPositionStore) {
    let service = MockTXTService()
    if let result = chapterResult {
        await service.setChapterOpenResult(result)
    }
    if let error = chapterOpenError {
        await service.setChapterOpenError(error)
    }
    if let meta = fullTextMetadata {
        await service.setMetadata(meta)
    }

    let positionStore = MockPositionStore()
    let sessionStore = MockSessionStore()
    let clock = MockClock()
    let tracker = ReadingSessionTracker(
        clock: clock,
        store: sessionStore,
        deviceId: "test-device"
    )

    let vm = TXTReaderViewModel(
        bookFingerprint: fingerprint,
        txtService: service,
        positionStore: positionStore,
        sessionTracker: tracker,
        deviceId: "test-device",
        positionSaveDebounceNs: 0
    )

    return (vm, service, positionStore)
}

// MARK: - Chapter-Based Open

@Suite("TXTReaderViewModel - Chapter-Based Open (WI-5)")
@MainActor
struct TXTChapterOpenTests {

    @Test("openChapterBased sets chapter index")
    func setsChapterIndex() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)

        await vm.openChapterBased(url: chapterTestURL)

        #expect(vm.chapterIndex != nil)
        #expect(vm.chapterIndex?.count == 3)
        #expect(vm.isChapterMode == true)
    }

    @Test("openChapterBased loads initial chapter text")
    func loadsInitialChapter() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)

        await vm.openChapterBased(url: chapterTestURL)

        #expect(vm.currentChapterText == ch1Text)
        #expect(vm.textContent == ch1Text)
        #expect(vm.currentChapterIdx == 0)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test("openChapterBased sets total UTF-16 length from index")
    func setsTotalLength() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)

        await vm.openChapterBased(url: chapterTestURL)

        let expectedTotal = (ch1Text as NSString).length + (ch2Text as NSString).length + (ch3Text as NSString).length
        #expect(vm.totalTextLengthUTF16 == expectedTotal)
    }

    @Test("openChapterBased restores position to correct chapter")
    func restoresPositionToCorrectChapter() async {
        let result = makeChapterOpenResult()
        let (vm, _, positionStore) = await makeChapterVM(chapterResult: result)

        // Save a position in chapter 2 (offset = ch1UTF16 + 5)
        let ch1UTF16 = (ch1Text as NSString).length
        let savedOffset = ch1UTF16 + 5

        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: chapterFingerprint,
            charOffsetUTF16: savedOffset
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: chapterFingerprint.canonicalKey,
            locator: savedLocator
        )

        await vm.openChapterBased(url: chapterTestURL)

        #expect(vm.currentChapterIdx == 1)
        #expect(vm.currentChapterText == ch2Text)
        #expect(vm.currentOffsetUTF16 == savedOffset)
    }

    @Test("openChapterBased handles empty file")
    func emptyFile() async {
        let result = makeEmptyChapterResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)

        await vm.openChapterBased(url: chapterTestURL)

        #expect(vm.textContent == "")
        #expect(vm.chapterIndex?.isEmpty == true)
        #expect(vm.currentOffsetUTF16 == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("openChapterBased with single chapter")
    func singleChapter() async {
        let result = makeSingleChapterResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)

        await vm.openChapterBased(url: chapterTestURL)

        #expect(vm.chapterIndex?.count == 1)
        #expect(vm.currentChapterText == "Only one chapter in this file.")
        #expect(vm.currentChapterIdx == 0)
    }
}

// MARK: - Chapter Navigation

@Suite("TXTReaderViewModel - Chapter Navigation (WI-5)")
@MainActor
struct TXTChapterNavigationTests {

    @Test("navigateToChapter updates text and index")
    func navigateUpdatesText() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.navigateToChapter(1)

        #expect(vm.currentChapterIdx == 1)
        #expect(vm.currentChapterText == ch2Text)
        #expect(vm.textContent == ch2Text)
    }

    @Test("navigateToChapter sets offset to chapter start")
    func navigateSetsOffset() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.navigateToChapter(2)

        let ch1UTF16 = (ch1Text as NSString).length
        let ch2UTF16 = (ch2Text as NSString).length
        #expect(vm.currentOffsetUTF16 == ch1UTF16 + ch2UTF16)
    }

    @Test("nextChapter advances from 0 to 1")
    func nextChapterAdvances() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.nextChapter()

        #expect(vm.currentChapterIdx == 1)
        #expect(vm.currentChapterText == ch2Text)
    }

    @Test("nextChapter at last chapter is no-op")
    func nextChapterAtEnd() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.navigateToChapter(2)
        await vm.nextChapter()

        #expect(vm.currentChapterIdx == 2)
        #expect(vm.currentChapterText == ch3Text)
    }

    @Test("previousChapter goes back from 1 to 0")
    func previousChapterGoesBack() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.nextChapter()
        #expect(vm.currentChapterIdx == 1)

        await vm.previousChapter()

        #expect(vm.currentChapterIdx == 0)
        #expect(vm.currentChapterText == ch1Text)
    }

    @Test("previousChapter at first chapter is no-op")
    func previousChapterAtStart() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.previousChapter()

        #expect(vm.currentChapterIdx == 0)
        #expect(vm.currentChapterText == ch1Text)
    }

    @Test("navigateToChapter out of bounds is no-op")
    func navigateOutOfBounds() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.navigateToChapter(99)

        #expect(vm.currentChapterIdx == 0)
        #expect(vm.currentChapterText == ch1Text)
    }

    @Test("navigateToChapter with negative index is no-op")
    func navigateNegativeIndex() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.navigateToChapter(-1)

        #expect(vm.currentChapterIdx == 0)
    }

    @Test("navigateToChapter without chapter mode is no-op")
    func navigateWithoutChapterMode() async {
        // Legacy mode — no chapter index
        let text = "Legacy full text content"
        let meta = TXTFileMetadata(
            text: text,
            fileByteCount: Int64(text.utf8.count),
            detectedEncoding: "UTF-8",
            totalTextLengthUTF16: (text as NSString).length,
            totalWordCount: 4
        )
        let (vm, _, _) = await makeChapterVM(fullTextMetadata: meta)
        await vm.open(url: chapterTestURL)

        await vm.navigateToChapter(0)

        // Should be no-op — not in chapter mode
        #expect(vm.isChapterMode == false)
        #expect(vm.currentChapterIdx == 0)
    }
}

// MARK: - Fallback to Full Text

@Suite("TXTReaderViewModel - Fallback (WI-5)")
@MainActor
struct TXTChapterFallbackTests {

    @Test("falls back to full-text open when chapter-based fails")
    func fallbackToFullText() async {
        let text = "Fallback full text content for the reader."
        let meta = TXTFileMetadata(
            text: text,
            fileByteCount: Int64(text.utf8.count),
            detectedEncoding: "UTF-8",
            totalTextLengthUTF16: (text as NSString).length,
            totalWordCount: 7
        )
        let (vm, service, _) = await makeChapterVM(
            chapterOpenError: .decodingFailed("Chapter index build failed"),
            fullTextMetadata: meta
        )

        await vm.openChapterBased(url: chapterTestURL)

        // Should have fallen back to full-text mode
        #expect(vm.isChapterMode == false)
        #expect(vm.textContent == text)
        #expect(vm.errorMessage == nil)

        // Both methods should have been called
        let chapterCalls = await service.chapterOpenCallCount
        let openCalls = await service.openCallCount
        #expect(chapterCalls == 1)
        #expect(openCalls == 1)
    }

    @Test("close clears chapter state")
    func closeClearsChapterState() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        #expect(vm.isChapterMode == true)

        await vm.close()

        #expect(vm.isChapterMode == false)
        #expect(vm.chapterIndex == nil)
        #expect(vm.currentChapterText == nil)
        #expect(vm.textContent == nil)
    }
}

// MARK: - TXTFileLoader Chapter-Based

@Suite("TXTFileLoader - Chapter-Based (WI-5)")
struct TXTFileLoaderChapterTests {

    @Test("loadChapterBased returns correct initial chapter")
    func loadsCorrectInitialChapter() async throws {
        let service = MockTXTService()
        let chapterResult = makeChapterOpenResult()
        await service.setChapterOpenResult(chapterResult)

        let positionStore = MockPositionStore()

        let result = try await TXTFileLoader.loadChapterBased(
            url: chapterTestURL,
            service: service,
            positionStore: positionStore,
            bookFingerprintKey: chapterFingerprint.canonicalKey
        )

        #expect(result.initialChapterIndex == 0)
        #expect(result.restoredLocalOffsetUTF16 == 0)
        #expect(result.hadSavedPosition == false)
    }

    @Test("loadChapterBased resolves saved position to chapter")
    func resolvesSavedPosition() async throws {
        let service = MockTXTService()
        let chapterResult = makeChapterOpenResult()
        await service.setChapterOpenResult(chapterResult)

        let positionStore = MockPositionStore()
        let ch1UTF16 = (ch1Text as NSString).length
        let savedOffset = ch1UTF16 + 10 // In chapter 2

        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: chapterFingerprint,
            charOffsetUTF16: savedOffset
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: chapterFingerprint.canonicalKey,
            locator: savedLocator
        )

        let result = try await TXTFileLoader.loadChapterBased(
            url: chapterTestURL,
            service: service,
            positionStore: positionStore,
            bookFingerprintKey: chapterFingerprint.canonicalKey
        )

        #expect(result.initialChapterIndex == 1)
        #expect(result.restoredLocalOffsetUTF16 == 10)
        #expect(result.hadSavedPosition == true)
    }

    @Test("loadChapterBased with position beyond range defaults to last chapter")
    func positionBeyondRange() async throws {
        let service = MockTXTService()
        let chapterResult = makeChapterOpenResult()
        await service.setChapterOpenResult(chapterResult)

        let positionStore = MockPositionStore()
        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: chapterFingerprint,
            charOffsetUTF16: 999999
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: chapterFingerprint.canonicalKey,
            locator: savedLocator
        )

        let result = try await TXTFileLoader.loadChapterBased(
            url: chapterTestURL,
            service: service,
            positionStore: positionStore,
            bookFingerprintKey: chapterFingerprint.canonicalKey
        )

        // Should default to last chapter since offset is beyond total
        #expect(result.initialChapterIndex == 2)
        #expect(result.restoredLocalOffsetUTF16 == 0)
        #expect(result.hadSavedPosition == true)
    }

    @Test("loadChapterBased with no saved position starts at chapter 0")
    func noSavedPosition() async throws {
        let service = MockTXTService()
        let chapterResult = makeChapterOpenResult()
        await service.setChapterOpenResult(chapterResult)

        let positionStore = MockPositionStore()

        let result = try await TXTFileLoader.loadChapterBased(
            url: chapterTestURL,
            service: service,
            positionStore: positionStore,
            bookFingerprintKey: chapterFingerprint.canonicalKey
        )

        #expect(result.initialChapterIndex == 0)
        #expect(result.hadSavedPosition == false)
    }

    @Test("loadChapterBased with position load error falls back to chapter 0")
    func positionLoadError() async throws {
        let service = MockTXTService()
        let chapterResult = makeChapterOpenResult()
        await service.setChapterOpenResult(chapterResult)

        let positionStore = MockPositionStore()
        await positionStore.setLoadError(NSError(domain: "test", code: 1))

        let result = try await TXTFileLoader.loadChapterBased(
            url: chapterTestURL,
            service: service,
            positionStore: positionStore,
            bookFingerprintKey: chapterFingerprint.canonicalKey
        )

        #expect(result.initialChapterIndex == 0)
        #expect(result.hadSavedPosition == false)
    }
}

// MARK: - GH #30: Unified Chapter System

@Suite("GH #30 — Unified Chapter System")
@MainActor
struct GH30UnifiedChapterTests {

    @Test("navigateToChapterByTitle finds correct chapter")
    func titleMatchNavigation() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        let matched = await vm.navigateToChapterByTitle("Chapter 2")

        #expect(matched == true)
        #expect(vm.currentChapterIdx == 1)
        #expect(vm.currentChapterText == ch2Text)
    }

    @Test("navigateToChapterByTitle trims whitespace")
    func titleMatchWhitespace() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        let matched = await vm.navigateToChapterByTitle("  Chapter 3  \n")

        #expect(matched == true)
        #expect(vm.currentChapterIdx == 2)
    }

    @Test("navigateToChapterByTitle returns false for no match")
    func titleMatchNoMatch() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        let matched = await vm.navigateToChapterByTitle("Nonexistent")

        #expect(matched == false)
        #expect(vm.currentChapterIdx == 0)
    }

    @Test("makeLocator includes txtchapter href in chapter mode")
    func makeLocatorHref() async {
        let result = makeChapterOpenResult()
        let (vm, _, _) = await makeChapterVM(chapterResult: result)
        await vm.openChapterBased(url: chapterTestURL)

        await vm.navigateToChapter(1)
        let locator = vm.makeLocator()

        #expect(locator.href?.hasPrefix("txtchapter:1:") == true)
    }

    @Test("makeLocator has nil href in non-chapter mode")
    func makeLocatorNoHref() async {
        let meta = TXTFileMetadata(
            text: "plain text", fileByteCount: 10,
            detectedEncoding: "UTF-8", totalTextLengthUTF16: 10, totalWordCount: 2
        )
        let (vm, _, _) = await makeChapterVM(fullTextMetadata: meta)
        await vm.open(url: chapterTestURL)

        let locator = vm.makeLocator()

        #expect(locator.href == nil)
    }

    @Test("content loader slices full text by UTF-16 offsets")
    func contentLoaderSlicing() async throws {
        let allText = ch1Text + ch2Text + ch3Text
        let allData = Data(allText.utf8)
        let ch1UTF16 = (ch1Text as NSString).length
        let ch2UTF16 = (ch2Text as NSString).length

        let loader = TXTChapterContentLoader(fileData: allData, encoding: .utf8)
        let ch = TXTChapter(
            index: 1, title: "Chapter 2",
            startByte: 0, endByte: Int64(allData.count),
            globalStartUTF16: ch1UTF16, textLengthUTF16: ch2UTF16
        )

        let text = try await loader.loadChapter(ch)

        #expect(text == ch2Text)
    }

    @Test("position restore via href parses chapter index directly")
    func hrefPositionRestore() async {
        let result = makeChapterOpenResult()
        let (vm, _, positionStore) = await makeChapterVM(chapterResult: result)

        // Save a position with href encoding
        let locator = Locator(
            bookFingerprint: chapterFingerprint,
            href: "txtchapter:2:5", progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: 99999, // Wrong global offset — should be ignored
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await positionStore.seed(
            bookFingerprintKey: chapterFingerprint.canonicalKey,
            locator: locator
        )

        await vm.openChapterBased(url: chapterTestURL)

        // Should use href (chapter 2, offset 5), not the wrong charOffsetUTF16
        #expect(vm.currentChapterIdx == 2)
        #expect(vm.currentChapterText == ch3Text)
    }

    @Test("position restore falls back to global offset for legacy locators")
    func legacyPositionRestore() async {
        let result = makeChapterOpenResult()
        let ch1UTF16 = (ch1Text as NSString).length
        let (vm, _, positionStore) = await makeChapterVM(chapterResult: result)

        // Save a legacy position without href
        guard let locator = LocatorFactory.txtPosition(
            fingerprint: chapterFingerprint,
            charOffsetUTF16: ch1UTF16 + 5
        ) else {
            Issue.record("Failed to create locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: chapterFingerprint.canonicalKey,
            locator: locator
        )

        await vm.openChapterBased(url: chapterTestURL)

        // Should fall back to global offset → chapter 1
        #expect(vm.currentChapterIdx == 1)
    }
}
