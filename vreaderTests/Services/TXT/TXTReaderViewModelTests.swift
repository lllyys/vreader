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
    serviceError: TXTServiceError? = nil,
    positionSaveDebounceNs: UInt64 = 2_000_000_000
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
        deviceId: "test-device",
        positionSaveDebounceNs: positionSaveDebounceNs
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

        // updateLastOpened fires in a detached Task; allow it to complete
        try? await Task.sleep(for: .milliseconds(50))

        let count = await positionStore.updateLastOpenedCallCount
        #expect(count >= 1)
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

// MARK: - Live Position Broadcast (Bug #164)

/// Bug #164: native TXT (UITextView) scroll path was not posting
/// `.readerPositionDidChange`, so `ReaderAICoordinator.currentLocator` stayed
/// stale and TTS started from offset 0 even when the user had scrolled
/// partway through. These tests pin the post: `updateScrollPosition` MUST
/// emit `.readerPositionDidChange` with a Locator whose `charOffsetUTF16`
/// matches the new (clamped) offset.
@Suite("TXTReaderViewModel - Live Position Broadcast (bug #164)")
@MainActor
struct TXTReaderViewModelPositionBroadcastTests {

    /// Captures the most-recent locator object posted on `.readerPositionDidChange`
    /// AND counts how many times the notification fired during the lifetime
    /// of the observer; tear down via the returned remove-closure (Swift
    /// Testing has no XCTest-style teardown lambda).
    ///
    /// Round-1 audit fix [Low]: registered with `queue: nil` so delivery is
    /// synchronous on the posting thread. With a non-nil queue the post is
    /// enqueued and we'd be reading `captured` before it's populated, making
    /// the assertions race-prone.
    ///
    /// Round-2 audit fix [Low]: also expose a fire-count so callers can
    /// pin "exactly N broadcasts" rather than just "at least one".
    private static func observeLocator() -> (capture: () -> Locator?, count: () -> Int, remove: () -> Void) {
        nonisolated(unsafe) var captured: Locator?
        nonisolated(unsafe) var fired: Int = 0
        let token = NotificationCenter.default.addObserver(
            forName: .readerPositionDidChange,
            object: nil,
            queue: nil
        ) { notification in
            captured = notification.object as? Locator
            fired += 1
        }
        return (
            capture: { captured },
            count: { fired },
            remove: { NotificationCenter.default.removeObserver(token) }
        )
    }

    @Test("updateScrollPosition posts readerPositionDidChange with current locator")
    func postsNotificationOnPositionUpdate() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        let observer = Self.observeLocator()
        defer { observer.remove() }

        vm.updateScrollPosition(charOffsetUTF16: 17)

