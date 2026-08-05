// Purpose: Markdown (.md) line-chunk renderer — feature #112 (#110 Phase 3). Renders ONE
// TxtDocument line-chunk's text as a Compose AnnotatedString styling a bounded v1
// CommonMark subset: ATX headers (`#`..`######`), `**bold**` / `*italic*` / `_italic_` /
// `***both***`, `` `inline code` ``, and `- `/`* ` bullet prefixes. Unknown/multi-line
// constructs degrade to literal text (no crash). v1 is a SINGLE-LINE subset because
// TxtDocument is line-chunked.
//
// feature #125: `renderWithMap` ALSO emits, per rendered char, the SOURCE span
// [srcStart[r], srcEnd[r]) of the source chars that produced it (dual-affinity, so a stripped
// marker between two visible runs doesn't collapse their distinct source positions). `render()`
// delegates to `renderWithMap(chunk).text` — same rendered text + spans.
// The parser parses `content` by ABSOLUTE index (no substrings) so each appended char records its
// source index directly; helpers are range-bounded.
//
// feature #129 WI-4: heading SpanStyle sizes are EM-RELATIVE (ratio to the 18sp default body size),
// not absolute sp, so headings scale with the reader's Display font-size setting — and the render
// stays settings-independent (the ChunkTextMapper cache never needs invalidating on a settings change).
//
// Pure JVM (value types) so the spans + map are unit-testable. Resume/anchor offsets index the RAW
// markdown source, not these rendered spans — the map bridges the two for highlighting.
//
// feature #156 WI-1: `isHeadingChunk` exposes the SAME ATX predicate the heading branch uses, so the
// scroll body can leave a wrapping Markdown heading unjustified while body prose justifies. Paged mode
// cannot use it — TxtPaginator.renderPage concatenates several chunks into ONE AnnotatedString rendered
// by ONE Text, which carries a single paragraph alignment (plan §5.2b, a stated known limitation).
//
// @coordinates-with: TxtReaderActivity.kt (renders + maps MD chunks), TxtReaderBody.kt (the scroll body
//   reads isHeadingChunk for the #156 alignment branch), MarkdownOffsetMap.kt (#125 WI-2
//   consumes srcStart/srcEnd), TxtDocument.kt (the line-chunk source),
//   settings/ReaderTextStyles.kt (chunkTextAlign — the alignment this predicate selects).
package com.vreader.app.reader

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em

/** A rendered chunk + the per-rendered-char source spans (`srcStart[r]..srcEnd[r]`). */
data class MarkdownRendered(val text: AnnotatedString, val srcStart: IntArray, val srcEnd: IntArray) {
    // data class with arrays — value equality by content (for tests).
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is MarkdownRendered) return false
        return text == other.text && srcStart.contentEquals(other.srcStart) && srcEnd.contentEquals(other.srcEnd)
    }
    override fun hashCode(): Int = (text.hashCode() * 31 + srcStart.contentHashCode()) * 31 + srcEnd.contentHashCode()
}

object MarkdownRenderer {

    // H1..H6 sizes in sp AT the 18sp default body size; emitted as EM ratios (size/18) so heading
    // spans scale with the reader's font-size setting (feature #129 WI-4) — the body Text's fontSize
    // is the em base.
    private val HEADING_SIZES = floatArrayOf(26f, 22f, 19f, 17f, 16f, 15f)
    private const val BODY_BASE_SP = 18f
    private val ATX = Regex("""^(#{1,6})[ \t]+.*$""")
    private val ESCAPABLE = setOf('*', '_', '`', '\\', '#', '-')

    /** Render one line-chunk's text (unchanged #112 output). */
    fun render(chunk: String): AnnotatedString = renderWithMap(chunk).text

    /**
     * Whether [chunk] is an ATX heading line (feature #156 WI-1) — the predicate the SCROLL body's
     * alignment branch reads so a WRAPPING heading is not justified like body prose. It shares
     * [contentEndOf] and [ATX] with [renderWithMap], so the two cannot drift: a chunk this calls a
     * heading is exactly a chunk the renderer takes down the heading branch (pinned by
     * `MarkdownRendererTest.isHeadingChunk_agreesWithWhatTheRendererActuallyStyles`).
     *
     * `"# "` (no heading text) is ATX-shaped and answers `true`, though the renderer emits no span and
     * no glyphs for it — with nothing rendered there is nothing to align either way.
     */
    fun isHeadingChunk(chunk: String): Boolean {
        val contentEnd = contentEndOf(chunk)
        if (contentEnd == 0) return false
        return ATX.matchEntire(chunk.substring(0, contentEnd)) != null
    }

    /** The chunk length with its trailing line terminator(s) excluded — the parsed content extent. */
    private fun contentEndOf(chunk: String): Int {
        var contentEnd = chunk.length
        while (contentEnd > 0 && (chunk[contentEnd - 1] == '\n' || chunk[contentEnd - 1] == '\r')) contentEnd--
        return contentEnd
    }

