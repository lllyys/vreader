// Purpose: Feature #62 WI-3 — pins `TOCSheet`'s composition.
//
// `TOCSheet` is the navigation half of the annotations-panel split —
// Contents + Bookmarks, book-titled, with per-tab count badges and the
// design-faithful `TOCContentsRow` / `TOCBookmarkRow` rows. It wraps
// `ReaderSheetChrome` (`title` = the book title at runtime) and owns a
// `BookmarkListViewModel` constructed in its own `.task` so the
// Bookmarks count badge is live on appear (Gate-2 round-2 finding 5).
//
// The contracts these tests guard: the chrome title equals the passed
// `bookTitle`; the Contents badge equals `tocEntries.count`; the
// Bookmarks badge reflects the loaded bookmark count; `initialTab`
// seeds the segment; the current-chapter row is the one matching
// `currentLocator`; the empty-TOC body is the empty state with the
// Open-Search CTA.
//
// @coordinates-with: TOCSheet.swift, TOCSheetRows.swift,
//   AnnotationsEmptyStateView.swift, AnnotationsSheetRoute.swift,
//   BookmarkListViewModel.swift

import Testing
import SwiftUI
import SwiftData
@testable import vreader

@Suite("Feature #62 — TOCSheet")
@MainActor
struct TOCSheetTests {

    // MARK: - Fixtures

    private func inMemoryContainer() -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    private func makeTOCEntries(_ count: Int) -> [TOCEntry] {
        (0..<count).map { i in
            TOCEntry(
                title: "Chapter \(i + 1)",
                level: 0,
                locator: makeEPUBLocator(href: "ch\(i).xhtml", progression: 0)
            )
        }
    }

    private func makeSheet(
        bookTitle: String = "Pride and Prejudice",
        tocEntries: [TOCEntry] = [],
        tocDidLoad: Bool = true,
        currentLocator: Locator? = nil,
        theme: ReaderThemeV2 = .paper,
        initialTab: TOCSheetTab = .contents,
        onNavigate: @escaping (Locator) -> Void = { _ in },
        onOpenSearch: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) -> TOCSheet {
        TOCSheet(
            bookTitle: bookTitle,
            bookFingerprintKey: wi9EPUBFingerprint.canonicalKey,
            modelContainer: inMemoryContainer(),
            tocEntries: tocEntries,
            tocDidLoad: tocDidLoad,
            currentLocator: currentLocator,
            theme: theme,
            initialTab: initialTab,
            onNavigate: onNavigate,
            onOpenSearch: onOpenSearch,
            onDismiss: onDismiss
        )
    }

    // MARK: - Builds + chrome title

