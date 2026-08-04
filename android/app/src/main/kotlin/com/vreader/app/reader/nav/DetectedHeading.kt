// Purpose: The format-neutral intermediate every TXT/MD table-of-contents scanner emits
// (feature #139 WI-2), plus the bounded result wrapper extraction returns.
//
// Key decisions:
// - `sourceOffsetUtf16` is an offset into the RAW decoded document text, in UTF-16 code units,
//   pointing at the heading LINE's first code unit (leading indent included). It is deliberately
//   NOT a rendered/paginated offset: the whole point is that a display-settings reflow cannot
//   invalidate it, and that it feeds `txtBookmarkLocator` / `jumpToOffset` unchanged.
// - `depth` is 0-based. TXT is always flat (plan §4.3 — the single-winning-rule model cannot tell
//   卷 from 章, and the real book's 卷 headings are interleaved out of order); MD carries real
//   heading levels.
// - [ExtractResult] carries `hitLimit` rather than an over-cap list so a caller can REJECT a
//   pathological document without the scan ever materializing it (plan §4.4 / Gate-2 R2).
//
// @coordinates-with: TxtTocRuleEngine.kt, MdTocScanner.kt, TxtMdTocProvider.kt
package com.vreader.app.reader.nav

/**
 * One detected heading, before it becomes a [TocEntry].
 *
 * @param title             the heading text, already trimmed. Never blank — a match whose text
 *                          trims to nothing is dropped rather than emitted.
 * @param sourceOffsetUtf16 UTF-16 offset of the heading LINE's start in the raw document text.
 *                          Guaranteed to be a code-point boundary (never inside a surrogate pair).
 * @param depth             0-based nesting level; TXT is always 0.
 */
data class DetectedHeading(
    val title: String,
    val sourceOffsetUtf16: Int,
    val depth: Int = 0,
)

/**
 * The outcome of a bounded extraction pass.
 *
 * @param headings  the headings found, in document order; never longer than the caller's `limit`.
 * @param hitLimit  `true` when collection STOPPED because `limit` was reached. Callers pass
 *                  `cap + 1` so this reads exactly as "the document has more than `cap` headings",
 *                  which is the reject-don't-truncate signal (a silently truncated Contents list
 *                  is worse than none — the user cannot tell it is incomplete).
 */
data class ExtractResult(
    val headings: List<DetectedHeading>,
    val hitLimit: Boolean,
) {
    companion object {
        /** Nothing found, nothing truncated — the empty-document / unusable-rule outcome. */
        val EMPTY = ExtractResult(emptyList(), hitLimit = false)
    }
}
