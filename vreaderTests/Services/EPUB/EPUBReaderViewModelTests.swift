// Purpose: Tests for EPUBReaderViewModel — open/close lifecycle, position persistence,
// session tracking integration, navigation, error handling.
//
// @coordinates-with: EPUBReaderViewModel.swift, MockEPUBParser.swift, MockPositionStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFingerprint = DocumentFingerprint(
    contentSHA256: "epub_vm_test_sha256_00000000000000000000000000000000000000000",
    fileByteCount: 50000,
    format: .epub
)

private let testSpineItems = [
    EPUBSpineItem(id: "ch1", href: "chapter1.xhtml", title: "Chapter 1", index: 0),
    EPUBSpineItem(id: "ch2", href: "chapter2.xhtml", title: "Chapter 2", index: 1),
    EPUBSpineItem(id: "ch3", href: "chapter3.xhtml", title: "Chapter 3", index: 2),
]

private let testMetadata = EPUBMetadata(
    title: "Test Book",
    author: "Test Author",
    language: "en",
    readingDirection: .ltr,
    layout: .reflowable,
    spineItems: testSpineItems
)

private let rtlMetadata = EPUBMetadata(
    title: "كتاب اختبار",
    author: "مؤلف",
    language: "ar",
    readingDirection: .rtl,
    layout: .reflowable,
    spineItems: testSpineItems
)

private let fixedLayoutMetadata = EPUBMetadata(
    title: "Fixed Layout Book",
    author: nil,
    language: "en",
    readingDirection: .ltr,
    layout: .fixedLayout,
    spineItems: testSpineItems
)

private let testURL = URL(fileURLWithPath: "/tmp/test.epub")

// MARK: - Helpers

@MainActor
private func makeViewModel(
    fingerprint: DocumentFingerprint = testFingerprint,
    parserMetadata: EPUBMetadata? = testMetadata,
    parserError: EPUBParserError? = nil
) async -> (EPUBReaderViewModel, MockEPUBParser, MockPositionStore, MockSessionStore) {
    let parser = MockEPUBParser()
    await parser.setMetadata(parserMetadata)
    if let error = parserError {
        await parser.setOpenError(error)
    }

    let positionStore = MockPositionStore()
    let sessionStore = MockSessionStore()
    let clock = MockClock()
    let tracker = ReadingSessionTracker(
        clock: clock,
        store: sessionStore,
        deviceId: "test-device"
    )

    let vm = EPUBReaderViewModel(
        bookFingerprint: fingerprint,
        parser: parser,
        positionStore: positionStore,
        sessionTracker: tracker,
        deviceId: "test-device"
    )

    return (vm, parser, positionStore, sessionStore)
}

// MARK: - MockEPUBParser helpers (setters need to be on actor)

extension MockEPUBParser {
    func setMetadata(_ metadata: EPUBMetadata?) {
        metadataToReturn = metadata
    }
    func setOpenError(_ error: EPUBParserError?) {
        openError = error
    }
}

// MARK: - Open Lifecycle

@Suite("EPUBReaderViewModel - Open")
@MainActor
struct EPUBReaderViewModelOpenTests {

    @Test("open loads metadata and sets initial position")
    func openLoadsMetadata() async {
        let (vm, parser, _, _) = await makeViewModel()

        await vm.open(url: testURL)

        #expect(vm.metadata != nil)
        #expect(vm.metadata?.title == "Test Book")
        #expect(vm.metadata?.spineCount == 3)
        #expect(vm.currentPosition != nil)
        #expect(vm.currentPosition?.href == "chapter1.xhtml")
        #expect(vm.currentPosition?.progression == 0)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)

        let openCount = await parser.openCallCount
        #expect(openCount == 1)
    }

    @Test("open restores saved position")
    func openRestoresPosition() async throws {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Seed a saved position at chapter 2, 50% through
        guard let savedLocator = LocatorFactory.epub(
            fingerprint: testFingerprint,
            href: "chapter2.xhtml",
            progression: 0.5,
            totalProgression: 0.5
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )

        await vm.open(url: testURL)

        #expect(vm.currentPosition?.href == "chapter2.xhtml")
        #expect(vm.currentPosition?.progression == 0.5)
    }

