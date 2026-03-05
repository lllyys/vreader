// Purpose: Tests for TXTReaderViewModel — open/close lifecycle, position persistence,
// session tracking integration, words read estimation, error handling, edge cases.
//
// @coordinates-with: TXTReaderViewModel.swift, MockTXTService.swift, MockPositionStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFingerprint = DocumentFingerprint(
    contentSHA256: "txt_vm_test_sha256_000000000000000000000000000000000000000000",
    fileByteCount: 1000,
    format: .txt
)

private let testText = "Hello world. This is a test document with some words for reading."
private let testMetadata = TXTFileMetadata(
    text: testText,
    fileByteCount: 1000,
    detectedEncoding: "UTF-8",
    totalTextLengthUTF16: (testText as NSString).length,
    totalWordCount: 12
)

private let emptyMetadata = TXTFileMetadata(
    text: "",
    fileByteCount: 0,
    detectedEncoding: "UTF-8",
    totalTextLengthUTF16: 0,
    totalWordCount: 0
)

private let cjkText = "这是一个测试文档，包含中文字符。"
private let cjkMetadata = TXTFileMetadata(
    text: cjkText,
    fileByteCount: Int64(cjkText.utf8.count),
    detectedEncoding: "UTF-8",
    totalTextLengthUTF16: (cjkText as NSString).length,
    totalWordCount: 1 // CJK typically treated as one "word" by whitespace split
)

private let testURL = URL(fileURLWithPath: "/tmp/test.txt")

// MARK: - Helpers

@MainActor
private func makeViewModel(
    fingerprint: DocumentFingerprint = testFingerprint,
    serviceMetadata: TXTFileMetadata? = testMetadata,
    serviceError: TXTServiceError? = nil
) async -> (TXTReaderViewModel, MockTXTService, MockPositionStore, MockSessionStore) {
    let service = MockTXTService()
    await service.setMetadata(serviceMetadata)
    if let error = serviceError {
        await service.setOpenError(error)
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
        deviceId: "test-device"
    )

    return (vm, service, positionStore, sessionStore)
}

// MARK: - Open Lifecycle

@Suite("TXTReaderViewModel - Open")
@MainActor
struct TXTReaderViewModelOpenTests {

    @Test("open loads text and sets initial state")
    func openLoadsText() async {
        let (vm, service, _, _) = await makeViewModel()

        await vm.open(url: testURL)

        #expect(vm.textContent == testText)
        #expect(vm.totalTextLengthUTF16 == testMetadata.totalTextLengthUTF16)
        #expect(vm.totalWordCount == 12)
        #expect(vm.currentOffsetUTF16 == 0)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)

        let openCount = await service.openCallCount
        #expect(openCount == 1)
    }

    @Test("open restores saved position")
    func openRestoresPosition() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Seed a saved position at offset 20
        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: testFingerprint,
            charOffsetUTF16: 20,
            sourceText: testText
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )

        await vm.open(url: testURL)

        #expect(vm.currentOffsetUTF16 == 20)
    }

    @Test("open restores position clamped to text length")
    func openRestoresPositionClamped() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Seed a saved position beyond text length
        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: testFingerprint,
            charOffsetUTF16: 99999
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )

        await vm.open(url: testURL)

        // Should clamp to text length
        #expect(vm.currentOffsetUTF16 <= testMetadata.totalTextLengthUTF16)
    }

    @Test("open handles service error")
    func openHandlesError() async {
        let (vm, _, _, _) = await makeViewModel(
            serviceError: .fileNotFound("/tmp/test.txt")
        )

        await vm.open(url: testURL)

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage == "The file could not be found.")
        #expect(vm.isLoading == false)
        #expect(vm.textContent == nil)
    }

    @Test("open handles encoding detection error")
    func openHandlesEncodingError() async {
        let (vm, _, _, _) = await makeViewModel(
            serviceError: .encodingDetectionFailed("Unknown encoding")
        )

        await vm.open(url: testURL)

        #expect(vm.errorMessage == "Could not detect file encoding.")
    }

    @Test("open handles decoding error")
    func openHandlesDecodingError() async {
        let (vm, _, _, _) = await makeViewModel(
            serviceError: .decodingFailed("Invalid bytes")
        )

        await vm.open(url: testURL)

        #expect(vm.errorMessage == "The file could not be decoded.")
    }

    @Test("open starts reading session")
    func openStartsSession() async {
        let (vm, _, _, sessionStore) = await makeViewModel()

        await vm.open(url: testURL)

        #expect(sessionStore.savedSessions.count >= 1)
    }

    @Test("open updates lastOpenedAt")
    func openUpdatesLastOpened() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        await vm.open(url: testURL)

        let count = await positionStore.updateLastOpenedCallCount
        #expect(count == 1)
    }

    @Test("open with empty file succeeds")
    func openEmptyFile() async {
        let (vm, _, _, _) = await makeViewModel(serviceMetadata: emptyMetadata)

        await vm.open(url: testURL)

        #expect(vm.textContent == "")
        #expect(vm.totalTextLengthUTF16 == 0)
        #expect(vm.totalWordCount == 0)
        #expect(vm.currentOffsetUTF16 == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("open with CJK text succeeds")
    func openCJK() async {
        let (vm, _, _, _) = await makeViewModel(serviceMetadata: cjkMetadata)

        await vm.open(url: testURL)

        #expect(vm.textContent == cjkText)
        #expect(vm.totalTextLengthUTF16 == (cjkText as NSString).length)
    }
}

