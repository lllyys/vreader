// Feature #86 WI-4: the ChatAnnotationCache — loads the reader's annotations
// once and refreshes ONLY on `.readerAnnotationsDidChange` (never on relocate),
// and AIChatViewModel.setSources (the sources re-assembly funnel). XCTest for the
// cache (NotificationCenter + async load timing); Swift Testing for the VM.

import XCTest
import Foundation
@testable import vreader

// A mock conforming to all three annotation-persisting protocols. Returns canned
// records and counts fetch calls (to prove "no refetch on relocate").
private actor MockAnnotationStores: AnnotationPersisting, HighlightPersisting, BookmarkPersisting {
    private let annotations: [AnnotationRecord]
    private let highlights: [HighlightRecord]
    private let bookmarks: [BookmarkRecord]
    private(set) var fetchCount = 0

    init(annotations: [AnnotationRecord] = [], highlights: [HighlightRecord] = [], bookmarks: [BookmarkRecord] = []) {
        self.annotations = annotations
        self.highlights = highlights
        self.bookmarks = bookmarks
    }
    func fetchAnnotations(forBookWithKey key: String) async throws -> [AnnotationRecord] { fetchCount += 1; return annotations }
    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] { fetchCount += 1; return highlights }
    func fetchBookmarks(forBookWithKey key: String) async throws -> [BookmarkRecord] { fetchCount += 1; return bookmarks }
    // Unused mutation methods (the cache only reads).
    func addAnnotation(locator: Locator, content: String, toBookWithKey key: String) async throws -> AnnotationRecord { fatalError() }
    func removeAnnotation(annotationId: UUID) async throws {}
    func updateAnnotation(annotationId: UUID, content: String) async throws {}
    func addHighlight(locator: Locator, selectedText: String, color: String, note: String?, toBookWithKey key: String) async throws -> HighlightRecord { fatalError() }
    func addHighlight(locator: Locator, anchor: AnnotationAnchor?, selectedText: String, color: String, note: String?, toBookWithKey key: String) async throws -> HighlightRecord { fatalError() }
    func removeHighlight(highlightId: UUID) async throws {}
    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}
    func fetchHighlight(highlightId: UUID) async throws -> HighlightRecord? { nil }
    func addBookmark(locator: Locator, title: String?, toBookWithKey key: String) async throws -> BookmarkRecord { fatalError() }
    func removeBookmark(bookmarkId: UUID) async throws {}
    func updateBookmarkTitle(bookmarkId: UUID, title: String?) async throws {}
    func isBookmarked(locator: Locator, forBookWithKey key: String) async throws -> Bool { false }
}

@MainActor
final class ChatAnnotationCacheTests: XCTestCase {

