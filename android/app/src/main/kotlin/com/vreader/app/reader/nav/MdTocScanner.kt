// Purpose: Markdown chapter detection — walk a decoded `.md` document line by line and emit one
// [DetectedHeading] per ATX or setext heading (feature #139 WI-3). The Kotlin port of iOS
// `TOCBuilder.forMD` (vreader/Services/TOCBuilder.swift:107-216), plus the setext + YAML
// front-matter extensions the #139 row scopes (plan §4.6, divergence D2).
//
// Pipeline: text ──streaming line walk (front matter → fence → blank → ATX → setext)──► ExtractResult
//
// Key decisions:
// - Offsets are RAW-SOURCE UTF-16 offsets at the heading LINE's start, indent included — never
//   rendered/markup-stripped ones. Everything downstream (the Contents jump, and through it #138's
//   paged `ensureMeasuredThrough` seam) treats them as source offsets, so a display-settings
//   reflow cannot invalidate them. A setext heading's offset is its TITLE line, not the underline.
// - iOS parity where iOS has an opinion: TRIM the line before both the fence and the heading test
//   (so arbitrary leading indentation is legal — looser than CommonMark's 3 spaces); ATX needs
//   exactly a U+0020 after the hashes (tab / NBSP / U+3000 do NOT qualify); the closing-hash strip
//   is guarded; depth is `hashCount - 1`. The trim set is Swift `CharacterSet.whitespaces` =
//   Zs ∪ {TAB}, spelled out below because Kotlin's `Char.isWhitespace()` disagrees at both ends.
// - Line splitting accepts LF, CRLF and CR — iOS splits on "\n" only, which mis-handles CR-only
//   documents; offsets stay each variant's own source offsets (pinned by test).
// - Setext (D2, Android-only — iOS has none) and YAML front matter follow plan §4.6; the exact
//   predicates live on the functions below. Both are conservative: anything that does not fully
//   qualify degrades to ordinary Markdown, never to swallowed content.
// - BOUNDED BEFORE MATERIALIZATION like `TxtTocRuleEngine.extractHeadings`: the walk takes a
//   `limit`, returns [ExtractResult], and stops the moment it has that many headings (plan §4.4).
//   Classification is RANGE-based — lines are tested through `(from, to)` indices — so the only
//   string allocated is a heading TITLE about to be emitted (plus one bounded front-matter probe),
//   and even a multi-megabyte document with no terminator at all is classified without a copy.
//
// Known limitations (deliberate, not oversights):
// - This is a LINE scanner, not a CommonMark block parser: a setext underline titles the single
//   preceding line rather than the whole preceding paragraph, and a `---` directly under a list
//   item reads as an underline where CommonMark says thematic break. Both are confined to the
//   Contents list (an odd row at worst); exactness would need a real block parser.
// - No Android imports and no logging: pure CPU work that must stay JVM-unit-testable
//   (`android.util.Log` throws "not mocked" in a plain unit test). It does not hop threads —
//   `TxtMdTocProvider` (WI-4) owns the `withContext(dispatcher)` hop, so never call this on the
//   main thread. Cancellation is observed every [CANCELLATION_CHECK_INTERVAL] lines and, inside a
//   line, every [CANCELLATION_CHECK_UNITS] code units — EVERY traversal that can run a line's
//   length (the terminator scan, both trims, the fence/hash/underline runs) goes through the one
//   checked `walkForward`/`walkBackward` pair, so one enormous line cannot defer a cancel either.
//
// @coordinates-with: DetectedHeading.kt, TxtTocRuleEngine.kt, TxtMdTocProvider.kt
package com.vreader.app.reader.nav

import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/** Extracts a Markdown document's heading structure as source-offset-bearing entries. */
object MdTocScanner {

    /**
     * A closing `---` further into the document than this many lines is not front matter. Counted
     * as a zero-based LINE INDEX, so the opening `---` is index 0 and the last accepted closing
     * position is `MAX_FRONT_MATTER_LINES - 1`. The bound stops a document that merely OPENS with
     * a thematic break from swallowing arbitrary content because another `---` appears far later.
     */
    internal const val MAX_FRONT_MATTER_LINES: Int = 100