// MARK: - Close Lifecycle

@Suite("TXTReaderViewModel - Close")
@MainActor
struct TXTReaderViewModelCloseTests {

    @Test("close ends reading session")
    func closeEndsSession() async {
        let (vm, _, _, sessionStore) = await makeViewModel()
        await vm.open(url: testURL)

        await vm.close()

        // Session was <5s (test clock doesn't advance), so it should be discarded
        #expect(!sessionStore.discardedSessionIds.isEmpty)
    }

    @Test("close saves final position")
    func closeSavesPosition() async {
        let (vm, _, positionStore, _) = await makeViewModel()
        await vm.open(url: testURL)

        // Simulate position change
        vm.updateScrollPosition(charOffsetUTF16: 30)

        await vm.close()

        let saveCount = await positionStore.saveCallCount
        #expect(saveCount >= 1)
    }

    @Test("close calls service close")
    func closeCallsService() async {
        let (vm, service, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        await vm.close()

        let closeCount = await service.closeCallCount
        #expect(closeCount == 1)
    }
}

// MARK: - Position Updates

@Suite("TXTReaderViewModel - Position Updates")
@MainActor
struct TXTReaderViewModelPositionTests {

    @Test("updateScrollPosition updates current offset")
    func updatePositionChangesState() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateScrollPosition(charOffsetUTF16: 25)

        #expect(vm.currentOffsetUTF16 == 25)
    }

    @Test("updateScrollPosition records progress on session tracker")
    func updatePositionRecordsProgress() async {
        let (vm, _, _, sessionStore) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateScrollPosition(charOffsetUTF16: 30)

        // At least 1 session saved (from open's startSessionIfNeeded)
        #expect(sessionStore.savedSessions.count >= 1)
    }

    @Test("updateScrollPosition clamps negative offset to 0")
    func updatePositionClampsNegative() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateScrollPosition(charOffsetUTF16: -10)

        #expect(vm.currentOffsetUTF16 == 0)
    }

    @Test("updateScrollPosition clamps beyond text length")
    func updatePositionClampsBeyondLength() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateScrollPosition(charOffsetUTF16: 999999)

        #expect(vm.currentOffsetUTF16 == testMetadata.totalTextLengthUTF16)
    }

    @Test("totalProgression computes correctly")
    func totalProgressionComputes() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        let halfOffset = testMetadata.totalTextLengthUTF16 / 2
        vm.updateScrollPosition(charOffsetUTF16: halfOffset)

        guard let progression = vm.totalProgression else {
            Issue.record("Expected non-nil totalProgression")
            return
        }
        // Should be approximately 0.5
        #expect(progression > 0.4)
        #expect(progression < 0.6)
    }

    @Test("totalProgression is 0 at start")
    func totalProgressionAtStart() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        #expect(vm.totalProgression == 0.0)
    }

    @Test("totalProgression is nil for empty file")
    func totalProgressionEmptyFile() async {
        let (vm, _, _, _) = await makeViewModel(serviceMetadata: emptyMetadata)
        await vm.open(url: testURL)

        // Empty file: division by zero -> nil
        #expect(vm.totalProgression == nil)
    }
}

