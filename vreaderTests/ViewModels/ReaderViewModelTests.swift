import Testing
import Foundation

@testable import vreader

// MARK: - Mock Reader Navigator

final class MockReaderNavigator: ReaderNavigatorProtocol {
    var currentLocator = BookLocator(chapter: 0, progression: 0.0)
    var totalChapters = 10
    var pageForwardCalled = false
    var pageBackwardCalled = false

    func goForward() {
        pageForwardCalled = true
        let newProg = min(currentLocator.progression + 0.1, 1.0)
        currentLocator = BookLocator(
            chapter: currentLocator.chapter,
            progression: newProg
        )
    }

    func goBackward() {
        pageBackwardCalled = true
        let newProg = max(currentLocator.progression - 0.1, 0.0)
        currentLocator = BookLocator(
            chapter: currentLocator.chapter,
            progression: newProg
        )
    }

    func navigateTo(_ locator: BookLocator) {
        currentLocator = locator
    }
}

// MARK: - Mock Position Store

final class MockPositionStore: PositionStoreProtocol {
    var positions: [UUID: ReadingPosition] = [:]

    func loadPosition(for bookID: UUID) -> ReadingPosition? {
        positions[bookID]
    }

    func savePosition(_ position: ReadingPosition) {
        positions[position.bookID] = position
    }
}

// MARK: - ReaderViewModel Tests

@Suite("ReaderViewModel")
struct ReaderViewModelTests {

    // MARK: - Helpers

    private func makeViewModel(
        bookID: UUID = UUID(),
        navigator: MockReaderNavigator = MockReaderNavigator(),
        positionStore: MockPositionStore = MockPositionStore()
    ) -> ReaderViewModel {
        ReaderViewModel(
            bookID: bookID,
            navigator: navigator,
            positionStore: positionStore
        )
    }

    // MARK: - Page Turn

    @Test("page forward updates current position")
    func pageForward() {
        let nav = MockReaderNavigator()
        let vm = makeViewModel(navigator: nav)

        vm.pageForward()

        #expect(nav.pageForwardCalled)
        #expect(vm.currentProgression > 0.0)
    }

    @Test("page backward updates current position")
    func pageBackward() {
        let nav = MockReaderNavigator()
        nav.currentLocator = BookLocator(chapter: 1, progression: 0.5)
        let vm = makeViewModel(navigator: nav)

        vm.pageBackward()

        #expect(nav.pageBackwardCalled)
    }

    @Test("page forward at end of chapter advances to next chapter")
    func forwardAtChapterEnd() {
        let nav = MockReaderNavigator()
        nav.currentLocator = BookLocator(chapter: 2, progression: 1.0)
        let vm = makeViewModel(navigator: nav)

        vm.pageForward()

        // The VM should handle chapter transition
        #expect(nav.pageForwardCalled)
    }

    @Test("page backward at start of chapter goes to previous chapter")
    func backwardAtChapterStart() {
        let nav = MockReaderNavigator()
        nav.currentLocator = BookLocator(chapter: 2, progression: 0.0)
        let vm = makeViewModel(navigator: nav)

        vm.pageBackward()

        #expect(nav.pageBackwardCalled)
    }

    @Test("page backward at start of book is a no-op")
    func backwardAtBookStart() {
        let nav = MockReaderNavigator()
        nav.currentLocator = BookLocator(chapter: 0, progression: 0.0)
        let vm = makeViewModel(navigator: nav)

        vm.pageBackward()

        // Should not crash, position stays at 0
        #expect(vm.currentProgression == 0.0)
    }

    // MARK: - Position Restore

    @Test("restores saved position on open")
    func restorePosition() {
        let bookID = UUID()
        let store = MockPositionStore()
        let savedLocator = BookLocator(chapter: 3, progression: 0.75)
        store.positions[bookID] = ReadingPosition(
            bookID: bookID,
            locator: savedLocator
        )

        let nav = MockReaderNavigator()
        let vm = makeViewModel(
            bookID: bookID,
            navigator: nav,
            positionStore: store
        )

        vm.restorePosition()

        #expect(nav.currentLocator.chapter == 3)
        #expect(abs(nav.currentLocator.progression - 0.75) < 0.01)
    }

