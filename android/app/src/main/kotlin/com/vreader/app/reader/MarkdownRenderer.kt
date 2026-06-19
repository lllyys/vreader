// Purpose: Markdown (.md) line-chunk renderer — feature #112 (#110 Phase 3). Renders ONE
// TxtDocument line-chunk's text as a Compose AnnotatedString styling a bounded v1
// CommonMark subset: ATX headers (`#`..`######`), `**bold**` / `*italic*` / `_italic_` /
// `***both***`, `` `inline code` ``, and `- `/`* ` bullet prefixes. Unknown/multi-line
// constructs degrade to literal text (no crash). v1 is a SINGLE-LINE subset because
// TxtDocument is line-chunked — fenced code, multi-line lists, continuation paragraphs,
// and emphasis spanning a newline are OUT of scope and render verbatim.
//
// Pure JVM (returns AnnotatedString, a Compose value type) so the span ranges are
// unit-testable. Resume is unaffected: TxtDocument offsets index the RAW markdown source,
// not these rendered spans.
//
// @coordinates-with: TxtReaderActivity.kt (calls render() per chunk when format == md),
//   TxtDocument.kt (the line-chunk source).
package com.vreader.app.reader

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

object MarkdownRenderer {

    private val HEADING_SIZES = floatArrayOf(26f, 22f, 19f, 17f, 16f, 15f)  // H1..H6
    private val ATX = Regex("""^(#{1,6})[ \t]+(.*)$""")

    /** Render one line-chunk's text. The trailing line terminator (if any) is preserved
     *  verbatim so paragraph spacing matches the plain-text path. */
    fun render(chunk: String): AnnotatedString {
        // Split off the trailing EOL run — markdown applies to the line content only.
        var end = chunk.length
        while (end > 0 && (chunk[end - 1] == '\n' || chunk[end - 1] == '\r')) end--
        val content = chunk.substring(0, end)
        val eol = chunk.substring(end)

        return buildAnnotatedString {
            when {
                content.isEmpty() -> {}
                else -> {
                    val heading = ATX.matchEntire(content)
                    when {
                        heading != null -> {
                            val level = heading.groupValues[1].length  // 1..6
                            val text = heading.groupValues[2]
                            val start = length
                            parseInline(text)
                            if (length > start) {
                                addStyle(
                                    SpanStyle(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = HEADING_SIZES[level - 1].sp,
                                    ),
                                    start, length,
                                )
                            }
                        }
                        isBullet(content) -> {
                            append("• ")  // "• "
                            parseInline(content.substring(2))
                        }
                        else -> parseInline(content)
                    }
                }
            }
            if (eol.isNotEmpty()) append(eol)
        }
    }

    /** `- ` or `* ` at the very start (single-line bullet). */
    private fun isBullet(s: String): Boolean =
        s.length >= 2 && (s[0] == '-' || s[0] == '*') && (s[1] == ' ' || s[1] == '\t')

    /**
     * Inline pass: code spans (which suppress emphasis), `**`/`*`/`***` and non-intraword
     * `_` emphasis, and backslash escapes. An unmatched delimiter is emitted literally.
     */
    private fun AnnotatedString.Builder.parseInline(s: String) {
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                c == '\\' && i + 1 < s.length && s[i + 1] in ESCAPABLE -> {
                    append(s[i + 1]); i += 2
                }
                c == '`' -> i = parseCode(s, i)
                c == '*' -> i = parseStar(s, i)
                c == '_' -> i = parseUnderscore(s, i)
                else -> { append(c); i++ }
            }
        }
    }

    /** Inline code `` `…` `` — monospace, backticks dropped, contents raw (no emphasis). */
    private fun AnnotatedString.Builder.parseCode(s: String, i: Int): Int {
        val close = s.indexOf('`', i + 1)
        if (close == -1) { append('`'); return i + 1 }
        val start = length
        append(s.substring(i + 1, close))
        addStyle(SpanStyle(fontFamily = FontFamily.Monospace), start, length)
        return close + 1
    }

    /** `***`/`**`/`*` emphasis. Run length decides bold / italic / both. */
    private fun AnnotatedString.Builder.parseStar(s: String, i: Int): Int {
        val run = (i until s.length).takeWhile { s[it] == '*' }.count().coerceAtMost(3)
        val marker = "*".repeat(run)
        val close = findUnescaped(s, i + run, marker)
        if (close == -1) { append(marker); return i + run }
        val inner = s.substring(i + run, close)
        // Empty inner (`******`, `before ****** after`) is NOT emphasis — degrade to
        // literal so visible separator runs aren't dropped (Gate-4 Medium).
        if (inner.isEmpty()) { append(marker); return i + run }
        val start = length
        parseInline(inner)
        when (run) {
            1 -> addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, length)
            2 -> addStyle(SpanStyle(fontWeight = FontWeight.Bold), start, length)
            else -> {
                addStyle(SpanStyle(fontWeight = FontWeight.Bold), start, length)
                addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, length)
            }
        }
        return close + run
    }

    /** `_italic_` — single underscore only, and only when not intraword (the CommonMark
     *  left/right-flanking rule). A run of 2+ underscores (`__bold__`) is literal in v1. */
    private fun AnnotatedString.Builder.parseUnderscore(s: String, i: Int): Int {
        val run = (i until s.length).takeWhile { s[it] == '_' }.count()
        if (run != 1) { append("_".repeat(run)); return i + run }  // __bold__ etc. → literal (v1)
        val canOpen = i == 0 || !s[i - 1].isLetterOrDigit()
        if (!canOpen) { append('_'); return i + 1 }
        var j = i + 1
        while (j < s.length) {
            // A `\_` is escaped — not a closing delimiter (Gate-4 Low).
            if (s[j] == '_' && !isEscaped(s, j)) {
                val canClose = j + 1 >= s.length || !s[j + 1].isLetterOrDigit()
                if (canClose && j > i + 1) break
            }
            j++
        }
        if (j >= s.length) { append('_'); return i + 1 }  // unmatched → literal
        val inner = s.substring(i + 1, j)
        val start = length
        parseInline(inner)
        addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, length)
        return j + 1
    }

    /** Index of [marker] at/after [from] that is NOT backslash-escaped, or -1. */
    private fun findUnescaped(s: String, from: Int, marker: String): Int {
        var idx = s.indexOf(marker, from)
        while (idx != -1) {
            if (!isEscaped(s, idx)) return idx
            idx = s.indexOf(marker, idx + 1)
        }
        return -1
    }

    /** True if the char at [pos] is preceded by an ODD run of backslashes (escaped). */
    private fun isEscaped(s: String, pos: Int): Boolean {
        var backslashes = 0
        var k = pos - 1
        while (k >= 0 && s[k] == '\\') { backslashes++; k-- }
        return backslashes % 2 == 1
    }

    private val ESCAPABLE = setOf('*', '_', '`', '\\', '#', '-')
}