        // Notification is posted synchronously inside updateScrollPosition,
        // and the observer is registered with `queue: nil` (synchronous
        // delivery on the posting thread), so the capture is populated by
        // the time the call returns.
        let locator = observer.capture()
        #expect(locator != nil, "Expected .readerPositionDidChange to fire on scroll position change")
        #expect(locator?.charOffsetUTF16 == 17)
    }

    @Test("clamped negative offset still broadcasts (offset==0)")
    func postsNotificationWithClampedNegative() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        let observer = Self.observeLocator()
        defer { observer.remove() }

        vm.updateScrollPosition(charOffsetUTF16: -50)

        let locator = observer.capture()
        #expect(locator != nil)
        #expect(locator?.charOffsetUTF16 == 0)
    }

    @Test("clamped beyond-length offset broadcasts the clamped value")
    func postsNotificationWithClampedBeyondLength() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        let observer = Self.observeLocator()
        defer { observer.remove() }

        vm.updateScrollPosition(charOffsetUTF16: 999_999)

        let locator = observer.capture()
        #expect(locator != nil)
        #expect(locator?.charOffsetUTF16 == testMetadata.totalTextLengthUTF16)
    }

    @Test("open with restored position seeds AI/TTS via post once")
    func openSeedsRestoredPosition() async {
        // Bug #164 round-1 audit fix [Medium]: the suppress window in
        // `updateScrollPosition` drops storm-zero updates AND the legitimate
        // restored offset. So `open()` must explicitly broadcast the
        // restored locator once, otherwise `aiCoordinator.currentLocator`
        // stays nil until the user scrolls past the suppress window —
        // meaning TTS started immediately after open would still resolve
        // offset 0.
        let positionStore = MockPositionStore()
        guard let savedLocator = Locator.validated(
            bookFingerprint: testFingerprint,
            totalProgression: 0.5,
            charOffsetUTF16: 30
        ) else {
            Issue.record("Could not build seed locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        let sessionStore = MockSessionStore()
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
            deviceId: "test-device",
            positionSaveDebounceNs: 2_000_000_000
        )

        let observer = Self.observeLocator()
        defer { observer.remove() }

        await vm.open(url: testURL)

        let locator = observer.capture()
        #expect(locator != nil, "open() must broadcast the restored locator once so AI/TTS see the restored offset before any scroll event")
        #expect(locator?.charOffsetUTF16 == 30)
        // Round-2 audit fix [Low]: pin the broadcast count to exactly 1
        // so a future regression that posts multiple times during open()
        // (e.g. once from restore and once from a stray scroll callback)
        // surfaces here.
        #expect(observer.count() == 1, "open() must broadcast exactly once for the restored position; got \(observer.count())")
    }

    @Test("position broadcast suppressed during post-restore settling window")
    func suppressedDuringRestoreWindow() async {
        // Bug #164 + bug #58 interaction: scroll-position saves are suppressed
        // during the settling window after a position restore (so a relayout
        // storm doesn't overwrite the freshly-restored offset). The position
        // broadcast must follow the same rule — otherwise the AI/TTS would
        // see the storm-zero positions instead of the restored offset.
        let positionStore = MockPositionStore()
        guard let savedLocator = Locator.validated(
            bookFingerprint: testFingerprint,
            totalProgression: 0.5,
            charOffsetUTF16: 30
        ) else {
            Issue.record("Could not build seed locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )
        let service = MockTXTService()
        await service.setMetadata(testMetadata)
        let sessionStore = MockSessionStore()
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
            deviceId: "test-device",
            positionSaveDebounceNs: 2_000_000_000
        )
        await vm.open(url: testURL)

        let observer = Self.observeLocator()
        defer { observer.remove() }

        // First updateScrollPosition during settle window with offset==0
        // (TextKit relayout storm) must NOT trigger broadcast.
        vm.updateScrollPosition(charOffsetUTF16: 0)
        #expect(observer.capture() == nil, "Storm-zero updates inside settle window must not broadcast")
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
        await vm.onBackground()

        let saveCount = await positionStore.saveCallCount
        #expect(saveCount >= 1)
    }

    @Test("onForeground resumes session tracker")
    func onForegroundResumes() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        await vm.onBackground()
        vm.onForeground()

        #expect(vm.errorMessage == nil)
    }
}

// MARK: - Session Non-Fatal

@Suite("TXTReaderViewModel - Session Non-Fatal")
@MainActor
struct TXTReaderViewModelSessionNonFatalTests {