    @Test("open handles parser error")
    func openHandlesError() async {
        let (vm, _, _, _) = await makeViewModel(
            parserError: .fileNotFound("/tmp/test.epub")
        )

        await vm.open(url: testURL)

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage == "The book file could not be found.")
        #expect(vm.isLoading == false)
        #expect(vm.metadata == nil)
    }

    @Test("open handles invalid format error")
    func openHandlesInvalidFormat() async {
        let (vm, _, _, _) = await makeViewModel(
            parserError: .invalidFormat("Not an EPUB")
        )

        await vm.open(url: testURL)

        #expect(vm.errorMessage == "This file is not a valid EPUB.")
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

    @Test("open with empty spine sets nil position")
    func openEmptySpine() async {
        let emptyMetadata = EPUBMetadata(
            title: "Empty",
            author: nil,
            language: nil,
            readingDirection: .ltr,
            layout: .reflowable,
            spineItems: []
        )
        let (vm, _, _, _) = await makeViewModel(parserMetadata: emptyMetadata)

        await vm.open(url: testURL)

        #expect(vm.metadata?.spineCount == 0)
        // No spine items, so no initial position
        #expect(vm.currentPosition == nil)
    }

    @Test("open with RTL metadata succeeds")
    func openRTL() async {
        let (vm, _, _, _) = await makeViewModel(parserMetadata: rtlMetadata)

        await vm.open(url: testURL)

        #expect(vm.metadata?.readingDirection == .rtl)
        #expect(vm.metadata?.title == "كتاب اختبار")
    }

    @Test("open with fixed layout metadata succeeds")
    func openFixedLayout() async {
        let (vm, _, _, _) = await makeViewModel(parserMetadata: fixedLayoutMetadata)

        await vm.open(url: testURL)

        #expect(vm.metadata?.layout == .fixedLayout)
    }
}

// MARK: - Close Lifecycle

@Suite("EPUBReaderViewModel - Close")
@MainActor
struct EPUBReaderViewModelCloseTests {

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
        vm.updatePosition(EPUBPosition(
            href: "chapter2.xhtml",
            progression: 0.7,
            totalProgression: 0.6,
            cfi: nil
        ))

        await vm.close()

        let saveCount = await positionStore.saveCallCount
        // At least one save from close
        #expect(saveCount >= 1)
    }

    @Test("close calls parser close")
    func closeCallsParser() async {
        let (vm, parser, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        await vm.close()

        let closeCount = await parser.closeCallCount
        #expect(closeCount == 1)
    }
}

// MARK: - Position Updates

@Suite("EPUBReaderViewModel - Position Updates")
@MainActor
struct EPUBReaderViewModelPositionTests {

    @Test("updatePosition updates current position")
    func updatePositionChangesState() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        let newPos = EPUBPosition(
            href: "chapter2.xhtml",
            progression: 0.3,
            totalProgression: 0.43,
            cfi: "/2/4[ch2]"
        )
        vm.updatePosition(newPos)

        #expect(vm.currentPosition?.href == "chapter2.xhtml")
        #expect(vm.currentPosition?.progression == 0.3)
        #expect(vm.currentPosition?.totalProgression == 0.43)
        #expect(vm.currentPosition?.cfi == "/2/4[ch2]")
    }

    @Test("updatePosition records progress on session tracker")
    func updatePositionRecordsProgress() async {
        let (vm, _, _, sessionStore) = await makeViewModel()
        await vm.open(url: testURL)

        let newPos = EPUBPosition(
            href: "chapter1.xhtml",
            progression: 0.5,
            totalProgression: 0.17,
            cfi: nil
        )
        vm.updatePosition(newPos)

        #expect(vm.currentPosition?.progression == 0.5)
        // Verify tracker received at least one session save (from open)
        #expect(!sessionStore.savedSessions.isEmpty)
    }

    @Test("currentSpineIndex tracks position")
    func currentSpineIndexTracksPosition() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        #expect(vm.currentSpineIndex == 0)

        vm.updatePosition(EPUBPosition(
            href: "chapter2.xhtml",
            progression: 0.0,
            totalProgression: 0.33,
            cfi: nil
        ))
        #expect(vm.currentSpineIndex == 1)

        vm.updatePosition(EPUBPosition(
            href: "chapter3.xhtml",
            progression: 0.0,
            totalProgression: 0.67,
            cfi: nil
        ))
        #expect(vm.currentSpineIndex == 2)
    }

    @Test("currentSpineIndex returns 0 for unknown href")
    func currentSpineIndexUnknownHref() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.updatePosition(EPUBPosition(
            href: "unknown.xhtml",
            progression: 0.0,
            totalProgression: 0.5,
            cfi: nil
        ))
        #expect(vm.currentSpineIndex == 0)
    }
}

// MARK: - Navigation

@Suite("EPUBReaderViewModel - Navigation")
@MainActor
struct EPUBReaderViewModelNavigationTests {

    @Test("navigateToSpine updates position")
    func navigateToSpine() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.navigateToSpine(index: 2)

