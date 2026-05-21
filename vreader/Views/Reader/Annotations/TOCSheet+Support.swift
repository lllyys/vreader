// Purpose: Feature #62 WI-3 — `TOCSheet`'s display helpers,
// current-chapter matching, badge counts, and DEBUG testing hooks.
//
// Split out of `TOCSheet.swift` to keep the main view file under the
// ~300-line guideline (`.claude/rules/50-codebase-conventions.md` §9) —
// the `+Sheets.swift` split pattern `ReaderContainerView` uses.
//
// @coordinates-with: TOCSheet.swift, TOCSheetRows.swift, TOCEntry.swift,
//   BookmarkRecord.swift

import SwiftUI

extension TOCSheet {

    // MARK: - Page display

    /// Normalizes a 0-based `Locator.page` (PDF) to a 1-based display
    /// page number, matching the design's `p. 47`. `nil` in → `nil` out
    /// (EPUB / TXT carry no page — the row degrades). Used by BOTH
    /// `TOCContentsRow` and the bookmark sub-line so the same physical
    /// page renders identically in both lists (Gate-4 finding).
    static func displayPage(_ rawPage: Int?) -> Int? {
        guard let rawPage else { return nil }
        return rawPage + 1
    }

    // MARK: - Bookmark display helpers

    /// The 1-line italic preview — the bookmark title, the quoted text,
    /// or a generic fallback.
    func bookmarkPreview(_ bookmark: BookmarkRecord) -> String {
        if let title = bookmark.title, !title.isEmpty { return title }
        if let quote = bookmark.locator.textQuote, !quote.isEmpty { return quote }
        return "Bookmark"
    }

    /// The `chapter · p. N · date` sub-line per the `TOCSheetV2` design.
    /// The chapter is derived from `tocEntries` using the same
    /// last-at-or-before matching rule as the active TOC entry; page is
    /// the 1-based display number. Each component degrades gracefully
    /// when unavailable (EPUB/TXT carry no page; a book with no TOC
    /// yields no chapter).
    func bookmarkSubtitle(_ bookmark: BookmarkRecord) -> String {
        var parts: [String] = []
        if let chapter = chapterTitle(for: bookmark.locator) { parts.append(chapter) }
        if let page = Self.displayPage(bookmark.locator.page) { parts.append("p. \(page)") }
        parts.append(Self.bookmarkDateFormatter.string(from: bookmark.createdAt))
        return parts.joined(separator: " · ")
    }

    /// The TOC chapter title containing `locator` — the title of the
    /// last `tocEntries` entry at or before that position. `nil` when
    /// the book ships no TOC or no entry precedes the locator.
    func chapterTitle(for locator: Locator) -> String? {
        guard let index = matchedEntryIndex(for: locator) else { return nil }
        return tocEntries[index].title
    }

    static let bookmarkDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: - Current-chapter matching (lifted from TOCListView)

    /// Index of the `tocEntries` entry containing `locator` — matched by
    /// `charOffsetUTF16` (TXT/MD), `page` (PDF), or `href` (EPUB),
    /// picking the last entry at or before the position. Lifted verbatim
    /// from `TOCListView.activeEntryIndex` (the logic is correct; only
    /// the row rendering is new — Gate-2 round-2 finding 1). Shared by
    /// the current-chapter highlight and bookmark-chapter derivation.
    func matchedEntryIndex(for locator: Locator) -> Int? {
        if let offset = locator.charOffsetUTF16 {
            var best: Int?
            for (i, entry) in tocEntries.enumerated() {
                if let o = entry.locator.charOffsetUTF16, o <= offset { best = i }
            }
            return best
        }
        if let page = locator.page {
            var best: Int?
            for (i, entry) in tocEntries.enumerated() {
                if let p = entry.locator.page, p <= page { best = i }
            }
            return best
        }
        if let href = locator.href {
            var best: Int?
            for (i, entry) in tocEntries.enumerated() {
                if entry.locator.href == href { best = i }
            }
            return best
        }
        return nil
    }