    /**
     * A front-matter line longer than this is never tested for YAML shape — the probes are the one
     * place a `Regex` needs a real `String`, so what may be copied is bounded here rather than by
     * the document. A 4 KB metadata key is not YAML anybody wrote, and calling it "not YAML-like"
     * only ever degrades toward scanning the block as ordinary Markdown.
     */
    internal const val MAX_FRONT_MATTER_LINE_LENGTH: Int = 4096

    /** Lines walked between cancellation checks. */
    internal const val CANCELLATION_CHECK_INTERVAL: Int = 1024

    /** UTF-16 code units walked WITHIN one line between cancellation checks. */
    internal const val CANCELLATION_CHECK_UNITS: Int = 8192

    /** A YAML mapping entry: `title: Foo`, or a valueless `title:`. */
    private val YAML_MAPPING = Regex("""^\s*[A-Za-z0-9_.\-]+\s*:(\s|$)""")

    /** A YAML sequence entry that is itself a mapping: `- title: Foo`. A bare `- item` is NOT. */
    private val YAML_SEQUENCE_MAPPING = Regex("""^\s*-\s+[A-Za-z0-9_.\-]+\s*:(\s|$)""")

    /**
     * Every heading in [text], in document order, stopping early at [limit].
     *
     * One forward pass holds two pieces of state: the open fence (char + run length), and the
     * previous line's trimmed RANGE when it was an ordinary PARAGRAPH line. A setext underline
     * fires only against that paragraph state, and a blank line, a fence line, a line inside a
     * fence, an ATX heading, a front-matter line and a candidate underline itself all clear it —
     * which is precisely why `---` after any of them stays a thematic break (plan §4.6).
     *
     * @param limit the maximum number of headings to collect; must be positive. Callers pass
     *              `cap + 1` so [ExtractResult.hitLimit] reads as "more than `cap` headings
     *              exist" (plan §4.4). Deliberately has no default, matching
     *              [TxtTocRuleEngine.extractHeadings]: every call site states its own budget.
     * @return ATX and setext headings with 0-based [DetectedHeading.depth] and raw-source UTF-16
     *         offsets. Empty for an empty document, one with no headings, or one whose headings
     *         all live inside fenced code blocks or YAML front matter.
     * @throws IllegalArgumentException if [limit] is not positive.
     * @throws kotlinx.coroutines.CancellationException if the calling coroutine is cancelled.
     */
    suspend fun scan(text: String, limit: Int): ExtractResult {
        require(limit > 0) { "limit must be positive, was $limit" }
        coroutineContext.ensureActive()
        if (text.isEmpty()) return ExtractResult.EMPTY

        val headings = ArrayList<DetectedHeading>()
        var fenceChar: Char? = null
        var fenceLength = 0
        var paragraphFrom = -1
        var paragraphTo = -1
        var paragraphOffset = 0
        var sinceCheck = 0

        var lineStart = frontMatterEndOffset(text)
        while (lineStart >= 0) {
            if (++sinceCheck >= CANCELLATION_CHECK_INTERVAL) {
                sinceCheck = 0
                coroutineContext.ensureActive()
            }
            val contentEnd = contentEnd(text, lineStart)
            val from = trimmedStart(text, lineStart, contentEnd)
            val to = trimmedEnd(text, from, contentEnd)
            val thisLineStart = lineStart
            lineStart = nextLineStart(text, contentEnd)

            val fenceRun = fenceRunLength(text, from, to)
            if (fenceRun > 0) {
                if (fenceChar == null) {
                    fenceChar = text[from]
                    fenceLength = fenceRun
                } else if (text[from] == fenceChar && fenceRun >= fenceLength) {
                    fenceChar = null
                    fenceLength = 0
                }
                paragraphFrom = -1
                continue
            }
            if (fenceChar != null || from == to) {
                paragraphFrom = -1
                continue
            }

            val atx = parseAtxHeading(text, from, to)
            if (atx != null) {
                headings.add(DetectedHeading(atx.second, thisLineStart, atx.first))
                if (headings.size == limit) return ExtractResult(headings, hitLimit = true)
                paragraphFrom = -1
                continue
            }

            val underline = setextDepth(text, from, to)
            if (underline != null) {
                if (paragraphFrom >= 0) {
                    val title = text.substring(paragraphFrom, paragraphTo)
                    headings.add(DetectedHeading(title, paragraphOffset, underline))
                    if (headings.size == limit) return ExtractResult(headings, hitLimit = true)
                }
                // A candidate underline is never itself a paragraph, whether or not it fired.
                paragraphFrom = -1
                continue
            }

            paragraphFrom = from
            paragraphTo = to
            paragraphOffset = thisLineStart
        }

        coroutineContext.ensureActive()
        return ExtractResult(headings, hitLimit = false)
    }