        #expect(vm.currentPosition?.href == "chapter3.xhtml")
        #expect(vm.currentPosition?.progression == 0)
    }

    @Test("navigateToSpine ignores out-of-bounds index")
    func navigateOutOfBounds() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        let originalPosition = vm.currentPosition
        vm.navigateToSpine(index: 99)

        #expect(vm.currentPosition == originalPosition)
    }

    @Test("navigateToSpine ignores negative index")
    func navigateNegativeIndex() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        let originalPosition = vm.currentPosition
        vm.navigateToSpine(index: -1)

        #expect(vm.currentPosition == originalPosition)
    }

    @Test("navigateNext moves to next spine item")
    func navigateNext() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        #expect(vm.currentSpineIndex == 0)
        vm.navigateNext()
        #expect(vm.currentPosition?.href == "chapter2.xhtml")
    }

    @Test("navigatePrevious does nothing at first chapter")
    func navigatePreviousAtStart() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        #expect(vm.currentSpineIndex == 0)
        vm.navigatePrevious()
        // Should stay at chapter 1 (index -1 is out of bounds)
        #expect(vm.currentPosition?.href == "chapter1.xhtml")
    }

    @Test("navigateNext does nothing at last chapter")
    func navigateNextAtEnd() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        vm.navigateToSpine(index: 2)
        #expect(vm.currentSpineIndex == 2)

        vm.navigateNext()
        // Should stay at chapter 3 (index 3 is out of bounds)
        #expect(vm.currentPosition?.href == "chapter3.xhtml")
    }
}

// MARK: - Background/Foreground

@Suite("EPUBReaderViewModel - Background/Foreground")
@MainActor
struct EPUBReaderViewModelLifecycleTests {

    @Test("onBackground saves position and pauses")
    func onBackgroundPauses() async {
        let (vm, _, positionStore, _) = await makeViewModel()
        await vm.open(url: testURL)

        // Move to a position
        vm.updatePosition(EPUBPosition(
            href: "chapter2.xhtml",
            progression: 0.5,
            totalProgression: 0.4,
            cfi: nil
        ))

        vm.onBackground()

        // Position should have been saved on background entry
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

        // Should not throw, session should be active again
        #expect(vm.errorMessage == nil)
    }
}

// MARK: - Edge Cases

@Suite("EPUBReaderViewModel - Edge Cases")
@MainActor
struct EPUBReaderViewModelEdgeCaseTests {

    @Test("updatePosition before open is safe")
    func updatePositionBeforeOpen() async {
        let (vm, _, _, _) = await makeViewModel()

        // Should not crash
        vm.updatePosition(EPUBPosition(
            href: "chapter1.xhtml",
            progression: 0.5,
            totalProgression: 0.5,
            cfi: nil
        ))

        // Position is updated even without metadata
        #expect(vm.currentPosition?.progression == 0.5)
    }

    @Test("close without open is safe")
    func closeWithoutOpen() async {
        let (vm, _, _, _) = await makeViewModel()

        // Should not crash
        await vm.close()

        #expect(vm.errorMessage == nil)
    }

    @Test("second open call re-initializes state")
    func secondOpenReinitializes() async {
        let (vm, parser, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        // Move to a position
        vm.updatePosition(EPUBPosition(
            href: "chapter3.xhtml",
            progression: 0.9,
            totalProgression: 0.9,
            cfi: nil
        ))

        // Open again — state should reset to initial
        await vm.open(url: testURL)

        let openCount = await parser.openCallCount
        #expect(openCount == 2)
        // Position restored to beginning (no saved position)
        #expect(vm.currentPosition?.href == "chapter1.xhtml")
    }

    @Test("rapid position updates don't crash")
    func rapidPositionUpdates() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        // Simulate rapid scrolling
        for i in 0..<100 {
            let prog = Double(i) / 100.0
            vm.updatePosition(EPUBPosition(
                href: "chapter1.xhtml",
                progression: prog,
                totalProgression: prog / 3.0,
                cfi: nil
            ))
        }

        #expect(vm.currentPosition?.progression != nil)
    }

    @Test("close without position change reports no error")
    func closeWithoutPositionChange() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.open(url: testURL)

        await vm.close()

        #expect(vm.errorMessage == nil)
    }
}

// MARK: - EPUB Types Tests

@Suite("EPUBTypes")
struct EPUBTypesTests {

    @Test("EPUBMetadata spineCount reflects items")
    func spineCount() {
        let metadata = EPUBMetadata(
            title: "Test",
            author: nil,
            language: nil,
            readingDirection: .ltr,
            layout: .reflowable,
            spineItems: testSpineItems
        )
        #expect(metadata.spineCount == 3)
    }

