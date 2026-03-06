// Purpose: Tests for PDFReaderViewModel — open/close lifecycle, position persistence,
// session tracking integration, page tracking, pages/hr metrics, password flow, edge cases.
//
// @coordinates-with: PDFReaderViewModel.swift, MockPositionStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let pdfFingerprint = DocumentFingerprint(
    contentSHA256: "pdf_vm_test_sha256_000000000000000000000000000000000000000000",
    fileByteCount: 50000,
    format: .pdf
)

private let testURL = URL(fileURLWithPath: "/tmp/test.pdf")

// MARK: - Helpers

@MainActor
private func makeViewModel(
    fingerprint: DocumentFingerprint = pdfFingerprint
) -> (PDFReaderViewModel, MockPositionStore, MockSessionStore) {
    let positionStore = MockPositionStore()
    let sessionStore = MockSessionStore()
    let clock = MockClock()
    let tracker = ReadingSessionTracker(
        clock: clock,
        store: sessionStore,
        deviceId: "test-device"
    )

    let vm = PDFReaderViewModel(
        bookFingerprint: fingerprint,
        positionStore: positionStore,
        sessionTracker: tracker,
        deviceId: "test-device"
    )

    return (vm, positionStore, sessionStore)
}

// MARK: - Initial State

@Suite("PDFReaderViewModel - Initial State")
@MainActor
struct PDFReaderViewModelInitialStateTests {

    @Test("initial state has nil document and zero pages")
    func initialState() async {
        let (vm, _, _) = makeViewModel()

        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.currentPageIndex == 0)
        #expect(vm.totalPages == 0)
        #expect(vm.isDocumentLoaded == false)
        #expect(vm.needsPassword == false)
        #expect(vm.sessionTimeDisplay == nil)
    }
}

// MARK: - Open Lifecycle

@Suite("PDFReaderViewModel - Open")
@MainActor
struct PDFReaderViewModelOpenTests {

    @Test("open sets total pages and clears loading")
    func openSetsPages() async {
        let (vm, _, _) = makeViewModel()

        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        #expect(vm.totalPages == 10)
        #expect(vm.currentPageIndex == 0)
        #expect(vm.isDocumentLoaded == true)
        #expect(vm.errorMessage == nil)
    }

    @Test("open restores saved page position")
    func openRestoresPosition() async {
        let (vm, positionStore, _) = makeViewModel()

        // Seed a saved position at page 5
        guard let savedLocator = LocatorFactory.pdf(
            fingerprint: pdfFingerprint,
            page: 5,
            totalProgression: 0.5
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: pdfFingerprint.canonicalKey,
            locator: savedLocator
        )

        // Must load document before restoring position (clamping depends on totalPages)
        vm.documentDidLoad(totalPages: 10)
        let restored = await vm.restorePosition()
        #expect(restored == 5)
    }

    @Test("open restores position clamped to total pages")
    func openRestoresPositionClamped() async {
        let (vm, positionStore, _) = makeViewModel()

        // Seed a saved position beyond total pages
        guard let savedLocator = LocatorFactory.pdf(
            fingerprint: pdfFingerprint,
            page: 99,
            totalProgression: 0.99
        ) else {
            Issue.record("Failed to create test locator")
            return
        }
        await positionStore.seed(
            bookFingerprintKey: pdfFingerprint.canonicalKey,
            locator: savedLocator
        )

        vm.documentDidLoad(totalPages: 5)
        let restored = await vm.restorePosition()

        // Should clamp to last valid page (totalPages - 1 = 4)
        guard let restoredPage = restored else {
            Issue.record("Expected non-nil restored page")
            return
        }
        #expect(restoredPage <= 4)
    }

    @Test("open starts reading session")
    func openStartsSession() async {
        let (vm, _, sessionStore) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)

        try? vm.startSession()

        #expect(sessionStore.savedSessions.count >= 1)
    }

    @Test("open updates lastOpenedAt")
    func openUpdatesLastOpened() async {
        let (vm, positionStore, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)

        await vm.updateLastOpened()

        let count = await positionStore.updateLastOpenedCallCount
        #expect(count == 1)
    }
}

// MARK: - Close Lifecycle

@Suite("PDFReaderViewModel - Close")
@MainActor
struct PDFReaderViewModelCloseTests {

    @Test("close ends reading session")
    func closeEndsSession() async {
        let (vm, _, sessionStore) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        await vm.close()

        // Session was <5s (mock clock doesn't advance), so it should be discarded
        #expect(!sessionStore.discardedSessionIds.isEmpty)
    }