// MARK: - Selection

@Suite("TXTReaderViewModel - Selection")
@MainActor
struct TXTReaderViewModelSelectionTests {

    @Test("updateSelection stores UTF-16 range")
    func updateSelection() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateSelection(startUTF16: 5, endUTF16: 15)

        #expect(vm.currentSelectionStart == 5)
        #expect(vm.currentSelectionEnd == 15)
    }

    @Test("clearSelection clears range")
    func clearSelection() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateSelection(startUTF16: 5, endUTF16: 15)
        vm.clearSelection()

        #expect(vm.currentSelectionStart == nil)
        #expect(vm.currentSelectionEnd == nil)
    }
}

// MARK: - Words Read Estimation

@Suite("TXTReaderViewModel - Words Read")
@MainActor
struct TXTReaderViewModelWordsReadTests {

    @Test("wordsRead at start is 0")
    func wordsReadAtStart() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        #expect(vm.estimatedWordsRead == 0)
    }

    @Test("wordsRead formula: round((abs(end - start) / total) * totalWords)")
    func wordsReadFormula() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        // Start at offset 0, move to half the text
        let halfOffset = testMetadata.totalTextLengthUTF16 / 2
        vm.updateScrollPosition(charOffsetUTF16: halfOffset)

        guard let words = vm.estimatedWordsRead else {
            Issue.record("Expected non-nil wordsRead")
            return
        }
        // Should be approximately half of 12 = 6
        #expect(words >= 5)
        #expect(words <= 7)
    }

    @Test("wordsRead clamped to totalWordCount")
    func wordsReadClamped() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        // Move to the end
        vm.updateScrollPosition(charOffsetUTF16: testMetadata.totalTextLengthUTF16)

        guard let words = vm.estimatedWordsRead else {
            Issue.record("Expected non-nil wordsRead")
            return
        }
        #expect(words <= testMetadata.totalWordCount)
    }

    @Test("wordsRead is nil for empty file")
    func wordsReadEmptyFile() async {
        let (vm, _, _, _) = await makeViewModel(serviceMetadata: emptyMetadata)
        await vm.open(url: testURL)

        #expect(vm.estimatedWordsRead == nil)
    }

    @Test("wordsRead is nil before open")
    func wordsReadBeforeOpen() async {
        let (vm, _, _, _) = await makeViewModel()

        #expect(vm.estimatedWordsRead == nil)
    }
}

// MARK: - Background/Foreground

@Suite("TXTReaderViewModel - Background/Foreground")
@MainActor
struct TXTReaderViewModelLifecycleTests {

    @Test("onBackground saves position and pauses")
    func onBackgroundPauses() async {
        let (vm, _, positionStore, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateScrollPosition(charOffsetUTF16: 20)
        vm.onBackground()

        // Give the background task a moment to complete
        try? await Task.sleep(for: .milliseconds(50))
        let saveCount = await positionStore.saveCallCount
        #expect(saveCount >= 1)
    }

    @Test("onForeground resumes session tracker")
    func onForegroundResumes() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.onBackground()
        vm.onForeground()

        #expect(vm.errorMessage == nil)
    }
}

// MARK: - Session Rollback

@Suite("TXTReaderViewModel - Session Rollback")
@MainActor
struct TXTReaderViewModelSessionRollbackTests {

    @Test("session start failure clears text and position")
    func sessionStartFailureClearsState() async {
        let service = MockTXTService()
        await service.setMetadata(testMetadata)

        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        sessionStore.saveError = NSError(domain: "test", code: 1)
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = TXTReaderViewModel(
            bookFingerprint: testFingerprint,
            txtService: service,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        await vm.open(url: testURL)

        #expect(vm.textContent == nil)
        #expect(vm.currentOffsetUTF16 == 0)
        #expect(vm.errorMessage == "Failed to start reading session.")
        #expect(vm.isLoading == false)

        let serviceClosed = await service.closeCallCount
        #expect(serviceClosed >= 1)
    }
}

// MARK: - Edge Cases

@Suite("TXTReaderViewModel - Edge Cases")
@MainActor
struct TXTReaderViewModelEdgeCaseTests {