    // ------------------------------------------------------------------ line walking

    /**
     * The first index at or after [from] (and before [to]) whose char fails [predicate], or [to].
     *
     * THE shared walk: every traversal in this file that can run the length of a line goes through
     * it, so the cancellation check lives in exactly one place and no single enormous line — a
     * terminator-free document is one line — can defer a cancel past
     * [CANCELLATION_CHECK_UNITS] code units.
     */
    private suspend fun walkForward(
        text: String,
        from: Int,
        to: Int,
        predicate: (Char) -> Boolean,
    ): Int {
        var i = from
        var sinceCheck = 0
        while (i < to && predicate(text[i])) {
            if (++sinceCheck >= CANCELLATION_CHECK_UNITS) {
                sinceCheck = 0
                coroutineContext.ensureActive()
            }
            i++
        }
        return i
    }

    /** [walkForward]'s mirror: the first index walking back from [to] whose char fails. */
    private suspend fun walkBackward(
        text: String,
        from: Int,
        to: Int,
        predicate: (Char) -> Boolean,
    ): Int {
        var i = to
        var sinceCheck = 0
        while (i > from && predicate(text[i - 1])) {
            if (++sinceCheck >= CANCELLATION_CHECK_UNITS) {
                sinceCheck = 0
                coroutineContext.ensureActive()
            }
            i--
        }
        return i
    }

    /** The offset just past line-[start]'s own text: its terminator, or the end of the document. */
    private suspend fun contentEnd(text: String, start: Int): Int =
        walkForward(text, start, text.length) { it != '\n' && it != '\r' }

    /**
     * The start of the line after the one whose content ends at [contentEnd], or `-1` when that
     * line was the document's last. LF, CRLF and CR are all one terminator, so a document ending
     * WITH one yields a final empty line — as iOS's `components(separatedBy:)` does — then -1.
     */
    private fun nextLineStart(text: String, contentEnd: Int): Int {
        if (contentEnd >= text.length) return -1
        val crlf = text[contentEnd] == '\r' &&
            contentEnd + 1 < text.length &&
            text[contentEnd + 1] == '\n'
        return contentEnd + if (crlf) 2 else 1
    }

    private suspend fun trimmedStart(text: String, from: Int, to: Int): Int =
        walkForward(text, from, to) { isInlineSpace(it) }

    private suspend fun trimmedEnd(text: String, from: Int, to: Int): Int =
        walkBackward(text, from, to) { isInlineSpace(it) }

    /** Swift `CharacterSet.whitespaces` = Unicode Zs plus CHARACTER TABULATION. */
    private fun isInlineSpace(c: Char): Boolean =
        c == '\t' || Character.getType(c) == Character.SPACE_SEPARATOR.toInt()

    // ------------------------------------------------------------------ front matter

