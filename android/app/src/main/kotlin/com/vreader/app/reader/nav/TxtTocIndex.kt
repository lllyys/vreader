// Purpose: The TXT/MD Contents sheet's current-chapter highlight (feature #139 WI-5) — map the
// reader's live SOURCE offset to the TOC row to highlight. The offset analog of the EPUB chrome's
// `ReaderChromeModel.tocIndexFor` (href + progression), and its exact behavioural mirror: -1 only
// when there is no TOC at all, 0 rather than -1 when a TOC exists but nothing sits at-or-before.
//
// Key decisions:
// - The highlight is COSMETIC, not a navigation target (the jump uses the row's own
//   `canonicalLocator`), so a best-effort row always beats a missing one. That is why an offset
//   before every entry answers 0 instead of -1 — the same trade `tocIndexFor` documents.
// - O(log n) by binary search, not a scan. The Contents list is bounded by
//   [TxtMdTocProvider.MAX_TOC_ENTRIES] (50 000 — Chinese web novels really do reach 20 000–30 000
//   chapters) and this runs on EVERY position change while scrolling, so a linear scan would be
//   50 000 comparisons per frame-ish update. `TxtTocIndexTest.isBinarySearch_not_linear_over50000Entries`
//   counts element reads at that cap and fails a linear implementation.
// - It takes plain `List<Int>` offsets rather than `List<TocEntry>` — the same "extract the
//   comparable key, keep the comparison pure" split `tocPositions` / `tocIndexFor` uses on the EPUB
//   side. No Readium types, no Android runtime, no allocation.
// - Deliberately NOT merged with [BookmarkTocIndex.nearest]'s binary search despite the similar
//   shape: that one answers a DIFFERENT question (which chapter does this bookmark belong to) and
//   must return null before the first entry rather than fabricating chapter 1. Sharing the code
//   would mean sharing an edge-case contract that is correct for neither caller.
//
// @coordinates-with: ../ReaderChromeModel.kt (`tocIndexFor`, the EPUB analog whose contract this
//                    mirrors), TxtMdTocProvider.kt (produces the entries, in document order),
//                    TocSheetRows.kt (renders the returned index as the highlighted row)
package com.vreader.app.reader.nav

/**
 * The index of the TOC row to highlight for a reading position of [currentOffsetUtf16] — the LAST
 * entry starting at-or-before it.
 *
 * @param currentOffsetUtf16 the live reading position as a UTF-16 offset into the raw decoded
 *        document, the same coordinate space [DetectedHeading.sourceOffsetUtf16] and
 *        `txtBookmarkLocator` use. A negative value (no position known yet) is treated as "before
 *        everything".
 * @param entryOffsets one source offset per TOC entry, in list order. **Precondition:** document
 *        order, i.e. non-decreasing — which is what both scanners emit and what
 *        `TxtTocRuleEngineTest` / `TxtMdTocProviderTest` pin. Unsorted input yields an unspecified
 *        (but in-range) row; it cannot throw.
 *
 * Edge behavior — identical to `ReaderChromeModel.tocIndexFor`:
 *  - empty [entryOffsets] → `-1` (there is no row to highlight; the Contents control is hidden
 *    anyway when the TOC is empty);
 *  - a non-empty TOC with no entry at-or-before the position → `0` (highlight the first row; never
 *    `-1` once a TOC exists — a missing highlight is worse than a best-effort first row).
 *
 * When several entries share one offset the LAST of them wins, mirroring `tocIndexFor`'s
 * last-match-wins loop over same-href rows.
 *
 * Pure function of its inputs — no side effects, no platform types.
 */
fun txtTocIndexFor(currentOffsetUtf16: Int, entryOffsets: List<Int>): Int {
    if (entryOffsets.isEmpty()) return -1

    // Rightmost entry whose offset <= the reading position. `<=` (not `<`) is what puts an offset
    // exactly AT a heading's first code unit inside THAT chapter, and what makes a run of equal
    // offsets resolve to its last member.
    var lo = 0
    var hi = entryOffsets.size - 1
    var found = -1
    while (lo <= hi) {
        val mid = (lo + hi) ushr 1 // ushr, not /2: overflow-safe for any in-range index pair.
        if (entryOffsets[mid] <= currentOffsetUtf16) {
            found = mid
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return if (found >= 0) found else 0
}