    /// The active TOC entry for `currentLocator` — `nil` when no reading
    /// position is known.
    var activeEntryIndex: Int? {
        guard let loc = currentLocator else { return nil }
        return matchedEntryIndex(for: loc)
    }

    /// The `TOCEntry.id` the Contents list scrolls to on appear — the active
    /// entry's stable id, or `nil` when there is no current chapter (no
    /// reading position, an out-of-range index, or a position before the
    /// first entry). `nil` means "open at the top, don't guess". Restores
    /// the auto-scroll capability feature #62 WI-5 dropped (Bug #248): the
    /// list's `ScrollViewReader` proxy targets this id.
    var currentChapterScrollTarget: String? {
        guard let index = activeEntryIndex, tocEntries.indices.contains(index) else { return nil }
        return tocEntries[index].id
    }

    // MARK: - Badge counts

    /// The Contents tab badge — the TOC entry count.
    var contentsBadgeCount: Int { tocEntries.count }

    /// The Bookmarks tab badge — the loaded bookmark count (0 before
    /// the sheet-owned load resolves).
    var bookmarksBadgeCount: Int { bookmarkVM?.bookmarks.count ?? 0 }
}

// MARK: - Testing hooks

#if DEBUG
extension TOCSheet {
    /// The title `ReaderSheetChrome` is built with — the book title.
    var sheetChromeTitleForTesting: String { bookTitle }

    /// The seeded / currently-selected tab.
    var selectedTabForTesting: TOCSheetTab { selectedTab }

    /// The lifted `activeEntryIndex` result, for the current-chapter test.
    var activeEntryIndexForTesting: Int? { activeEntryIndex }

    /// The id the Contents list auto-scrolls to on appear — for the
    /// Bug #248 scroll-target test.
    var currentChapterScrollTargetForTesting: String? { currentChapterScrollTarget }

    /// True when the Contents tab carries no TOC entries — distinct
    /// from whether the empty *state* renders (that is also gated on
    /// `tocDidLoad`; see `contentsEmptyStateShown`).
    var contentsIsEmpty: Bool { tocEntries.isEmpty }

    /// True when the Contents body would render the "No table of
    /// contents" empty state — i.e. the host's TOC build has completed
    /// AND no entries exist. Before the build completes this is `false`
    /// (a neutral body shows, not the empty state — Gate-4 finding).
    var contentsEmptyStateShown: Bool {
        tocDidLoad && tocEntries.isEmpty
    }

    /// True when the Bookmarks body would render the empty state — i.e.
    /// the load has completed AND no bookmarks exist. Before the load
    /// completes this is `false` (a neutral body shows, not the empty
    /// state — Gate-4 finding).
    var bookmarksEmptyStateShown: Bool {
        bookmarksDidLoad && (bookmarkVM?.bookmarks ?? []).isEmpty
    }

    /// Runs the exact bookmark-load the sheet's `.task` runs and returns
    /// the loaded count — for the Bookmarks-count-badge test. Returns the
    /// count rather than mutating `@State` because `@State` is not
    /// observable outside a render tree; the sheet's `.task` + render
    /// path is what feeds the live badge in the app.
    func loadBookmarkCountForTesting() async -> Int {
        let vm = BookmarkListViewModel(
            bookFingerprintKey: bookFingerprintKey,
            store: PersistenceActor(modelContainer: modelContainer)
        )
        await vm.loadBookmarks()
        return vm.bookmarks.count
    }

    /// The bookmark sub-line a row would show — for the
    /// chapter·page·date composition test.
    func bookmarkSubtitleForTesting(_ bookmark: BookmarkRecord) -> String {
        bookmarkSubtitle(bookmark)
    }

    /// Invokes the Contents-empty "Open Search" CTA — dismiss then search.
    func invokeContentsEmptyCTAForTesting() {
        onDismiss()
        onOpenSearch()
    }
}
#endif