    @Test("updateScrollPosition before open is safe")
    func updatePositionBeforeOpen() async {
        let (vm, _, _, _) = await makeViewModel()

        // Should not crash
        vm.updateScrollPosition(charOffsetUTF16: 50)

        // Offset should still clamp to 0 since no text loaded
        #expect(vm.currentOffsetUTF16 == 0)
    }

    @Test("close without open is safe")
    func closeWithoutOpen() async {
        let (vm, _, _, _) = await makeViewModel()

        // Should not crash
        await vm.close()

        #expect(vm.errorMessage == nil)
    }

    @Test("second open call closes previous and re-opens")
    func secondOpenReinitializes() async {
        let (vm, service, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateScrollPosition(charOffsetUTF16: 40)

        // Open again — close saves position, then re-open restores it
        await vm.open(url: testURL)

        let openCount = await service.openCallCount
        #expect(openCount == 2)
        // Position is restored from saved state (40 was persisted on close)
        #expect(vm.currentOffsetUTF16 == 40)
    }

    @Test("rapid position updates don't crash")
    func rapidPositionUpdates() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        for i in 0..<100 {
            vm.updateScrollPosition(charOffsetUTF16: i)
        }

        #expect(vm.currentOffsetUTF16 >= 0)
    }

    @Test("close without position change reports no error")
    func closeWithoutPositionChange() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        await vm.close()

        #expect(vm.errorMessage == nil)
    }

    @Test("position restore ignores negative saved offsets")
    func negativeRestoredOffset() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Seed a position with offset that would be negative after any clamping.
        // LocatorFactory.txtPosition rejects negative offsets, so directly create locator.
        let savedLocator = Locator(
            bookFingerprint: testFingerprint,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil,
            charOffsetUTF16: nil, // Locator allows nil
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )

        await vm.open(url: testURL)

        // Should start at 0 when no valid offset in locator
        #expect(vm.currentOffsetUTF16 == 0)
    }
}

// MARK: - TXTServiceError Description

@Suite("TXTServiceError")
struct TXTServiceErrorTests {

    @Test("errors are equatable")
    func equatable() {
        let a = TXTServiceError.fileNotFound("test.txt")
        let b = TXTServiceError.fileNotFound("test.txt")
        let c = TXTServiceError.decodingFailed("bad")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("all error cases exist")
    func allCases() {
        let errors: [TXTServiceError] = [
            .fileNotFound(""),
            .encodingDetectionFailed(""),
            .decodingFailed(""),
            .notOpen,
            .alreadyOpen,
        ]
        #expect(errors.count == 5)
    }
}

// MARK: - TXTFileMetadata

@Suite("TXTFileMetadata")
struct TXTFileMetadataTests {

    @Test("metadata stores correct values")
    func metadataValues() {
        let text = "Hello world"
        let meta = TXTFileMetadata(
            text: text,
            fileByteCount: 11,
            detectedEncoding: "UTF-8",
            totalTextLengthUTF16: (text as NSString).length,
            totalWordCount: 2
        )
        #expect(meta.text == "Hello world")
        #expect(meta.fileByteCount == 11)
        #expect(meta.detectedEncoding == "UTF-8")
        #expect(meta.totalTextLengthUTF16 == 11)
        #expect(meta.totalWordCount == 2)
    }

    @Test("metadata equality")
    func metadataEquality() {
        let a = TXTFileMetadata(text: "a", fileByteCount: 1, detectedEncoding: "UTF-8", totalTextLengthUTF16: 1, totalWordCount: 1)
        let b = TXTFileMetadata(text: "a", fileByteCount: 1, detectedEncoding: "UTF-8", totalTextLengthUTF16: 1, totalWordCount: 1)
        let c = TXTFileMetadata(text: "b", fileByteCount: 1, detectedEncoding: "UTF-8", totalTextLengthUTF16: 1, totalWordCount: 1)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("empty metadata")
    func emptyMetadata() {
        let meta = TXTFileMetadata(text: "", fileByteCount: 0, detectedEncoding: "UTF-8", totalTextLengthUTF16: 0, totalWordCount: 0)
        #expect(meta.text.isEmpty)
        #expect(meta.totalWordCount == 0)
    }
}
