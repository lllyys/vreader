// Purpose: Feature #62 WI-4 — `HighlightsSheet`'s count/stream helpers,
// card meta-label formatting, empty-state copy, and DEBUG testing hooks.
//
// Split out of `HighlightsSheet.swift` to keep the main view file under
// the ~300-line guideline (`.claude/rules/50-codebase-conventions.md`
// §9) — the `+Sheets.swift` split pattern `ReaderContainerView` uses.
//
// @coordinates-with: HighlightsSheet.swift, AnnotationStreamBuilder.swift,
//   AnnotationStreamItem.swift, Locator.swift

import SwiftUI

extension HighlightsSheet {

    // MARK: - Records

    /// The loaded highlight records (empty before the `.task` resolves).
    var highlights: [HighlightRecord] { highlightVM?.highlights ?? [] }

    /// The loaded standalone-annotation records.
    var annotations: [AnnotationRecord] { annotationVM?.annotations ?? [] }

    // MARK: - Counts + stream

    /// The four filter-chip counts, computed by the pure
    /// `AnnotationStreamBuilder` per the #860 design semantics.
    var filterCounts: [HighlightsSheetFilter: Int] {
        AnnotationStreamBuilder.counts(highlights: highlights, annotations: annotations)
    }

    /// The card stream for the active filter — newest-first, interleaved.
    var currentStream: [AnnotationStreamItem] {
        AnnotationStreamBuilder.stream(
            highlights: highlights, annotations: annotations, filter: activeFilter
        )
    }

    // MARK: - Card meta label

    /// The `chapter · p. N` meta sub-line a card shows, per the
    /// `HighlightsSheetV3` design. The chapter is resolved from
    /// `tocEntries` (the last entry at or before the locator — the same
    /// matching rule `TOCSheet` uses); the page is the 1-based display
    /// number. Each component degrades gracefully: a book with no TOC
    /// yields no chapter; an EPUB/TXT locator yields no page.
    func metaLabel(for locator: Locator) -> String {
        var parts: [String] = []
        if let chapter = chapterTitle(for: locator) { parts.append(chapter) }
        if let page = locator.page { parts.append("p. \(page + 1)") }
        return parts.joined(separator: " · ")
    }

    /// The TOC chapter title containing `locator` — the title of the
    /// last `tocEntries` entry at or before that position, matched by
    /// `charOffsetUTF16` (TXT/MD), `page` (PDF), or `href` (EPUB).
    /// `nil` when the book ships no TOC or no entry precedes the locator.
    func chapterTitle(for locator: Locator) -> String? {
        var best: Int?
        if let offset = locator.charOffsetUTF16 {
            for (i, e) in tocEntries.enumerated() {
                if let o = e.locator.charOffsetUTF16, o <= offset { best = i }
            }
        } else if let page = locator.page {
            for (i, e) in tocEntries.enumerated() {
                if let p = e.locator.page, p <= page { best = i }
            }
        } else if let href = locator.href {
            for (i, e) in tocEntries.enumerated() {
                if e.locator.href == href { best = i }
            }
        }
        guard let index = best else { return nil }
        return tocEntries[index].title
    }

    // MARK: - Empty-state copy (per filter, per #860 design)

    /// Empty-state heading for a filter — pinned to `HighlightsSheetV3`.
    func emptyTitle(_ filter: HighlightsSheetFilter) -> String {
        switch filter {
        case .all:        return "No highlights or notes yet"
        case .highlights: return "No highlights yet"
        case .notes:      return "No notes yet"
        case .bookmarks:  return "No bookmarks yet"
        }
    }

    /// Empty-state body for a filter — pinned to `HighlightsSheetV3`.
    func emptyBody(_ filter: HighlightsSheetFilter) -> String {
        switch filter {
        case .all:
            return "Long-press any passage to highlight or add a note. Or tap the note icon on a chapter to leave a standalone note that isn't tied to a passage."
        case .highlights:
            return "Long-press any passage to highlight it. Pick a colour to keep them organised."
        case .notes:
            return "Add a note to any highlight, or leave a standalone note at a chapter."
        case .bookmarks:
            return "Tap the bookmark icon in the top bar to save your place."
        }
    }

    /// The empty-state view's accessibility identifier — distinct for
    /// the Bookmarks filter so XCUITest can target it.
    var emptyStateIdentifier: String {
        activeFilter == .bookmarks ? "highlightsBookmarksEmptyState" : "highlightsEmptyState"
    }
}

// MARK: - Testing hooks

#if DEBUG
extension HighlightsSheet {
    /// The title `ReaderSheetChrome` is built with.
    var sheetChromeTitleForTesting: String { "Annotations" }

    /// The seeded / currently-active filter.
    var activeFilterForTesting: HighlightsSheetFilter { activeFilter }

    /// The filter-chip set, in render order.
    var filterChipsForTesting: [HighlightsSheetFilter] { HighlightsSheetFilter.allCases }

    /// The trailing slot ships exactly one button — the export button.
    var trailingButtonCountForTesting: Int { 1 }

    /// `HighlightsSheet` ships the designed export button.
    var hasExportButtonForTesting: Bool { true }

    /// `HighlightsSheet` ships NO import button — the import affordance
    /// is deferred to needs-design #963 (round-2 finding 2).
    var hasImportButtonForTesting: Bool { false }

    /// The empty-state title a filter would show.
    func emptyTitleForTesting(_ filter: HighlightsSheetFilter) -> String {
        emptyTitle(filter)
    }

    /// Runs the exact record load the sheet's `.task` runs, then returns
    /// the `AnnotationStreamBuilder` counts — for the count-badge test.
    /// Returns the value rather than mutating `@State` (not observable
    /// outside a render tree).
    func loadCountsForTesting() async -> [HighlightsSheetFilter: Int] {
        let (h, a) = await loadRecordsForTesting()
        return AnnotationStreamBuilder.counts(highlights: h, annotations: a)
    }

    /// Runs the load, then returns the card stream for `filter`.
    func loadStreamForTesting(filter: HighlightsSheetFilter) async -> [AnnotationStreamItem] {
        let (h, a) = await loadRecordsForTesting()
        return AnnotationStreamBuilder.stream(highlights: h, annotations: a, filter: filter)
    }

    /// The shared record-load both testing hooks use.
    private func loadRecordsForTesting() async -> ([HighlightRecord], [AnnotationRecord]) {
        let persistence = PersistenceActor(modelContainer: modelContainer)
        let hVM = HighlightListViewModel(
            bookFingerprintKey: bookFingerprintKey,
            store: persistence, totalTextLengthUTF16: nil
        )
        let aVM = AnnotationListViewModel(
            bookFingerprintKey: bookFingerprintKey, store: persistence
        )
        await hVM.loadHighlights()
        await aVM.loadAnnotations()
        return (hVM.highlights, aVM.annotations)
    }
}
#endif
