// Purpose: feature #131 WI-1 — the half-open UTF-16 span value type for the
// Android bilingual interlinear pipeline. Mirrors the iOS half-open
// `Range<Int>` convention used by ChapterSegmenter.sentenceRanges /
// BilingualParagraphRanges: [start, endExclusive) over UTF-16 code units of a
// source string. This is a bilingual SEGMENT span type — NOT a text-selection
// type.
//
// @coordinates-with: ChapterSegmenter.kt (produces spans),
//   dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1)
package com.vreader.app.bilingual

/**
 * A half-open UTF-16 span `[start, endExclusive)` over a source string.
 *
 * `start >= 0` and `endExclusive >= start` are required (an empty span where
 * `endExclusive == start` is legal). Substringing a source with
 * `source.substring(start, endExclusive)` yields the spanned text. This value
 * type carries no source reference, so `endExclusive <= source.length` remains
 * the caller's responsibility at the substring site.
 */
data class Utf16Span(val start: Int, val endExclusive: Int) {
    init {
        require(start >= 0) { "start ($start) must be >= 0" }
        require(endExclusive >= start) {
            "endExclusive ($endExclusive) must be >= start ($start)"
        }
    }

    /** True when the span covers no code units. */
    val isEmpty: Boolean get() = endExclusive == start

    /** Number of UTF-16 code units the span covers. */
    val length: Int get() = endExclusive - start
}
