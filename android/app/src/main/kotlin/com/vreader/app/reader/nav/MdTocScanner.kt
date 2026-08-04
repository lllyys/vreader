// Purpose: Markdown chapter detection — walk a decoded `.md` document line by line and emit one
// [DetectedHeading] per ATX or setext heading (feature #139 WI-3). The Kotlin port of iOS
// `TOCBuilder.forMD` (vreader/Services/TOCBuilder.swift:107-216), plus the setext + YAML
// front-matter extensions the #139 row scopes (plan §4.6, divergence D2).
//
// Pipeline: text ──lineStarts──► per-line walk (front matter → fence → blank → ATX → setext)
//                                                              └─► List<DetectedHeading>
//
// Key decisions:
// - Offsets are RAW-SOURCE UTF-16 offsets at the heading LINE's start, leading indent included —
//   never rendered/markup-stripped ones. Everything downstream (the Contents jump, and through it
//   #138's paged `ensureMeasuredThrough` seam) treats them as source offsets, so a display-settings
//   reflow cannot invalidate them. A setext heading's offset is its TITLE line, not the underline.
// - iOS parity where iOS has an opinion: each line is TRIMMED before both the fence and the
//   heading test, so arbitrary leading indentation is legal (deliberately looser than
//   CommonMark's 3-space limit); ATX requires exactly a U+0020 after the hashes (a tab, an NBSP
//   or an ideographic space does NOT qualify); a trailing closing-hash run is stripped only when
//   what remains is non-empty; depth is `hashCount - 1`, i.e. 0-based. The trim set is Swift
//   `CharacterSet.whitespaces` = Zs ∪ {TAB}, spelled out below because Kotlin's
//   `Char.isWhitespace()` disagrees at both ends (excludes NBSP, includes line terminators).
// - Line splitting accepts LF, CRLF and CR — iOS splits on "\n" only, which mis-handles CR-only
//   documents; offsets stay each variant's own source offsets (pinned by test). The one place
//   this port is deliberately better than the original rather than merely equal.
// - Setext (D2, Android-only — iOS has none) and YAML front matter follow plan §4.6; the exact
//   predicates live on the functions below. Both are conservative: anything that does not fully
//   qualify degrades to ordinary Markdown, never to swallowed content.
//
// Known limitations (deliberate, not oversights):
// - This is a LINE scanner, not a CommonMark block parser: a setext underline titles the single
//   preceding line rather than the whole preceding paragraph, and a `---` directly under a list
//   item reads as an underline where CommonMark says thematic break. Both are confined to the
//   Contents list (an odd row at worst); exactness would need a real block parser.
// - No Android imports and no logging: pure CPU work that must stay JVM-unit-testable
//   (`android.util.Log` throws "not mocked" in a plain unit test). Cancellation-cooperative, but
//   it does not hop threads — `TxtMdTocProvider` (WI-4) owns the `withContext(dispatcher)` hop,
//   so this object must not be called on the main thread.
// - Unbounded by design: unlike `TxtTocRuleEngine.extractHeadings` there is no `limit` — the plan
//   pins this signature, an MD heading costs one line of an already-resident document, and WI-4
//   wraps the result for the cap.
//
// @coordinates-with: DetectedHeading.kt, TxtTocRuleEngine.kt, TxtMdTocProvider.kt
package com.vreader.app.reader.nav

import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/** Extracts a Markdown document's heading structure as source-offset-bearing entries. */
object MdTocScanner {

    /**
     * A closing `---` further into the document than this many lines is not front matter.
     *
     * Counted as a zero-based LINE INDEX over the whole document, so the opening `---` occupies
     * index 0 and the last accepted closing position is `MAX_FRONT_MATTER_LINES - 1`. The bound
     * stops a document that merely OPENS with a thematic break from swallowing arbitrary content
     * because another `---` appears much later.
     */
    internal const val MAX_FRONT_MATTER_LINES: Int = 100

    /** Lines walked between cancellation checks. */
    internal const val CANCELLATION_CHECK_INTERVAL: Int = 1024

    /** A YAML mapping entry: `title: Foo`, or a valueless `title:`. */
    private val YAML_MAPPING = Regex("""^\s*[A-Za-z0-9_.\-]+\s*:(\s|$)""")

