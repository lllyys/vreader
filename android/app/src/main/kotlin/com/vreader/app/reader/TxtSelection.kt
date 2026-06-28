// Purpose: feature #124 WI-1 — the TXT highlight range type + validation. Ranges are HALF-OPEN
// [startInclusive, endExclusive) in SOURCE UTF-16 coords (the TxtDocument raw-source index space, which
// for TXT equals the rendered space and the resume/anchor space). Half-open (not Kotlin's closed
// IntRange) because getPathForRange/substring are exclusive-end — Gate-2 r2.
package com.vreader.app.reader

/** A half-open UTF-16 range `[startInclusive, endExclusive)` in TXT source coords. */
data class Utf16Range(val startInclusive: Int, val endExclusive: Int) {
    val length: Int get() = endExclusive - startInclusive
    val isEmpty: Boolean get() = endExclusive <= startInclusive
}

object TxtSelection {
    /**
     * A range is valid for persistence iff: in-bounds of [text], non-empty (end > start), non-negative,
     * and neither endpoint splits a UTF-16 surrogate pair (a low surrogate preceded by a high surrogate).
     */
    fun isValid(range: Utf16Range, text: String): Boolean {
        if (range.startInclusive < 0 || range.endExclusive > text.length) return false
        if (range.isEmpty) return false
        if (splitsSurrogate(text, range.startInclusive)) return false
        if (splitsSurrogate(text, range.endExclusive)) return false
        return true
    }

    /** True if [offset] lands between the high and low halves of a surrogate pair. (offset == length is OK.) */
    private fun splitsSurrogate(text: String, offset: Int): Boolean =
        offset in 1 until text.length &&
            Character.isLowSurrogate(text[offset]) && Character.isHighSurrogate(text[offset - 1])
}