    @Test("close saves final position")
    func closeSavesPosition() async {
        let (vm, positionStore, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.pageDidChange(to: 3)

        await vm.close()

        let saveCount = await positionStore.saveCallCount
        #expect(saveCount >= 1)
    }
}

// MARK: - Page Navigation

@Suite("PDFReaderViewModel - Page Navigation")
@MainActor
struct PDFReaderViewModelPageTests {

    @Test("pageDidChange updates current page index")
    func pageDidChangeUpdatesState() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.pageDidChange(to: 5)

        #expect(vm.currentPageIndex == 5)
    }

    @Test("pageDidChange tracks distinct pages visited")
    func pageDidChangeTracksDistinct() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.pageDidChange(to: 0)
        vm.pageDidChange(to: 1)
        vm.pageDidChange(to: 2)
        vm.pageDidChange(to: 1) // revisit

        #expect(vm.distinctPagesVisited == 3)
    }

    @Test("pageDidChange clamps negative index to 0")
    func pageDidChangeClampsNegative() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.pageDidChange(to: -1)

        #expect(vm.currentPageIndex == 0)
    }

    @Test("pageDidChange clamps beyond total pages")
    func pageDidChangeClampsBeyondTotal() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 5)
        try? vm.startSession()

        vm.pageDidChange(to: 99)

        #expect(vm.currentPageIndex == 4) // 0-based: max is totalPages - 1
    }

    @Test("totalProgression computes correctly at midpoint")
    func totalProgressionMidpoint() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.pageDidChange(to: 5)

        guard let progression = vm.totalProgression else {
            Issue.record("Expected non-nil totalProgression")
            return
        }
        // 5 / max(10 - 1, 1) ≈ 0.556
        #expect(progression > 0.50)
        #expect(progression < 0.60)
    }

    @Test("totalProgression is 0 at first page")
    func totalProgressionAtStart() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        #expect(vm.totalProgression == 0.0)
    }

    @Test("totalProgression is nil for empty PDF")
    func totalProgressionEmpty() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 0)

        #expect(vm.totalProgression == nil)
    }

    @Test("page indicator string shows correct format")
    func pageIndicatorString() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.pageDidChange(to: 3)

        #expect(vm.pageIndicator == "4 / 10") // 1-based display
    }
}

// MARK: - Pages Per Hour

@Suite("PDFReaderViewModel - Pages Per Hour")
@MainActor
struct PDFReaderViewModelPagesPerHourTests {

    @Test("pagesPerHour is nil before open")
    func pagesPerHourBeforeOpen() async {
        let (vm, _, _) = makeViewModel()

        #expect(vm.pagesPerHour == nil)
    }

    @Test("pagesPerHour is nil with zero pages visited")
    func pagesPerHourZeroPages() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        #expect(vm.pagesPerHour == nil)
    }

    @Test("pagesPerHour calculates correctly")
    func pagesPerHourCalculation() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 100)
        try? vm.startSession()

        // Simulate reading 10 distinct pages over 30 minutes
        for i in 0..<10 {
            vm.pageDidChange(to: i)
        }

        // pagesPerHour with session time of 30 min = 10 / 0.5 = 20 pages/hr
        // Can't easily test with real time, so verify it returns non-nil
        // when explicitly calculated
        let rate = vm.calculatePagesPerHour(
            pagesRead: 10,
            durationSeconds: 1800 // 30 min
        )
        #expect(rate != nil)
        #expect(rate == 20.0)
    }

    @Test("pagesPerHour returns nil for session under 60s")
    func pagesPerHourUnder60s() async {
        let (vm, _, _) = makeViewModel()

        let rate = vm.calculatePagesPerHour(
            pagesRead: 5,
            durationSeconds: 30
        )
        #expect(rate == nil)
    }

    @Test("pagesPerHour returns nil for zero duration")
    func pagesPerHourZeroDuration() async {
        let (vm, _, _) = makeViewModel()

        let rate = vm.calculatePagesPerHour(
            pagesRead: 5,
            durationSeconds: 0
        )
        #expect(rate == nil)
    }
}

// MARK: - Password Flow

@Suite("PDFReaderViewModel - Password")
@MainActor
struct PDFReaderViewModelPasswordTests {

    @Test("needsPassword is set when document is locked")
    func lockedDocumentSetsNeedsPassword() async {
        let (vm, _, _) = makeViewModel()

        vm.documentNeedsPassword()

        #expect(vm.needsPassword == true)
        #expect(vm.isDocumentLoaded == false)
    }

    @Test("submitPassword clears needsPassword on success")
    func submitPasswordSuccess() async {
        let (vm, _, _) = makeViewModel()
        vm.documentNeedsPassword()

        vm.passwordAccepted(totalPages: 10)

        #expect(vm.needsPassword == false)
        #expect(vm.totalPages == 10)
        #expect(vm.isDocumentLoaded == true)
    }