    /** A YAML sequence entry that is itself a mapping: `- title: Foo`. A bare `- item` is NOT. */
    private val YAML_SEQUENCE_MAPPING = Regex("""^\s*-\s+[A-Za-z0-9_.\-]+\s*:(\s|$)""")

    /**
     * Every heading in [text], in document order.
     *
     * One forward pass holds two pieces of state: the open fence (char + run length), and the
     * previous line when it was an ordinary PARAGRAPH line. A setext underline fires only against
     * that paragraph state, and a blank line, a fence line, a line inside a fence, an ATX heading,
     * a front-matter line and a candidate underline itself all clear it — which is precisely why
     * `---` after any of them stays a thematic break rather than becoming a heading (plan §4.6).
     *
     * @return ATX and setext headings with 0-based [DetectedHeading.depth] and raw-source UTF-16
     *         offsets. Empty for an empty document, a document with no headings, or one whose
     *         headings all live inside fenced code blocks or YAML front matter.
     * @throws kotlinx.coroutines.CancellationException if the calling coroutine is cancelled.
     */
    suspend fun scan(text: String): List<DetectedHeading> {
        coroutineContext.ensureActive()
        if (text.isEmpty()) return emptyList()

        val starts = lineStarts(text)
        val headings = ArrayList<DetectedHeading>()

        var fenceChar: Char? = null
        var fenceLength = 0
        var paragraph: String? = null
        var paragraphOffset = 0
        var sinceCheck = 0

        var index = frontMatterEndExclusive(text, starts)
        while (index < starts.size) {
            if (++sinceCheck >= CANCELLATION_CHECK_INTERVAL) {
                sinceCheck = 0
                coroutineContext.ensureActive()
            }
            val lineStart = starts[index]
            val trimmed = trimmedLine(text, starts, index)
            index++

            val fence = parseFenceLine(trimmed)
            if (fence != null) {
                if (fenceChar == null) {
                    fenceChar = fence.first
                    fenceLength = fence.second
                } else if (fence.first == fenceChar && fence.second >= fenceLength) {
                    fenceChar = null
                    fenceLength = 0
                }
                paragraph = null
                continue
            }
            if (fenceChar != null || trimmed.isEmpty()) {
                paragraph = null
                continue
            }

            val atx = parseAtxHeading(trimmed)
            if (atx != null) {
                headings.add(
                    DetectedHeading(
                        title = atx.second,
                        sourceOffsetUtf16 = lineStart,
                        depth = atx.first,
                    ),
                )
                paragraph = null
                continue
            }

            val underline = setextDepth(trimmed)
            if (underline != null) {
                val title = paragraph
                if (title != null) {
                    headings.add(
                        DetectedHeading(
                            title = title,
                            sourceOffsetUtf16 = paragraphOffset,
                            depth = underline,
                        ),
                    )
                }
                // A candidate underline is never itself a paragraph, whether or not it fired.
                paragraph = null
                continue
            }

            paragraph = trimmed
            paragraphOffset = lineStart
        }

        coroutineContext.ensureActive()
        return headings
    }

    // ------------------------------------------------------------------ lines

    /**
     * The UTF-16 offset of every line start in [text], LF / CRLF / CR alike.
     *
     * Stores offsets rather than substrings so a large document is never copied wholesale; each
     * line's text is materialized one at a time by [trimmedLine]. A document ending in a
     * terminator gets a final empty line, matching iOS's `components(separatedBy:)`.
     */
    private fun lineStarts(text: String): IntArray {
        var count = 1
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (c == '\n') {
                count++
            } else if (c == '\r') {
                count++
                if (i + 1 < text.length && text[i + 1] == '\n') i++
            }
            i++
        }