    @Test("Builds for every theme")
    func buildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let sheet = makeSheet(tocEntries: makeTOCEntries(3), theme: theme)
            _ = sheet.body
        }
    }

    @Test("Chrome title equals the passed book title")
    func chromeTitleIsBookTitle() {
        let sheet = makeSheet(bookTitle: "Moby-Dick")
        #expect(sheet.sheetChromeTitleForTesting == "Moby-Dick")
    }

    @Test("Builds and titles with a long CJK book title")
    func buildsWithCJKBookTitle() {
        let sheet = makeSheet(bookTitle: "红楼梦：风月宝鉴与大观园的兴衰史诗")
        #expect(sheet.sheetChromeTitleForTesting == "红楼梦：风月宝鉴与大观园的兴衰史诗")
        _ = sheet.body
    }

    // MARK: - Count badges

    @Test("Contents badge equals tocEntries.count")
    func contentsBadgeMatchesEntryCount() {
        #expect(makeSheet(tocEntries: makeTOCEntries(7)).contentsBadgeCount == 7)
        #expect(makeSheet(tocEntries: []).contentsBadgeCount == 0)
    }

    @Test("Bookmarks badge reflects the loaded bookmark count")
    func bookmarksBadgeMatchesLoadedCount() async throws {
        let container = inMemoryContainer()
        let persistence = PersistenceActor(modelContainer: container)
        // A Book row must exist before bookmarks can be added.
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let fp = DocumentFingerprint(canonicalKey: key)!
        // Seed 2 bookmarks through the real persistence boundary.
        _ = try await persistence.addBookmark(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch0.xhtml", progression: 0.1)!,
            title: "BM 1", toBookWithKey: key
        )
        _ = try await persistence.addBookmark(
            locator: LocatorFactory.epub(fingerprint: fp, href: "ch1.xhtml", progression: 0.2)!,
            title: "BM 2", toBookWithKey: key
        )
        let sheet = TOCSheet(
            bookTitle: "Book", bookFingerprintKey: key,
            modelContainer: container, tocEntries: makeTOCEntries(3),
            currentLocator: nil, theme: .paper, initialTab: .contents,
            onNavigate: { _ in }, onOpenSearch: {}, onDismiss: {}
        )
        // Run the exact bookmark-load the sheet's .task runs — the loaded
        // count is what the live Bookmarks badge reads.
        let loadedCount = await sheet.loadBookmarkCountForTesting()
        #expect(loadedCount == 2)
    }

    @Test("Bookmarks badge is 0 before the load resolves")
    func bookmarksBadgeZeroBeforeLoad() {
        // The badge reads 0 until loadBookmarks() returns — acceptable
        // per the design (a count, not a spinner).
        #expect(makeSheet(tocEntries: makeTOCEntries(3)).bookmarksBadgeCount == 0)
    }

    @Test("Zero counts render as 0, not a hidden badge")
    func zeroCountsRenderZero() {
        let sheet = makeSheet(tocEntries: [])
        #expect(sheet.contentsBadgeCount == 0)
        #expect(sheet.bookmarksBadgeCount == 0)
        _ = sheet.body
    }

    // MARK: - initialTab seeding

    @Test("initialTab seeds the selected segment")
    func initialTabSeedsSegment() {
        #expect(makeSheet(initialTab: .contents).selectedTabForTesting == .contents)
        #expect(makeSheet(initialTab: .bookmarks).selectedTabForTesting == .bookmarks)
    }

    // MARK: - Current-chapter row

    @Test("Current-chapter index matches currentLocator (lifted activeEntryIndex logic)")
    func currentChapterIndexMatchesLocator() {
        let entries = makeTOCEntries(5)   // ch0..ch4
        // currentLocator on ch3 — the active index must be 3.
        let loc = makeEPUBLocator(href: "ch3.xhtml", progression: 0.5)
        let sheet = makeSheet(tocEntries: entries, currentLocator: loc)
        #expect(sheet.activeEntryIndexForTesting == 3)
    }

    @Test("No current-chapter highlight when currentLocator is nil")
    func noCurrentChapterWhenLocatorNil() {
        let sheet = makeSheet(tocEntries: makeTOCEntries(5), currentLocator: nil)
        #expect(sheet.activeEntryIndexForTesting == nil)
    }

    // MARK: - Empty states

    @Test("Empty TOC renders the empty state with the Open-Search CTA")
    func emptyTOCRendersEmptyStateWithCTA() {
        var searchFired = false
        let sheet = makeSheet(
            tocEntries: [], initialTab: .contents,
            onOpenSearch: { searchFired = true }
        )
        // The Contents body is the empty state, and its CTA fires onOpenSearch.
        #expect(sheet.contentsIsEmpty)
        sheet.invokeContentsEmptyCTAForTesting()
        #expect(searchFired)
    }

    @Test("Bookmarks empty state shows only after the load completes")
    func bookmarksEmptyStateOnlyAfterLoad() async {
        // Before the load resolves, the Bookmarks body must NOT be the
        // empty state — a neutral body shows instead (no false "No
        // bookmarks yet" flash on first paint, Gate-4 finding).
        let sheet = makeSheet(tocEntries: makeTOCEntries(3), initialTab: .bookmarks)
        #expect(sheet.bookmarksEmptyStateShown == false)
    }

    @Test("Non-empty TOC is not the empty state")
    func nonEmptyTOCNotEmptyState() {
        let sheet = makeSheet(tocEntries: makeTOCEntries(4))
        #expect(sheet.contentsIsEmpty == false)
    }

    @Test("Contents empty state shows only after the host TOC build completes")
    func contentsEmptyStateOnlyAfterLoad() {
        // Before the host's eager TOC build resolves, the Contents body
        // must NOT be the "No table of contents" empty state — a Contents
        // tap during the build would otherwise flash a false empty state
        // for books whose TOC is merely still loading (Gate-4 finding).
        let loading = makeSheet(tocEntries: [], tocDidLoad: false)
        #expect(loading.contentsEmptyStateShown == false)
        #expect(loading.contentsIsEmpty)   // no entries, but state withheld

        // Once the build completes with no entries, the genuine empty
        // state ("this book ships no TOC") renders.
        let loaded = makeSheet(tocEntries: [], tocDidLoad: true)
        #expect(loaded.contentsEmptyStateShown)

        // A loaded TOC with entries is never the empty state regardless.
        let withEntries = makeSheet(tocEntries: makeTOCEntries(3), tocDidLoad: true)
        #expect(withEntries.contentsEmptyStateShown == false)
    }

    // MARK: - displayPage — consistent 1-based numbering

    @Test("displayPage normalizes a 0-based page to 1-based; nil degrades")
    func displayPageNormalizes() {
        // Locator.page is 0-based (PDF). Both TOCContentsRow and the
        // bookmark sub-line route page through displayPage so the same
        // physical page renders identically (Gate-4 finding).
        #expect(TOCSheet.displayPage(0) == 1)
        #expect(TOCSheet.displayPage(46) == 47)   // the design's "p. 47"
        #expect(TOCSheet.displayPage(nil) == nil) // EPUB/TXT — no page
    }

    // MARK: - bookmark subtitle composition (chapter · p. N · date)

    @Test("Bookmark subtitle includes the derived chapter for a page-based locator")
    func bookmarkSubtitleIncludesChapter() {
        // PDF-style TOC: 3 chapters at pages 0 / 10 / 20.
        let pdfFP = wi9PDFFingerprint
        let entries = [
            TOCEntry(title: "Opening", level: 0, locator: makePDFLocator(fingerprint: pdfFP, page: 0)),
            TOCEntry(title: "The Middle", level: 0, locator: makePDFLocator(fingerprint: pdfFP, page: 10)),
            TOCEntry(title: "The End", level: 0, locator: makePDFLocator(fingerprint: pdfFP, page: 20)),
        ]
        let sheet = makeSheet(tocEntries: entries)
        // A bookmark on page 12 is inside "The Middle"; display page 13.
        let bm = makeBookmarkRecord(
            locator: makePDFLocator(fingerprint: pdfFP, page: 12),
            title: nil
        )
        let subtitle = sheet.bookmarkSubtitleForTesting(bm)
        #expect(subtitle.contains("The Middle"))
        #expect(subtitle.contains("p. 13"))
    }

    @Test("Bookmark subtitle degrades to date-only when no TOC and no page")
    func bookmarkSubtitleDegrades() {
        // EPUB locator (no page) + no TOC → only the date remains.
        let sheet = makeSheet(tocEntries: [])
        let bm = makeBookmarkRecord(
            locator: makeEPUBLocator(href: "ch1.xhtml", progression: 0.3),
            title: nil
        )
        let subtitle = sheet.bookmarkSubtitleForTesting(bm)
        #expect(subtitle.contains("p. ") == false)   // no page component
        #expect(subtitle.isEmpty == false)            // date still present
    }
}
