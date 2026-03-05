// Purpose: Integration tests for PDF reader flow — verifying locator round-trip,
// page tracking across open/close, and session lifecycle integration.
//
// @coordinates-with: PDFReaderViewModel.swift, LocatorFactory.swift,
//   ReadingSessionTracker.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let pdfFP = DocumentFingerprint(
    contentSHA256: "pdf_integration_sha256_0000000000000000000000000000000000000000",
    fileByteCount: 100000,
    format: .pdf
)

// MARK: - Locator Round-Trip

@Suite("PDF Integration - Locator Round-Trip")
@MainActor
struct PDFLocatorRoundTripTests {

    @Test("PDF locator preserves page index through save/restore")
    func locatorPreservesPage() async {
        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = PDFReaderViewModel(
            bookFingerprint: pdfFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        // Simulate opening and navigating to page 7
        vm.documentDidLoad(totalPages: 20)
        try? vm.startSession()
        vm.pageDidChange(to: 7)

        // Close — this saves position
        await vm.close()

        // Verify the saved locator has the correct page
        let saved = await positionStore.position(forKey: pdfFP.canonicalKey)
        #expect(saved != nil)
        #expect(saved?.page == 7)
        #expect(saved?.totalProgression != nil)

        // Create a new ViewModel and restore
        let tracker2 = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )
        let vm2 = PDFReaderViewModel(
            bookFingerprint: pdfFP,
            positionStore: positionStore,
            sessionTracker: tracker2,
            deviceId: "test-device"
        )

        vm2.documentDidLoad(totalPages: 20)
        let restoredPage = await vm2.restorePosition()

        #expect(restoredPage == 7)
    }

    @Test("PDF locator factory creates valid locators for various pages")
    func locatorFactoryVariousPages() {
        let pages = [0, 1, 5, 99, 999]
        for page in pages {
            let locator = LocatorFactory.pdf(
                fingerprint: pdfFP,
                page: page,
                totalProgression: Double(page) / 1000.0
            )
            #expect(locator != nil, "Failed for page \(page)")
            #expect(locator?.page == page)
        }
    }

    @Test("PDF locator factory rejects negative page")
    func locatorFactoryRejectsNegativePage() {
        let locator = LocatorFactory.pdf(
            fingerprint: pdfFP,
            page: -1,
            totalProgression: 0.0
        )
        #expect(locator == nil)
    }
}

// MARK: - Session Integration

@Suite("PDF Integration - Session")
@MainActor
struct PDFSessionIntegrationTests {

    @Test("session tracks distinct pages visited")
    func sessionTracksPages() async {
        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = PDFReaderViewModel(
            bookFingerprint: pdfFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        vm.documentDidLoad(totalPages: 10)
        try? vm.startSession()

        // Visit pages: 0, 1, 2, 3, 2, 1 — distinct = 4
        vm.pageDidChange(to: 0)
        vm.pageDidChange(to: 1)
        vm.pageDidChange(to: 2)
        vm.pageDidChange(to: 3)
        vm.pageDidChange(to: 2)
        vm.pageDidChange(to: 1)

        #expect(vm.distinctPagesVisited == 4)
    }

    @Test("pagesPerHour calculation for known values")
    func pagesPerHourKnownValues() async {
        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = PDFReaderViewModel(
            bookFingerprint: pdfFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        // 60 pages in 3600 seconds = 60 pages/hr
        let rate60 = vm.calculatePagesPerHour(pagesRead: 60, durationSeconds: 3600)
        #expect(rate60 == 60.0)

        // 10 pages in 600 seconds = 60 pages/hr
        let rate10 = vm.calculatePagesPerHour(pagesRead: 10, durationSeconds: 600)
        #expect(rate10 == 60.0)

        // 1 page in 60 seconds = 60 pages/hr
        let rate1 = vm.calculatePagesPerHour(pagesRead: 1, durationSeconds: 60)
        #expect(rate1 == 60.0)

        // Under 60s returns nil
        let rateShort = vm.calculatePagesPerHour(pagesRead: 5, durationSeconds: 59)
        #expect(rateShort == nil)
    }
}

// MARK: - Background/Foreground Cycle

@Suite("PDF Integration - Background/Foreground Cycle")
@MainActor
struct PDFBackgroundForegroundTests {

    @Test("background saves position, foreground resumes cleanly")
    func backgroundForegroundCycle() async {
        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = PDFReaderViewModel(
            bookFingerprint: pdfFP,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        vm.documentDidLoad(totalPages: 20)
        try? vm.startSession()
        vm.pageDidChange(to: 5)

        // Background
        vm.onBackground()
        try? await Task.sleep(for: .milliseconds(50))

        let saveCountAfterBg = await positionStore.saveCallCount
        #expect(saveCountAfterBg >= 1)

        // Foreground
        vm.onForeground()

        #expect(vm.errorMessage == nil)
        #expect(vm.currentPageIndex == 5)
    }
}