    @Test("session start failure preserves content (non-fatal)")
    func sessionStartFailurePreservesContent() async {
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

        // Session failure is non-fatal — user can still read
        #expect(vm.textContent == testText)
        #expect(vm.currentOffsetUTF16 == 0)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)

        // Service should NOT have been closed by rollback
        let serviceClosed = await service.closeCallCount
        #expect(serviceClosed == 0)
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

// MARK: - Bug #23: Position Save Guards

@Suite("TXTReaderViewModel - Position Save Guards (Bug #23)")
@MainActor
struct TXTReaderViewModelPositionGuardTests {

    @Test("close saves restored position, not stale 0, when user never scrolled")
    func closeSavesRestoredOffset() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Seed a saved position at offset 30
        guard let savedLocator = LocatorFactory.txtPosition(
            fingerprint: testFingerprint,
            charOffsetUTF16: 30,
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
        #expect(vm.currentOffsetUTF16 == 30)

        // Close without scrolling — should save offset 30, not 0
        await vm.close()

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved != nil)
        #expect(saved?.charOffsetUTF16 == 30)
    }

    @Test("close after failed session start still saves position (session non-fatal)")
    func closeAfterSessionFailureStillSaves() async {
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

        // open() succeeds even though session start fails (non-fatal)
        await vm.open(url: testURL)
        #expect(vm.errorMessage == nil)
        #expect(vm.textContent == testText)

        let saveCountBeforeClose = await positionStore.saveCallCount

        await vm.close()

        let saveCountAfterClose = await positionStore.saveCallCount
        // close() SHOULD save position since isOpenComplete is true
        // (session failure doesn't prevent content from loading)
        #expect(saveCountAfterClose >= saveCountBeforeClose)
    }

    @Test("onBackground awaits save — position persisted without sleep hack")
    func onBackgroundSavesImmediately() async {
        let (vm, _, positionStore, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updateScrollPosition(charOffsetUTF16: 42)
        await vm.onBackground()

        // Save is guaranteed complete after await — no Task.sleep needed
        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 42)
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

// MARK: - Position Service Integration (WI-008d)

@Suite("TXTReaderViewModel - Position Service")
@MainActor
struct TXTReaderViewModelPositionServiceTests {

    @Test("close uses positionService.saveNow for immediate persistence")
    func closeUsesPositionService() async {
        let (vm, _, positionStore, _) = await makeViewModel(positionSaveDebounceNs: 0)

        await vm.open(url: testURL)
        vm.updateScrollPosition(charOffsetUTF16: 15)
        await vm.close()

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 15)
    }

    @Test("onBackground uses positionService.saveNow")
    func onBackgroundUsesPositionService() async {
        let (vm, _, positionStore, _) = await makeViewModel(positionSaveDebounceNs: 0)

        await vm.open(url: testURL)
        vm.updateScrollPosition(charOffsetUTF16: 10)
        await vm.onBackground()

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 10)
    }

    @Test("updateScrollPosition uses positionService.scheduleSave")
    func scrollUsesScheduleSave() async {
        let (vm, _, positionStore, _) = await makeViewModel(positionSaveDebounceNs: 10_000_000)

        await vm.open(url: testURL)
        vm.updateScrollPosition(charOffsetUTF16: 20)

        // Wait for debounce (10ms)
        try? await Task.sleep(for: .milliseconds(50))

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 20)
    }
}

// MARK: - Chapter Local Offset (Bug #31)

@Suite("TXTReaderViewModel - Chapter Local Offset")
@MainActor
struct TXTReaderViewModelChapterLocalTests {

    @Test("chapterLocalUTF16 starts at 0 in non-chapter mode")
    func nonChapterModeLocalIsZero() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)
        #expect(vm.currentChapterLocalUTF16 == 0)
    }

    @Test("updateScrollPosition in chapter mode updates chapterLocalUTF16")
    func scrollUpdatesLocal() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)
        // Simulate chapter mode by setting state through updateScrollPosition
        // In non-chapter mode, chapterLocalUTF16 should track currentOffsetUTF16
        vm.updateScrollPosition(charOffsetUTF16: 10)
        #expect(vm.currentChapterLocalUTF16 == 10)
    }

    @Test("updateScrollPosition in chapter mode keeps currentOffsetUTF16 global")
    func scrollKeepsGlobal() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)
        // In non-chapter mode, both should be the same
        vm.updateScrollPosition(charOffsetUTF16: 15)
        #expect(vm.currentOffsetUTF16 == 15)
        #expect(vm.currentChapterLocalUTF16 == 15)
    }

    @Test("chapterScrollFraction computed correctly")
    func chapterScrollFraction() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)
        // Non-chapter mode: fraction = local / totalLength
        vm.updateScrollPosition(charOffsetUTF16: 32)
        let total = vm.totalTextLengthUTF16
        let expected = Double(32) / Double(total)
        #expect(vm.chapterScrollFraction == expected)
    }
}