    /**
     * The offset scanning starts at: past a recognized YAML front-matter block, else 0 (or `-1`
     * when a recognized block runs to the very end of the document).
     *
     * All three conditions of plan §4.6(1) must hold — first line exactly `---`, a closing `---`
     * within [MAX_FRONT_MATTER_LINES], and at least one YAML-looking line between them. If any
     * fails the block is NOT front matter and the leading `---` is left to the ordinary walk as a
     * thematic break. Bounded in line COUNT and line LENGTH, so never a document-sized pre-pass.
     */
    private suspend fun frontMatterEndOffset(text: String): Int {
        var end = contentEnd(text, 0)
        val openFrom = trimmedStart(text, 0, end)
        if (!isDelimiter(text, openFrom, trimmedEnd(text, openFrom, end))) return 0

        var looksYaml = false
        var index = 1
        var start = nextLineStart(text, end)
        while (start >= 0 && index < MAX_FRONT_MATTER_LINES) {
            end = contentEnd(text, start)
            val from = trimmedStart(text, start, end)
            val to = trimmedEnd(text, from, end)
            if (isDelimiter(text, from, to)) {
                return if (looksYaml) nextLineStart(text, end) else 0
            }
            if (!looksYaml && to - from in 1..MAX_FRONT_MATTER_LINE_LENGTH) {
                val line = text.substring(from, to)
                looksYaml = YAML_MAPPING.containsMatchIn(line) ||
                    YAML_SEQUENCE_MAPPING.containsMatchIn(line)
            }
            start = nextLineStart(text, end)
            index++
        }
        return 0
    }

    /** `[from, to)` is exactly `---`, the front-matter delimiter. */
    private fun isDelimiter(text: String, from: Int, to: Int): Boolean =
        to - from == 3 && text[from] == '-' && text[from + 1] == '-' && text[from + 2] == '-'

    // ------------------------------------------------------------------ line classifiers

    /**
     * The fence run length when trimmed line `[from, to)` is a fenced-code delimiter, else 0. iOS
     * parity (`TOCBuilder.parseFenceLine`): run of at least 3, and a backtick fence's info string
     * may not itself contain a backtick — `` ```kotlin` `` is not a fence.
     */
    private suspend fun fenceRunLength(text: String, from: Int, to: Int): Int {
        if (from >= to) return 0
        val first = text[from]
        if (first != '`' && first != '~') return 0
        val afterRun = walkForward(text, from, to) { it == first }
        val count = afterRun - from
        if (count < 3) return 0
        // A backtick anywhere in the info string disqualifies the line.
        if (first == '`' && walkForward(text, afterRun, to) { it != '`' } < to) return 0
        return count
    }

    /**
     * Trimmed line `[from, to)` as an ATX heading: its 0-based depth and title, or `null`. iOS
     * parity (`TOCBuilder.parseATXHeading`): 1–6 hashes, then literally a U+0020; title trimmed; a
     * trailing closing-hash run dropped only when what is left is non-empty (so `### ###` keeps
     * `###` as its title); an empty title is not a heading.
     */
    private suspend fun parseAtxHeading(text: String, from: Int, to: Int): Pair<Int, String>? {
        if (from >= to || text[from] != '#') return null
        val afterHashes = walkForward(text, from, to) { it == '#' }
        val hashes = afterHashes - from
        if (hashes > 6) return null
        if (afterHashes >= to || text[afterHashes] != ' ') return null

        val start = trimmedStart(text, afterHashes, to)
        var end = trimmedEnd(text, start, to)
        if (end > start && text[end - 1] == '#') {
            val stripped = trimmedEnd(text, start, walkBackward(text, start, end) { it == '#' })
            if (stripped > start) end = stripped
        }
        if (start >= end) return null
        return (hashes - 1) to text.substring(start, end)
    }

    /**
     * Trimmed line `[from, to)` as a setext underline: depth 0 for `=`, 1 for `-`, else `null`. It
     * must be ONE contiguous run of a single marker char (length >= 1 — a lone `-` is a valid
     * underline per CommonMark); interior whitespace disqualifies it, so `- - -` stays a break.
     */
    private suspend fun setextDepth(text: String, from: Int, to: Int): Int? {
        if (from >= to) return null
        val first = text[from]
        if (first != '=' && first != '-') return null
        if (walkForward(text, from, to) { it == first } < to) return null
        return if (first == '=') 0 else 1
    }
}
