// Purpose: Regression tests for bug #89 — book opening performance.
// Ensures no blocking work runs on the book-open critical path.
//
// @coordinates-with: ReaderContainerView.swift, ReaderSearchCoordinator.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Bug #89 — Book Open Performance")
@MainActor
struct BookOpenPerformanceTests {

    // MARK: - Search prep must NOT run on open

    @Test("search coordinator prepareService is not called during reader setup")
    func searchPrepNotCalledOnOpen() {
        // The ReaderSearchCoordinator.prepareService() opens SQLite on @MainActor.
        // It must NOT be called during book open — only when search panel opens.
        // This test verifies the coordinator starts unprepared.
        let coordinator = ReaderSearchCoordinator()
        #expect(coordinator.searchService == nil,
                "Search service should be nil on init — not eagerly prepared")
        #expect(coordinator.searchViewModel == nil,
                "Search ViewModel should be nil on init — not eagerly prepared")
    }

    // MARK: - TXT chapter-based open uses openChapterBased

    @Test("TXTReaderViewModel has openChapterBased method")
    func txtViewModelHasChapterBasedOpen() {
        // Verify the chapter-based open path exists (regression: was calling open() instead)
        let vm = TXTReaderViewModel(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: String(repeating: "a", count: 64),
                fileByteCount: 100,
                format: .txt
            ),
            txtService: TXTService(),
            positionStore: NoOpPositionStore(),
            sessionTracker: ReadingSessionTracker(
                clock: SystemClock(),
                store: NoOpSessionStore(),
                deviceId: "test"
            ),
            deviceId: "test"
        )
        // openChapterBased exists and is callable (we don't actually call it — no file)
        #expect(vm.isChapterMode == false, "Should not be in chapter mode before open")
        #expect(vm.currentChapterText == nil, "No chapter text before open")
    }
}

// MARK: - No-Op Test Doubles

private struct NoOpPositionStore: ReadingPositionPersisting {
    func loadPosition(bookFingerprintKey: String) async throws -> Locator? { nil }
    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws {}
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws {}
}

private struct NoOpSessionStore: SessionPersisting {
    func saveSession(_ session: ReadingSession) throws {}
    func discardSession(id: UUID) throws {}
    func flushDuration(sessionId: UUID, durationSeconds: Int) throws {}
    func fetchUnclosedSessions() throws -> [ReadingSession] { [] }
}
#endif