    /** Render + the per-rendered-char source-span map. */
    fun renderWithMap(chunk: String): MarkdownRendered {
        val contentEnd = contentEndOf(chunk)

        val b = MapBuilder()
        if (contentEnd > 0) {
            val heading = ATX.matchEntire(chunk.substring(0, contentEnd))
            when {
                heading != null -> {
                    val level = heading.groupValues[1].length  // 1..6
                    var textStart = level
                    while (textStart < contentEnd && (chunk[textStart] == ' ' || chunk[textStart] == '\t')) textStart++
                    val styleStart = b.length
                    b.parseInline(chunk, textStart, contentEnd)
                    if (b.length > styleStart) {
                        b.addStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = (HEADING_SIZES[level - 1] / BODY_BASE_SP).em), styleStart, b.length)
                    }
                }
                isBullet(chunk, contentEnd) -> {
                    // "- "/"* " → "• " ; both inserted glyphs map to the source bullet marker span [0,2).
                    b.appendInserted('•', 0, 2)
                    b.appendInserted(' ', 0, 2)
                    b.parseInline(chunk, 2, contentEnd)
                }
                else -> b.parseInline(chunk, 0, contentEnd)
            }
        }
        // trailing EOL — 1:1 to source
        for (k in contentEnd until chunk.length) b.appendSource(chunk, k)
        return b.build()
    }

    /** `- ` or `* ` at the very start of the content. */
    private fun isBullet(s: String, end: Int): Boolean =
        end >= 2 && (s[0] == '-' || s[0] == '*') && (s[1] == ' ' || s[1] == '\t')

    /** Inline pass over `content[start until end]` (absolute indices). */
    private fun MapBuilder.parseInline(s: String, start: Int, end: Int) {
        var i = start
        while (i < end) {
            val c = s[i]
            i = when {
                c == '\\' && i + 1 < end && s[i + 1] in ESCAPABLE -> { appendSpan(s[i + 1], i, i + 2); i + 2 }
                c == '`' -> parseCode(s, i, end)
                c == '*' -> parseStar(s, i, end)
                c == '_' -> parseUnderscore(s, i, end)
                else -> { appendSource(s, i); i + 1 }
            }
        }
    }

    private fun MapBuilder.parseCode(s: String, i: Int, end: Int): Int {
        val close = indexOf(s, '`', i + 1, end)
        if (close == -1) { appendSource(s, i); return i + 1 }
        val start = length
        for (k in i + 1 until close) appendSource(s, k)
        addStyle(SpanStyle(fontFamily = FontFamily.Monospace), start, length)
        return close + 1
    }

    private fun MapBuilder.parseStar(s: String, i: Int, end: Int): Int {
        val run = (i until end).takeWhile { s[it] == '*' }.count().coerceAtMost(3)
        val marker = "*".repeat(run)
        val close = findUnescaped(s, i + run, end, marker)
        if (close == -1) { for (k in i until i + run) appendSource(s, k); return i + run }
        if (close == i + run) { for (k in i until i + run) appendSource(s, k); return i + run }  // empty inner → literal
        val start = length
        parseInline(s, i + run, close)
        when (run) {
            1 -> addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, length)
            2 -> addStyle(SpanStyle(fontWeight = FontWeight.Bold), start, length)
            else -> { addStyle(SpanStyle(fontWeight = FontWeight.Bold), start, length); addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, length) }
        }
        return close + run
    }

    private fun MapBuilder.parseUnderscore(s: String, i: Int, end: Int): Int {
        val run = (i until end).takeWhile { s[it] == '_' }.count()
        if (run != 1) { for (k in i until i + run) appendSource(s, k); return i + run }
        val canOpen = i == 0 || !s[i - 1].isLetterOrDigit()
        if (!canOpen) { appendSource(s, i); return i + 1 }
        var j = i + 1
        while (j < end) {
            if (s[j] == '_' && !isEscaped(s, j, i)) {
                val canClose = j + 1 >= end || !s[j + 1].isLetterOrDigit()
                if (canClose && j > i + 1) break
            }
            j++
        }
        if (j >= end) { appendSource(s, i); return i + 1 }
        val start = length
        parseInline(s, i + 1, j)
        addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, length)
        return j + 1
    }

    /** Index of [ch] in `s[from until end)`, or -1. */
    private fun indexOf(s: String, ch: Char, from: Int, end: Int): Int {
        for (k in from until end) if (s[k] == ch) return k
        return -1
    }

    /** Index of [marker] (unescaped) at/after [from], within `[from, end)`, or -1. */
    private fun findUnescaped(s: String, from: Int, end: Int, marker: String): Int {
        var idx = from
        val ml = marker.length
        while (idx + ml <= end) {
            if (s.regionMatches(idx, marker, 0, ml) && !isEscaped(s, idx, from)) return idx
            idx++
        }
        return -1
    }

    /** True if the char at [pos] is preceded by an ODD run of backslashes, not counting below [lowerBound]. */
    private fun isEscaped(s: String, pos: Int, lowerBound: Int): Boolean {
        var backslashes = 0
        var k = pos - 1
        while (k >= lowerBound && s[k] == '\\') { backslashes++; k-- }
        return backslashes % 2 == 1
    }

    /** Builds the rendered AnnotatedString + the parallel per-char source spans. */
    private class MapBuilder {
        private val sb = AnnotatedString.Builder()
        private val ss = ArrayList<Int>()
        private val se = ArrayList<Int>()
        val length: Int get() = sb.length
        /** Append `content[k]` (one rendered char from source [k, k+1)). */
        fun appendSource(content: String, k: Int) { sb.append(content[k]); ss.add(k); se.add(k + 1) }
        /** Append a single char that came from the source span [from, to) (escape: 2 source → 1 rendered). */
        fun appendSpan(ch: Char, from: Int, to: Int) { sb.append(ch); ss.add(from); se.add(to) }
        /** Append an INSERTED glyph (no direct source char) mapped to source span [from, to). */
        fun appendInserted(ch: Char, from: Int, to: Int) { sb.append(ch); ss.add(from); se.add(to) }
        fun addStyle(style: SpanStyle, start: Int, end: Int) { sb.addStyle(style, start, end) }
        fun build(): MarkdownRendered = MarkdownRendered(sb.toAnnotatedString(), ss.toIntArray(), se.toIntArray())
    }
}
