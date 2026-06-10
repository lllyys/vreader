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
        spineHrefs: [String] = [],
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
            spineHrefs: spineHrefs,
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

    // MARK: - Bug #313 r2: entry-less spine items (preceding-entry fallback)

    /// "The Half Second" shape: the nav titles the chapter COVER pages, so
    /// the actual prose bodies (and the book's own toc page) are spine items
    /// with NO TOC entry. The current-chapter match must fall back to the
    /// nearest PRECEDING entry in spine order.
    private var halfSecondSpine: [String] {
        ["covers/cover-front.xhtml",                  // 0 — no entry
         "prose/front-matter/title-page.xhtml",       // 1 — "Title page"
         "prose/front-matter/copyright.xhtml",        // 2 — "Copyright"
         "covers/cover-flyleaf.xhtml",                // 3 — no entry
         "toc.xhtml",                                 // 4 — no entry
         "covers/cover-prologue.xhtml",               // 5 — "Prologue"
         "prose/book/prologue.xhtml",                 // 6 — no entry (prose body!)
         "covers/cover-ch01.xhtml",                   // 7 — "Chapter 1"
         "prose/book/chapter-01.xhtml"]               // 8 — no entry (prose body)
    }

    private var halfSecondEntries: [TOCEntry] {
        [("Title page", "prose/front-matter/title-page.xhtml"),
         ("Copyright", "prose/front-matter/copyright.xhtml"),
         ("Prologue", "covers/cover-prologue.xhtml"),
         ("Chapter 1", "covers/cover-ch01.xhtml")].map { title, href in
            TOCEntry(title: title, level: 0,
                     locator: makeEPUBLocator(href: href, progression: 0))
        }
    }

    @Test("Entry-less prose body highlights its preceding entry (the user repro)")
    func entryLessProseBody_highlightsPrecedingEntry() {
        // Reading the prologue PROSE (spine 6) — entry is its cover (spine 5).
        let loc = makeEPUBLocator(href: "prose/book/prologue.xhtml", progression: 0.4)
        let sheet = makeSheet(
            tocEntries: halfSecondEntries, currentLocator: loc,
            spineHrefs: halfSecondSpine)
        #expect(sheet.activeEntryIndexForTesting == 2, "the Prologue row highlights")
    }

    @Test("The book's own toc page highlights the preceding entry")
    func entryLessTocPage_highlightsPrecedingEntry() {
        let loc = makeEPUBLocator(href: "toc.xhtml", progression: 0.9)
        let sheet = makeSheet(
            tocEntries: halfSecondEntries, currentLocator: loc,
            spineHrefs: halfSecondSpine)
        #expect(sheet.activeEntryIndexForTesting == 1, "Copyright precedes the toc page")
    }

    @Test("A position before the first entry stays nil (don't guess)")
    func entryLessBeforeFirstEntry_returnsNil() {
        let loc = makeEPUBLocator(href: "covers/cover-front.xhtml", progression: 0.0)
        let sheet = makeSheet(
            tocEntries: halfSecondEntries, currentLocator: loc,
            spineHrefs: halfSecondSpine)
        #expect(sheet.activeEntryIndexForTesting == nil)
    }

    @Test("Exact entry match still wins over the fallback")
    func exactMatch_winsOverFallback() {
        let loc = makeEPUBLocator(href: "covers/cover-prologue.xhtml", progression: 0.0)
        let sheet = makeSheet(
            tocEntries: halfSecondEntries, currentLocator: loc,
            spineHrefs: halfSecondSpine)
        #expect(sheet.activeEntryIndexForTesting == 2)
    }

    @Test("No spine order supplied -> no fallback (pre-#313-r2 behavior)")
    func noSpineHrefs_noFallback() {
        let loc = makeEPUBLocator(href: "prose/book/prologue.xhtml", progression: 0.4)
        let sheet = makeSheet(tocEntries: halfSecondEntries, currentLocator: loc)
        #expect(sheet.activeEntryIndexForTesting == nil)
    }

    @Test("An href absent from BOTH entries and spine stays nil")
    func unknownHref_returnsNil() {
        let loc = makeEPUBLocator(href: "not-in-this-book.xhtml", progression: 0.1)
        let sheet = makeSheet(
            tocEntries: halfSecondEntries, currentLocator: loc,
            spineHrefs: halfSecondSpine)
        #expect(sheet.activeEntryIndexForTesting == nil)
    }

    @Test("Percent-encoded hrefs match only on byte-identical forms (no silent decode)")
    func encodedHref_matchesOnlyIdenticalForm() {
        // The matcher is raw-String equality by design — both producers
        // (EPUBParser spine + the position broadcast) emit the SAME form.
        // Pin that an encoded variant of a spine href does NOT match, so a
        // future one-sided decode shows up here instead of on devices.
        let spine = ["c1.xhtml", "my chapter.xhtml", "c3.xhtml"]
        let entries = [
            TOCEntry(title: "One", level: 0,
                     locator: makeEPUBLocator(href: "c1.xhtml", progression: 0)),
            TOCEntry(title: "Two", level: 0,
                     locator: makeEPUBLocator(href: "my chapter.xhtml", progression: 0)),
        ]
        // Identical form → exact match.
        let same = makeSheet(
            tocEntries: entries,
            currentLocator: makeEPUBLocator(href: "my chapter.xhtml", progression: 0.2),
            spineHrefs: spine)
        #expect(same.activeEntryIndexForTesting == 1)
        // Encoded variant → neither exact nor in the spine → nil (never guess).
        let encoded = makeSheet(
            tocEntries: entries,
            currentLocator: makeEPUBLocator(href: "my%20chapter.xhtml", progression: 0.2),
            spineHrefs: spine)
        #expect(encoded.activeEntryIndexForTesting == nil)
    }

    @Test("Duplicate entry hrefs: the LAST matching entry wins (existing convention)")
    func duplicateEntryHrefs_lastWins() {
        let spine = ["a.xhtml", "b.xhtml"]
        let entries = [
            TOCEntry(title: "Part I", level: 0,
                     locator: makeEPUBLocator(href: "a.xhtml", progression: 0)),
            TOCEntry(title: "Part I — continued", level: 1,
                     locator: makeEPUBLocator(href: "a.xhtml", progression: 0)),
        ]
        let sheet = makeSheet(
            tocEntries: entries,
            currentLocator: makeEPUBLocator(href: "a.xhtml", progression: 0.3),
            spineHrefs: spine)
        #expect(sheet.activeEntryIndexForTesting == 1)
    }

    @Test("Entries whose href is absent from the spine are skipped by the fallback")
    func entryHrefAbsentFromSpine_isSkippedInFallback() {
        let spine = ["c1.xhtml", "c2.xhtml", "c3.xhtml"]
        let entries = [
            TOCEntry(title: "One", level: 0,
                     locator: makeEPUBLocator(href: "c1.xhtml", progression: 0)),
            // A stale/foreign entry not in this spine — must not poison the walk.
            TOCEntry(title: "Ghost", level: 0,
                     locator: makeEPUBLocator(href: "ghost.xhtml", progression: 0)),
        ]
        let sheet = makeSheet(
            tocEntries: entries,
            currentLocator: makeEPUBLocator(href: "c3.xhtml", progression: 0.5),
            spineHrefs: spine)
        #expect(sheet.activeEntryIndexForTesting == 0,
                "fallback resolves through the valid entry, ignoring the ghost")
    }

    // MARK: - Current-chapter for TXT (the Bug #248 user repro: charOffsetUTF16)

    /// Builds a TXT-style TOC where each chapter starts at an increasing
    /// UTF-16 character offset — the position model TXT books use. This is
    /// the exact shape the Bug #248 user hit ("txt toc dont jump").
    private func makeTXTTOCEntries(offsets: [Int]) -> [TOCEntry] {
        offsets.enumerated().map { (i, offset) in
            TOCEntry(
                title: "Chapter \(i + 1)",
                level: 0,
                locator: makeTXTLocator(offset: offset)
            )
        }
    }

    @Test("TXT current-chapter index matches a mid-book charOffset (Bug #248 repro)")
    func txtCurrentChapterIndexMatchesOffset() {
        // 10 chapters at offsets 0, 1000, 2000, …, 9000.
        let entries = makeTXTTOCEntries(offsets: (0..<10).map { $0 * 1000 })
        // Reading position deep in chapter 5 (offset 4500 → last entry at-or-before is index 4).
        let loc = makeTXTLocator(offset: 4500)
        let sheet = makeSheet(tocEntries: entries, currentLocator: loc)
        #expect(sheet.activeEntryIndexForTesting == 4)   // chapter 5 (0-based index 4)
    }

    @Test("TXT current-chapter resolves exactly on a chapter boundary")
    func txtCurrentChapterOnBoundary() {
        let entries = makeTXTTOCEntries(offsets: (0..<10).map { $0 * 1000 })
        // Offset exactly at chapter 8's start (7000) → index 7, not 6.
        let loc = makeTXTLocator(offset: 7000)
        let sheet = makeSheet(tocEntries: entries, currentLocator: loc)
        #expect(sheet.activeEntryIndexForTesting == 7)
    }

    @Test("TXT current-chapter before the first entry's offset yields nil")
    func txtCurrentChapterBeforeFirstEntry() {
        // TOC entries start at offset 500; a position at offset 100 precedes
        // all of them → no active chapter (matches the "last at-or-before"
        // rule's empty result, not a crash / index 0).
        let entries = makeTXTTOCEntries(offsets: [500, 1500, 2500])
        let loc = makeTXTLocator(offset: 100)
        let sheet = makeSheet(tocEntries: entries, currentLocator: loc)
        #expect(sheet.activeEntryIndexForTesting == nil)
    }

    @Test("Last TXT chapter stays selected past the final entry's offset")
    func txtCurrentChapterPastLastEntry() {
        let entries = makeTXTTOCEntries(offsets: (0..<10).map { $0 * 1000 })
        // Reading past the last chapter start (offset 12000) → stays on the
        // last entry (index 9), the row the scroll target must center on.
        let loc = makeTXTLocator(offset: 12000)
        let sheet = makeSheet(tocEntries: entries, currentLocator: loc)
        #expect(sheet.activeEntryIndexForTesting == 9)
    }

    // MARK: - Scroll target id (Bug #248 — the dropped ScrollViewReader)

    /// The auto-scroll target — the `TOCEntry.id` of the active entry, which
    /// the list's `ScrollViewReader` proxy scrolls to on appear. `nil` when
    /// no current chapter is known (no reading position, or a position before
    /// the first entry), so the list opens at the top rather than guessing.
    @Test("Scroll target id is the active entry's id (Bug #248)")
    func scrollTargetIsActiveEntryID() {
        let entries = makeTXTTOCEntries(offsets: (0..<10).map { $0 * 1000 })
        let loc = makeTXTLocator(offset: 4500)   // chapter 5, index 4
        let sheet = makeSheet(tocEntries: entries, currentLocator: loc)
        #expect(sheet.currentChapterScrollTargetForTesting == entries[4].id)
    }

    @Test("Scroll target id is nil when there is no current chapter")
    func scrollTargetNilWhenNoCurrentChapter() {
        // No reading position → nothing to scroll to → list opens at the top.
        let noLoc = makeSheet(tocEntries: makeTXTTOCEntries(offsets: [0, 100]), currentLocator: nil)
        #expect(noLoc.currentChapterScrollTargetForTesting == nil)
        // Empty TOC → no target either.
        let empty = makeSheet(tocEntries: [], currentLocator: makeTXTLocator(offset: 5))
        #expect(empty.currentChapterScrollTargetForTesting == nil)
    }

    // MARK: - Scroll retry schedule timing (Bug #282 — the ~1.3s creep)

    /// Bug #282: the old `.task(id:)` loop slept BEFORE every attempt
    /// (`[100, 300, 600]`), so the authoritative scroll didn't fire until
    /// ~1000ms in (each attempt then animated 0.3s → settle ~1.3s). The
    /// schedule must now lead with an immediate t=0 attempt so a
    /// materialized row lands the instant the sheet appears; later attempts
    /// are a short fallback for the not-yet-materialized LazyVStack case.
    @Test("Scroll retry schedule leads with an immediate t=0 attempt (Bug #282)")
    func scrollRetryScheduleLeadsImmediate() {
        let schedule = TOCSheet.scrollRetryDelaysMilliseconds
        // First attempt must fire with no leading sleep.
        #expect(schedule.first == 0)
    }

    @Test("Scroll retry schedule is non-decreasing and finishes fast (Bug #282)")
    func scrollRetryScheduleMonotonicAndFast() {
        let schedule = TOCSheet.scrollRetryDelaysMilliseconds
        // A fallback is still present (at least one retry after t=0).
        #expect(schedule.count >= 2)
        // Cumulative delays are monotonically non-decreasing.
        #expect(schedule == schedule.sorted())
        // The last (authoritative) attempt fires well before the old ~1000ms
        // — the perceived-slowness regression. Keep the whole schedule under
        // half the old worst case so the chapter is on-screen near-instantly.
        #expect(schedule.last! <= 500)
    }

    // MARK: - Current-chapter row styling decision (Bug #248 — accent + bold)

    @Test("Current-chapter row styles accent + bold; others ink + regular (Bug #248)")
    func currentChapterRowStyling() {
        let theme = ReaderThemeV2.paper
        // The current row: accent foreground, semibold weight, tinted background.
        let current = TOCContentsRow.styleForTesting(theme: theme, isCurrent: true)
        #expect(current.foregroundUIColor == theme.accentColor)
        #expect(current.isBold)
        #expect(current.hasBackgroundTint)
        // A non-current row: ink foreground, regular weight, clear background.
        let other = TOCContentsRow.styleForTesting(theme: theme, isCurrent: false)
        #expect(other.foregroundUIColor == theme.inkColor)
        #expect(other.isBold == false)
        #expect(other.hasBackgroundTint == false)
    }

    @Test("Current-chapter row styling holds across every theme (Bug #248)")
    func currentChapterRowStylingEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let current = TOCContentsRow.styleForTesting(theme: theme, isCurrent: true)
            #expect(current.foregroundUIColor == theme.accentColor)
            #expect(current.isBold)
            #expect(current.hasBackgroundTint)
        }
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