    @Test("passwordRejected keeps needsPassword true")
    func passwordRejected() async {
        let (vm, _, _) = makeViewModel()
        vm.documentNeedsPassword()

        vm.passwordRejected()

        #expect(vm.needsPassword == true)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Background/Foreground

@Suite("PDFReaderViewModel - Background/Foreground")
@MainActor
struct PDFReaderViewModelLifecycleTests {

    @Test("onBackground saves position and pauses")
    func onBackgroundPauses() async {
        let (vm, positionStore, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()
        vm.pageDidChange(to: 3)

        vm.onBackground()

        // Give the background task a moment to complete
        try? await Task.sleep(for: .milliseconds(50))
        let saveCount = await positionStore.saveCallCount
        #expect(saveCount >= 1)
    }

    @Test("onForeground resumes session tracker")
    func onForegroundResumes() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.onBackground()
        vm.onForeground()

        #expect(vm.errorMessage == nil)
    }
}

// MARK: - Edge Cases

@Suite("PDFReaderViewModel - Edge Cases")
@MainActor
struct PDFReaderViewModelEdgeCaseTests {

    @Test("single page PDF works correctly")
    func singlePagePDF() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 1)
        try? vm.startSession()

        vm.pageDidChange(to: 0)

        #expect(vm.currentPageIndex == 0)
        #expect(vm.totalPages == 1)
        #expect(vm.pageIndicator == "1 / 1")
    }

    @Test("empty PDF (0 pages) handles gracefully")
    func emptyPDF() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 0)

        #expect(vm.totalPages == 0)
        #expect(vm.totalProgression == nil)
        #expect(vm.pageIndicator == "0 / 0")
    }

    @Test("close without open is safe")
    func closeWithoutOpen() async {
        let (vm, _, _) = makeViewModel()

        // Should not crash
        await vm.close()

        #expect(vm.errorMessage == nil)
    }

    @Test("pageDidChange before documentDidLoad is safe")
    func pageChangeBeforeLoad() async {
        let (vm, _, _) = makeViewModel()

        // Should not crash, should be ignored
        vm.pageDidChange(to: 5)

        #expect(vm.currentPageIndex == 0)
    }

    @Test("rapid page changes don't crash")
    func rapidPageChanges() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 100)
        try? vm.startSession()

        for i in 0..<100 {
            vm.pageDidChange(to: i)
        }

        #expect(vm.currentPageIndex >= 0)
        #expect(vm.distinctPagesVisited == 100)
    }

    @Test("locator construction uses page field")
    func locatorUsesPageField() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        vm.pageDidChange(to: 7)

        let locator = vm.makeCurrentLocator()
        #expect(locator.page == 7)
        #expect(locator.totalProgression != nil)
        #expect(locator.charOffsetUTF16 == nil)
        #expect(locator.href == nil)
    }

    @Test("session rollback on session start failure")
    func sessionStartFailure() async {
        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        sessionStore.saveError = NSError(domain: "test", code: 1)
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = PDFReaderViewModel(
            bookFingerprint: pdfFingerprint,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        vm.documentDidLoad(totalPages: 10)

        do {
            try vm.startSession()
            Issue.record("Expected startSession to throw")
        } catch {
            // Expected
        }

        #expect(vm.isDocumentLoaded == true) // document is still loaded
    }
}

// MARK: - Locator Construction

@Suite("PDFReaderViewModel - Locator")
@MainActor
struct PDFReaderViewModelLocatorTests {

    @Test("locator has correct totalProgression")
    func locatorTotalProgression() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 20)
        try? vm.startSession()

        vm.pageDidChange(to: 10)

        let locator = vm.makeCurrentLocator()
        #expect(locator.page == 10)

        guard let tp = locator.totalProgression else {
            Issue.record("Expected non-nil totalProgression")
            return
        }
        // 10 / max(20 - 1, 1) ≈ 0.526
        let expected = 10.0 / 19.0
        #expect(abs(tp - expected) < 0.001)
    }

    @Test("locator at page 0 has totalProgression 0")
    func locatorFirstPage() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        let locator = vm.makeCurrentLocator()
        #expect(locator.page == 0)
        #expect(locator.totalProgression == 0.0)
    }

    @Test("locator for empty PDF has page 0 and nil totalProgression")
    func locatorEmptyPDF() async {
        let (vm, _, _) = makeViewModel()
        vm.documentDidLoad(totalPages: 0)

        let locator = vm.makeCurrentLocator()
        #expect(locator.page == 0)
        #expect(locator.totalProgression == nil)
    }
}