        val starts = IntArray(count)
        var line = 1
        i = 0
        while (i < text.length) {
            val c = text[i]
            if (c == '\n') {
                starts[line++] = i + 1
            } else if (c == '\r') {
                if (i + 1 < text.length && text[i + 1] == '\n') i++
                starts[line++] = i + 1
            }
            i++
        }
        return starts
    }

    /** Line [index]'s text without its terminator, trimmed the way Swift `.whitespaces` trims. */
    private fun trimmedLine(text: String, starts: IntArray, index: Int): String {
        var end = if (index + 1 < starts.size) starts[index + 1] else text.length
        while (end > starts[index] && (text[end - 1] == '\n' || text[end - 1] == '\r')) end--
        return text.substring(starts[index], end).trim(::isInlineSpace)
    }

    /** Swift `CharacterSet.whitespaces` = Unicode Zs plus CHARACTER TABULATION. */
    private fun isInlineSpace(c: Char): Boolean =
        c == '\t' || Character.getType(c) == Character.SPACE_SEPARATOR.toInt()

    // ------------------------------------------------------------------ front matter

    /**
     * The line index scanning starts at: past a recognized YAML front-matter block, else 0.
     *
     * All three conditions of plan §4.6(1) must hold — first line exactly `---`, a closing `---`
     * within [MAX_FRONT_MATTER_LINES], and at least one YAML-looking line between them. If any
     * fails the block is NOT front matter and the leading `---` is left to the ordinary walk,
     * where it is simply a thematic break.
     */
    private fun frontMatterEndExclusive(text: String, starts: IntArray): Int {
        if (starts.isEmpty() || trimmedLine(text, starts, 0) != FRONT_MATTER_DELIMITER) return 0

        val limit = minOf(starts.size, MAX_FRONT_MATTER_LINES)
        var closing = -1
        var i = 1
        while (i < limit) {
            if (trimmedLine(text, starts, i) == FRONT_MATTER_DELIMITER) {
                closing = i
                break
            }
            i++
        }
        if (closing < 0) return 0

        var looksYaml = false
        var j = 1
        while (j < closing) {
            val line = trimmedLine(text, starts, j)
            if (YAML_MAPPING.find(line) != null || YAML_SEQUENCE_MAPPING.find(line) != null) {
                looksYaml = true
                break
            }
            j++
        }
        return if (looksYaml) closing + 1 else 0
    }

    private const val FRONT_MATTER_DELIMITER = "---"

    // ------------------------------------------------------------------ line classifiers

    /**
     * [trimmed] as a fenced-code delimiter: its marker char and run length, or `null`.
     *
     * iOS parity (`TOCBuilder.parseFenceLine`): the run must be at least 3 long, and a backtick
     * fence's info string may not itself contain a backtick — `` ```kotlin` `` is not a fence.
     */
    private fun parseFenceLine(trimmed: String): Pair<Char, Int>? {
        val first = trimmed.firstOrNull() ?: return null
        if (first != '`' && first != '~') return null
        var count = 0
        while (count < trimmed.length && trimmed[count] == first) count++
        if (count < 3) return null
        if (first == '`' && trimmed.indexOf('`', count) >= 0) return null
        return first to count
    }

    /**
     * [trimmed] as an ATX heading: its 0-based depth and title, or `null`.
     *
     * iOS parity (`TOCBuilder.parseATXHeading`): 1–6 hashes, then literally a U+0020; the title is
     * trimmed; a trailing closing-hash run is dropped only when what is left is non-empty (so
     * `### ###` keeps `###` as its title); an empty title is not a heading.
     */
    private fun parseAtxHeading(trimmed: String): Pair<Int, String>? {
        if (!trimmed.startsWith("#")) return null
        var hashes = 0
        while (hashes < trimmed.length && trimmed[hashes] == '#') hashes++
        if (hashes > 6) return null

        val afterHashes = trimmed.substring(hashes)
        if (!afterHashes.startsWith(" ")) return null

        var title = afterHashes.trim(::isInlineSpace)
        if (title.endsWith("#")) {
            val stripped = title.trimEnd('#').trim(::isInlineSpace)
            if (stripped.isNotEmpty()) title = stripped
        }
        if (title.isEmpty()) return null
        return (hashes - 1) to title
    }

    /**
     * [trimmed] as a setext underline: depth 0 for `=`, depth 1 for `-`, or `null`.
     *
     * The line must be ONE contiguous run of a single marker character (length >= 1 — a lone `-`
     * is a valid underline per CommonMark). Interior whitespace disqualifies it, so `- - -` stays
     * a thematic break.
     */
    private fun setextDepth(trimmed: String): Int? {
        val first = trimmed.firstOrNull() ?: return null
        if (first != '=' && first != '-') return null
        for (c in trimmed) if (c != first) return null
        return if (first == '=') 0 else 1
    }
}
