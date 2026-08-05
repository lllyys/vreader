// Purpose: the AZW3 Contents sheet's current-chapter highlight (feature #140 WI-4) — map foliate's
// live `relocate.tocHref` to the TOC row to highlight. The href analog of `txtTocIndexFor`'s offset
// mapping, and the exact behavioural mirror of the EPUB chrome's `ReaderChromeModel.tocIndexFor`:
// -1 only when there is no TOC at all, 0 rather than -1 whenever a TOC exists but nothing matches.
//
// Key decisions:
// - The engine already answered the question. foliate's own TOCProgress resolves the current
//   `tocItem` over the same SOURCE TOC whose href values were serialized to us (serializeTOC maps it
//   into fresh objects, but the href strings are the ones we hold), and posts that href on every
//   relocate (foliate-bundle.js:7048). This maps that href back to a row index; it does not re-derive the
//   chapter from fractions, which would be a second, worse implementation that drifts from what the
//   renderer believes.
// - Matching is EXACT STRING EQUALITY on the decoded href — precisely: Kotlin `String.equals`, i.e.
//   UTF-16 code-unit equality after the JSON decoding both sides already went through, with NO
//   application-level transformation of any kind (no trimming, no case folding, no
//   percent-encode/decode, no fragment/query stripping, no Unicode normalization — NFC and NFD stay
//   distinct). This is what the plan calls "byte-exact": FoliateTocParser preserves hrefs verbatim
//   precisely so this comparison works, and two rows differing only by `#fragment`, `?query`, an
//   accent's composition or the KF8 `:off:` segment are genuinely DISTINCT chapters — normalizing
//   would silently collapse them onto one highlight.
// - Last match wins. A part and its first chapter legitimately share one href in a real NCX; the
//   deepest row is the one the reader is actually in. Same rule as `tocIndexFor`'s exact-href loop
//   (which overwrites) and `txtTocIndexFor`'s equal-offset run.
// - The highlight is COSMETIC, not a navigation target (the jump uses the row's own
//   `canonicalLocator`), so a best-effort row always beats a missing one — hence 0, not -1, for an
//   unknown or unmatched href.
// - A linear scan, deliberately: hrefs have no order to binary-search, the list is capped at
//   FoliateTocParser.MAX_TOC_ENTRIES (10 000) and this runs once per relocate (a page turn), not per
//   frame. It takes plain `List<String?>` rather than `List<TocEntry>` — the same "extract the
//   comparable key, keep the comparison pure" split `tocPositions` / `tocIndexFor` uses on the EPUB
//   side. No Readium types, no Android runtime, no allocation.
//
// @coordinates-with: ../ReaderChromeModel.kt (`tocIndexFor`, the EPUB analog whose contract this
//                    mirrors), TxtTocIndex.kt (the TXT/MD analog), ../foliate/FoliateTocParser.kt
//                    (produces the verbatim hrefs), ../foliate/FoliateMessage.kt
//                    (`Relocate.tocHref`, the live position), TocSheetRows.kt (renders the returned
//                    index as the highlighted row)
package com.vreader.app.reader.nav

/**
 * The index of the TOC row to highlight for a reading position whose foliate TOC href is
 * [currentTocHref] — the LAST entry whose href is EXACTLY equal to it (`String.equals`; no trimming,
 * case folding, percent-decoding, fragment/query stripping or Unicode normalization is applied).
 *
 * @param currentTocHref `relocate.tocHref` as foliate posted it, already normalized to `null` by
 *        [com.vreader.app.reader.foliate.FoliateMessageParser] when absent, blank or wrong-typed.
 *        `null` means "the current chapter is unknown", NOT "there is no TOC".
 * @param entryHrefs one href per TOC row, in row order — `null` for a row that carries none (a
 *        `Locator.href` is nullable), which simply never matches. No ordering precondition: unlike
 *        [txtTocIndexFor] this compares for equality, not order.
 *
 * Edge behavior — identical to `ReaderChromeModel.tocIndexFor`:
 *  - empty [entryHrefs] → `-1` (there is no row to highlight; the Contents control is hidden anyway
 *    when the TOC is empty);
 *  - a non-empty TOC with an unknown (`null`) or unmatched href → `0` (highlight the first row;
 *    never `-1` once a TOC exists — a missing highlight is worse than a best-effort first row).
 *
 * Pure function of its inputs — no side effects, no platform types.
 */
fun foliateTocIndexFor(currentTocHref: String?, entryHrefs: List<String?>): Int {
    if (entryHrefs.isEmpty()) return -1
    if (currentTocHref == null) return 0

    // Last-match-wins, mirroring `tocIndexFor`'s overwriting exact-href loop: a parent and its first
    // child share an href, and the deeper row is the truer answer.
    var found = -1
    entryHrefs.forEachIndexed { index, href ->
        if (href == currentTocHref) found = index
    }
    return if (found >= 0) found else 0
}