    private let fp = DocumentFingerprint(
        contentSHA256: String(repeating: "d", count: 64), fileByteCount: 100, format: .txt
    )
    private func loc(_ o: Int) -> Locator {
        LocatorFactory.txtPosition(fingerprint: fp, charOffsetUTF16: o)!
    }
    private func note(_ s: String) -> AnnotationRecord {
        AnnotationRecord(annotationId: UUID(), locator: loc(0), profileKey: "k", content: s, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }
    private func highlight(_ s: String, note: String? = nil) -> HighlightRecord {
        HighlightRecord(highlightId: UUID(), locator: loc(0), anchor: nil, profileKey: "k", selectedText: s, color: "yellow", note: note, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }
    private func bookmark(_ t: String) -> BookmarkRecord {
        BookmarkRecord(bookmarkId: UUID(), locator: loc(0), profileKey: "k", title: t, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    func test_load_populatesRecordsAndCounts() async {
        let stores = MockAnnotationStores(
            annotations: [note("a standalone note")],
            highlights: [highlight("h1", note: "annotated"), highlight("h2")],
            bookmarks: [bookmark("bm")]
        )
        let cache = ChatAnnotationCache(
            fingerprintKey: fp.canonicalKey,
            annotationStore: stores, highlightStore: stores, bookmarkStore: stores
        )
        await cache.load()
        XCTAssertEqual(cache.counts.notes, 2)        // 1 standalone + 1 annotated highlight
        XCTAssertEqual(cache.counts.highlights, 2)
        XCTAssertEqual(cache.counts.bookmarks, 1)
    }

    func test_refreshesOnMutationBus_notOnRelocate() async throws {
        let stores = MockAnnotationStores(annotations: [note("n")])
        let cache = ChatAnnotationCache(
            fingerprintKey: fp.canonicalKey,
            annotationStore: stores, highlightStore: stores, bookmarkStore: stores
        )
        await cache.load()
        let afterLoad = await stores.fetchCount   // 3 (one per kind)

        // A relocate posts NO annotation bus → no refetch.
        NotificationCenter.default.post(name: .readerPositionDidChange, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        let afterRelocate = await stores.fetchCount
        XCTAssertEqual(afterRelocate, afterLoad, "relocate must not refetch annotations")

        // The mutation-complete bus DOES refetch (and fires onChange).
        let exp = expectation(description: "onChange after bus")
        cache.onChange = { exp.fulfill() }
        NotificationCenter.default.post(name: .readerAnnotationsDidChange, object: nil)
        await fulfillment(of: [exp], timeout: 2.0)
        let afterMutation = await stores.fetchCount
        XCTAssertGreaterThan(afterMutation, afterRelocate, "mutation bus must refetch")
    }

    func test_annotationBlock_respectsSelection() async {
        let stores = MockAnnotationStores(
            annotations: [note("my standalone note")],
            highlights: [highlight("a highlighted phrase")],
            bookmarks: [bookmark("a bookmark")]
        )
        let cache = ChatAnnotationCache(
            fingerprintKey: fp.canonicalKey,
            annotationStore: stores, highlightStore: stores, bookmarkStore: stores
        )
        await cache.load()
        let notesOnly = cache.annotationBlock(
            for: ChatSourceSelection(notes: true, highlights: false, bookmarks: false), maxUTF16: 10_000
        )
        XCTAssertTrue(notesOnly.contains("my standalone note"))
        XCTAssertFalse(notesOnly.contains("a highlighted phrase"))

        let allOff = cache.annotationBlock(
            for: ChatSourceSelection(notes: false, highlights: false, bookmarks: false), maxUTF16: 10_000
        )
        XCTAssertTrue(allOff.isEmpty)
    }
}

// MARK: - AIChatViewModel.setSources (the sources re-assembly funnel)

@MainActor
final class AIChatViewModelSourcesTests: XCTestCase {

    private func makeVM() -> AIChatViewModel {
        AIChatViewModel(
            aiService: AIService(
                featureFlags: FeatureFlags.shared,
                consentManager: AIConsentManager(),
                keychainService: KeychainService(),
                profileStore: ProviderProfileStore.shared
            ),
            bookFingerprint: nil
        )
    }

    func test_defaultSources_notesAndHighlightsOn() {
        let vm = makeVM()
        XCTAssertTrue(vm.sources.notes)
        XCTAssertTrue(vm.sources.highlights)
        XCTAssertFalse(vm.sources.bookmarks)
        XCTAssertEqual(vm.sources.activeCount, 2)
    }

    func test_setSources_changesAndInvokesFunnel() {
        let vm = makeVM()
        var calls = 0
        vm.onScopeChanged = { calls += 1 }   // shared re-assembly funnel
        vm.setSources(ChatSourceSelection(notes: false, highlights: true, bookmarks: true))
        XCTAssertFalse(vm.sources.notes)
        XCTAssertTrue(vm.sources.bookmarks)
        XCTAssertEqual(calls, 1)
    }

    func test_setSources_sameSelection_isNoOp() {
        let vm = makeVM()
        var calls = 0
        vm.onScopeChanged = { calls += 1 }
        vm.setSources(.default)   // already default
        XCTAssertEqual(calls, 0)
    }
}