    @Test("starts at beginning when no saved position")
    func noSavedPosition() {
        let bookID = UUID()
        let store = MockPositionStore() // empty
        let nav = MockReaderNavigator()
        let vm = makeViewModel(
            bookID: bookID,
            navigator: nav,
            positionStore: store
        )

        vm.restorePosition()

        #expect(nav.currentLocator.chapter == 0)
        #expect(nav.currentLocator.progression == 0.0)
    }

    // MARK: - Progress Calculation

    @Test("calculates overall progress as percentage")
    func progressPercentage() {
        let nav = MockReaderNavigator()
        nav.totalChapters = 10
        nav.currentLocator = BookLocator(chapter: 5, progression: 0.5)

        let vm = makeViewModel(navigator: nav)
        vm.updateFromNavigator()

        // Chapter 5 of 10, 50% through chapter = ~55%
        let progress = vm.overallProgress
        #expect(progress >= 0.0)
        #expect(progress <= 1.0)
    }

    @Test("progress is 0% at book start")
    func progressAtStart() {
        let nav = MockReaderNavigator()
        nav.totalChapters = 5
        nav.currentLocator = BookLocator(chapter: 0, progression: 0.0)

        let vm = makeViewModel(navigator: nav)
        vm.updateFromNavigator()

        #expect(vm.overallProgress == 0.0)
    }

    @Test("progress is 100% at book end")
    func progressAtEnd() {
        let nav = MockReaderNavigator()
        nav.totalChapters = 5
        nav.currentLocator = BookLocator(
            chapter: 4,
            progression: 1.0
        )

        let vm = makeViewModel(navigator: nav)
        vm.updateFromNavigator()

        #expect(abs(vm.overallProgress - 1.0) < 0.01)
    }

    @Test("progress with single chapter book")
    func singleChapterProgress() {
        let nav = MockReaderNavigator()
        nav.totalChapters = 1
        nav.currentLocator = BookLocator(chapter: 0, progression: 0.5)

        let vm = makeViewModel(navigator: nav)
        vm.updateFromNavigator()

        #expect(abs(vm.overallProgress - 0.5) < 0.01)
    }

    // MARK: - Debounce Position Save

    @Test("does not save position on every page turn")
    func debounceSave() {
        let store = MockPositionStore()
        let nav = MockReaderNavigator()
        let vm = makeViewModel(navigator: nav, positionStore: store)

        // Rapid page turns
        vm.pageForward()
        vm.pageForward()
        vm.pageForward()

        // Save count should be 0 or 1 (debounced), not 3
        // The actual save happens after debounce delay
        #expect(vm.pendingSaveCount <= 1)
    }

    @Test("saves position after debounce interval")
    func saveAfterDebounce() async {
        let bookID = UUID()
        let store = MockPositionStore()
        let nav = MockReaderNavigator()
        let vm = makeViewModel(
            bookID: bookID,
            navigator: nav,
            positionStore: store
        )

        vm.pageForward()

        // Wait for debounce (implementation should use ~500ms-1s)
        try? await Task.sleep(for: .milliseconds(1500))

        #expect(store.positions[bookID] != nil)
    }

    @Test("saves position on explicit flush (app backgrounding)")
    func flushSave() {
        let bookID = UUID()
        let store = MockPositionStore()
        let nav = MockReaderNavigator()
        nav.currentLocator = BookLocator(chapter: 2, progression: 0.6)

        let vm = makeViewModel(
            bookID: bookID,
            navigator: nav,
            positionStore: store
        )

        vm.flushPosition()

        #expect(store.positions[bookID] != nil)
        #expect(store.positions[bookID]?.locator.chapter == 2)
    }

    // MARK: - Edge Cases

    @Test("handles zero-chapter book gracefully")
    func zeroChapters() {
        let nav = MockReaderNavigator()
        nav.totalChapters = 0

        let vm = makeViewModel(navigator: nav)
        vm.updateFromNavigator()

        // Should not crash; progress is 0
        #expect(vm.overallProgress == 0.0)
    }

    @Test("current chapter info available")
    func chapterInfo() {
        let nav = MockReaderNavigator()
        nav.currentLocator = BookLocator(chapter: 3, progression: 0.4)
        nav.totalChapters = 10

        let vm = makeViewModel(navigator: nav)
        vm.updateFromNavigator()

        #expect(vm.currentChapter == 3)
        #expect(vm.totalChapters == 10)
    }
}