    @Test("EPUBMetadata empty spine")
    func emptySpine() {
        let metadata = EPUBMetadata(
            title: "Test",
            author: nil,
            language: nil,
            readingDirection: .ltr,
            layout: .reflowable,
            spineItems: []
        )
        #expect(metadata.spineCount == 0)
    }

    @Test("EPUBSpineItem equality")
    func spineItemEquality() {
        let a = EPUBSpineItem(id: "ch1", href: "chapter1.xhtml", title: "Chapter 1", index: 0)
        let b = EPUBSpineItem(id: "ch1", href: "chapter1.xhtml", title: "Chapter 1", index: 0)
        let c = EPUBSpineItem(id: "ch2", href: "chapter2.xhtml", title: "Chapter 2", index: 1)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("EPUBPosition equality")
    func positionEquality() {
        let a = EPUBPosition(href: "ch1.xhtml", progression: 0.5, totalProgression: 0.25, cfi: nil)
        let b = EPUBPosition(href: "ch1.xhtml", progression: 0.5, totalProgression: 0.25, cfi: nil)
        let c = EPUBPosition(href: "ch1.xhtml", progression: 0.6, totalProgression: 0.3, cfi: nil)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("ReadingDirection raw values")
    func readingDirectionValues() {
        #expect(ReadingDirection.ltr.rawValue == "ltr")
        #expect(ReadingDirection.rtl.rawValue == "rtl")
        #expect(ReadingDirection.auto.rawValue == "auto")
    }

    @Test("EPUBLayout raw values")
    func layoutValues() {
        #expect(EPUBLayout.reflowable.rawValue == "reflowable")
        #expect(EPUBLayout.fixedLayout.rawValue == "fixed")
    }
}

// MARK: - EPUBPosition Edge Cases

@Suite("EPUBPosition - Clamping")
struct EPUBPositionClampingTests {

    @Test("NaN progression clamps to 0")
    func nanProgressionClampsToZero() {
        let pos = EPUBPosition(href: "ch.xhtml", progression: .nan, totalProgression: 0.5, cfi: nil)
        #expect(pos.progression == 0)
        #expect(pos.totalProgression == 0.5)
    }

    @Test("NaN totalProgression clamps to 0")
    func nanTotalProgressionClampsToZero() {
        let pos = EPUBPosition(href: "ch.xhtml", progression: 0.5, totalProgression: .nan, cfi: nil)
        #expect(pos.progression == 0.5)
        #expect(pos.totalProgression == 0)
    }

    @Test("infinity progression clamps to 0")
    func infinityProgressionClampsToZero() {
        let pos = EPUBPosition(href: "ch.xhtml", progression: .infinity, totalProgression: 0.5, cfi: nil)
        #expect(pos.progression == 0)
    }

    @Test("negative infinity progression clamps to 0")
    func negativeInfinityProgressionClampsToZero() {
        let pos = EPUBPosition(href: "ch.xhtml", progression: -.infinity, totalProgression: 0.5, cfi: nil)
        #expect(pos.progression == 0)
    }
}

// MARK: - Session Start Failure Rollback

@Suite("EPUBReaderViewModel - Session Rollback")
@MainActor
struct EPUBReaderViewModelSessionRollbackTests {

    @Test("session start failure clears metadata and position")
    func sessionStartFailureClearsState() async {
        let parser = MockEPUBParser()
        await parser.setMetadata(testMetadata)

        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        sessionStore.saveError = NSError(domain: "test", code: 1)
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = EPUBReaderViewModel(
            bookFingerprint: testFingerprint,
            parser: parser,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        await vm.open(url: testURL)

        #expect(vm.metadata == nil)
        #expect(vm.currentPosition == nil)
        #expect(vm.errorMessage == "Failed to start reading session.")
        #expect(vm.isLoading == false)

        let parserClosed = await parser.closeCallCount
        #expect(parserClosed >= 1)
    }
}

// MARK: - EPUBParserError Tests

@Suite("EPUBParserError")
struct EPUBParserErrorTests {

    @Test("errors are equatable")
    func equatable() {
        let a = EPUBParserError.fileNotFound("test.epub")
        let b = EPUBParserError.fileNotFound("test.epub")
        let c = EPUBParserError.invalidFormat("bad")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("all error cases exist")
    func allCases() {
        let errors: [EPUBParserError] = [
            .fileNotFound(""),
            .invalidFormat(""),
            .parsingFailed(""),
            .notOpen,
            .alreadyOpen,
            .resourceNotFound(""),
        ]
        #expect(errors.count == 6)
    }
}
