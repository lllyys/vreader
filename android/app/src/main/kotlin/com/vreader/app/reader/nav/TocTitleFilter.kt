// Purpose: feature #141 WI-1 — the PURE core of the filterable Contents sheet: fold a TOC's titles
// once, answer "which rows survive this query" and "which characters of THIS row matched", and say
// whether the active chapter was filtered out. No Compose, no state, no I/O. The Android counterpart
// of iOS `TOCTitleFilter.swift` (#94) — matching its OBSERVABLE semantics, not its API.
//
// Pipeline (per display code point, NEVER per char — surrogate pairs are one unit):
//   display cp ──ICU FULL case fold──► NFD (never NFKC) ──drop category Mn──► folded chars
//                                                                    + starts[]/ends[] index maps
//
// Key decisions:
// - **ICU `UCharacter.foldCase(String, FOLD_CASE_DEFAULT)`, not `lowercase()`.** Lowercasing is
//   context-sensitive: it maps `Σ`→`σ` but leaves final sigma `ς` alone (so a Greek chapter ending
//   in `ς` is unreachable by the word's uppercase spelling) and leaves `ß` as `ß`. Full folding maps
//   `ς`/`σ`/`Σ` all to `σ` and `ß`→`ss`, and is locale-independent BY CONSTRUCTION, so the Turkish-I
//   hazard cannot arise. The `foldCase(int, Boolean)` overload does only SIMPLE folding and would
//   silently reopen both gaps — do not "simplify" to it.
// - **NFD, never NFKC.** NFKC is length-changing ACROSS code points and would destroy the index
//   maps. Consequence: full-width Latin does not fold (agrees with iOS). `SearchTextNormalizer` is
//   deliberately NOT reused — it is NFKC-first, recomposes to NFC, and CJK-segments for FTS.
// - **One string, one owner.** [TocTitleFilter.matchTitle] is the SOLE producer of a row's match
//   string, and the fold is built from that same string, so `starts`/`ends` index it by
//   construction. Text and ranges leave as ONE [TocRowText] a caller can neither build nor copy.
// - **The "Untitled" label is never matchable.** A null/blank title's match string is `""`; the
//   label is applied at render time, in a branch that never touches a range source.
// - **The not-filtering path allocates nothing per row** — [TocTitleFilter.filter] returns the
//   [TocFilterResult.Unfiltered] singleton WITHOUT reading the corpus `Lazy`. Three prior plan
//   revisions each let that cost back in through this branch.
// - **Ranges (normative):** INCLUSIVE both ends, UTF-16 `Char` units of the MATCH title — the
//   `search/InBookSearchRows` convention; the exclusive conversion happens once, at the
//   `AnnotatedString` boundary.
//
// @coordinates-with: TocEntry.kt, TocContentsSheet.kt (collapseLineBreaks), TocSheetRows.kt
package com.vreader.app.reader.nav

import android.icu.lang.UCharacter
import java.text.Normalizer
import java.util.Arrays

/**
 * What one Contents row renders: a title string and the inclusive ranges that index THAT string.
 *
 * NOT a `data class` and NOT publicly constructible — no synthesised `copy`, no caller-built
 * instances. Only [TocTitleFilter.plainRowText] (no range source at all) and [TocFoldedToc.rowText]
 * (resolves its OWN fold from an index) produce one, so a title and a set of ranges cannot be paired
 * by anyone but the code that guarantees they describe the same string.
 */
class TocRowText private constructor(
    val title: String,
    val matchRanges: List<IntRange>,
) {
    internal companion object {
        /** The only producer with NO range parameter — ranges are empty by type, not by value. */
        fun untinted(title: String): TocRowText = TocRowText(title, emptyList())

        /** The only producer that can attach ranges; both arguments come from one row's own fold. */
        fun tinted(title: String, matchRanges: List<IntRange>): TocRowText =
            TocRowText(title, matchRanges)
    }
}

/**
 * Which rows the Contents list shows. Deliberately NOT a list of row projections: the unfiltered
 * case must materialise nothing per row, because that is the cost this shape exists to remove.
 */
sealed interface TocFilterResult {
    /** Not filtering: NO per-row data — nothing normalized, nothing folded, nothing allocated. */
    data object Unfiltered : TocFilterResult

    /** Filtering: the surviving ORIGINAL indices, strictly ascending. One small array per keystroke. */
    class Matched(val indices: IntArray) : TocFilterResult
}

/**
 * The folded corpus for ONE table of contents — match titles and their folds, index-aligned with the
 * entries it was built from. Constructing it is the feature's one >100 ms-class cost, so it is built
 * lazily, on the first query that can actually match, and never on a Contents open.
 *
 * Sole owner of the fold: every operation takes an INDEX into its own arrays, so there is no
 * parameter through which another row's (or another book's) fold could be supplied.
 */
class TocFoldedToc private constructor(
    private val matchTitles: List<String>,
    private val folds: List<FoldedTitle>,
) {

    /** How many entries this corpus was built from — the "of M" denominator's source. */
    val size: Int get() = matchTitles.size

    /** The ORIGINAL indices whose match title contains [foldedQuery], strictly ascending. */
    fun filter(foldedQuery: String): IntArray {
        if (foldedQuery.isEmpty()) return EMPTY_INDICES
        val out = IntArray(folds.size)
        var n = 0
        for (i in folds.indices) {
            if (folds[i].folded.indexOf(foldedQuery) >= 0) out[n++] = i
        }
        return if (n == out.size) out else out.copyOf(n)
    }

    /**
     * The rendered text for the entry at ORIGINAL index [index]. Looks up its own fold — the caller
     * supplies an index, never a fold. An entry with a blank match title returns the presentational
     * label with empty ranges WITHOUT reading the fold at all, so the label can never carry a tint.
     */
    fun rowText(index: Int, foldedQuery: String): TocRowText {
        val title = matchTitles[index]
        if (title.isEmpty()) return TocRowText.untinted(TocTitleFilter.UNTITLED_LABEL)
        return TocRowText.tinted(title, folds[index].matchRanges(foldedQuery))
    }

    /**
     * A match title's folded form plus the maps carrying a folded range back to that title. PRIVATE
     * to [TocFoldedToc] — never a parameter, return value or public property anywhere, so a foreign
     * fold has no way in.
     *
     * `starts[i]` = display index of the code point that produced `folded[i]`. `ends[i]` = that code
     * point's display END (exclusive), extended over any immediately following STRIPPED marks, so a
     * match ending just before a combining mark still tints the mark with its base character.
     */
    private class FoldedTitle(
        val folded: String,
        private val starts: IntArray,
        private val ends: IntArray,
    ) {
        /** ALL non-overlapping occurrences of [foldedQuery], as inclusive ranges in the match title. */
        fun matchRanges(foldedQuery: String): List<IntRange> {
            if (foldedQuery.isEmpty() || folded.isEmpty()) return emptyList()
            val out = ArrayList<IntRange>(2)
            var from = 0
            while (from <= folded.length - foldedQuery.length) {
                val at = folded.indexOf(foldedQuery, from)
                if (at < 0) break
                out.add(originalRange(at, at + foldedQuery.length - 1))
                from = at + foldedQuery.length
            }
            return out
        }

        /** The display range for the folded slice `[foldedFirst..foldedLast]` — both inclusive. */
        private fun originalRange(foldedFirst: Int, foldedLast: Int): IntRange {
            if (starts.isEmpty()) return IntRange.EMPTY
            val first = foldedFirst.coerceIn(0, starts.size - 1)
            val last = foldedLast.coerceIn(first, ends.size - 1)
            return starts[first]..(ends[last] - 1)
        }

        companion object {
            fun of(matchTitle: String): FoldedTitle {
                val folded = StringBuilder(matchTitle.length)
                val starts = IntBuf(matchTitle.length)
                val ends = IntBuf(matchTitle.length)
                var i = 0
                while (i < matchTitle.length) {
                    val cp = matchTitle.codePointAt(i)
                    val cpStart = i
                    val cpEnd = i + Character.charCount(cp)
                    var emitted = false
                    foldCodePoint(cp) { survivor ->
                        folded.appendCodePoint(survivor)
                        repeat(Character.charCount(survivor)) {
                            starts.add(cpStart)
                            ends.add(cpEnd)
                        }
                        emitted = true
                    }
                    // A display code point that survives nothing is a stripped mark: fold its span
                    // into the preceding folded character so the two highlight together.
                    if (!emitted) ends.extendLastTo(cpEnd)
                    i = cpEnd
                }
                return FoldedTitle(folded.toString(), starts.toArray(), ends.toArray())
            }
        }
    }

    companion object {
        private val EMPTY_INDICES = IntArray(0)

        /** Folds every entry's match title. THIS call is the cost the `Lazy` wrapper defers. */
        fun of(entries: List<TocEntry>): TocFoldedToc {
            val titles = ArrayList<String>(entries.size)
            val folds = ArrayList<FoldedTitle>(entries.size)
            for (entry in entries) {
                val title = TocTitleFilter.matchTitle(entry)
                titles.add(title)
                folds.add(FoldedTitle.of(title))
            }
            return TocFoldedToc(titles, folds)
        }
    }
}

/** The pure title-filtering derivations the Contents sheet drives. Stateless. */
object TocTitleFilter {

    /** The presentational fallback for an entry with no title. NOT matchable — see [plainRowText]. */
    const val UNTITLED_LABEL: String = "Untitled"

    /**
     * THE single producer of a row's MATCH string: [TocEntry.title] with embedded line breaks
     * collapsed and ends trimmed, or `""` when null/blank. Deliberately NOT [UNTITLED_LABEL] —
     * typing "untitled" must not surface every untitled row.
     */
    fun matchTitle(entry: TocEntry): String {
        val raw = entry.title ?: return ""
        val collapsed = raw.collapseLineBreaks()
        return if (collapsed.isBlank()) "" else collapsed
    }

    /**
     * The canonical query form: [query] trimmed, then folded by the pipeline the titles use.
     *
     * Kotlin's `trim()` is correct here and Java's is NOT: `Char.isWhitespace()` is
     * `Character.isWhitespace() || Character.isSpaceChar()`, so it strips U+3000 IDEOGRAPHIC SPACE
     * and U+00A0 NBSP; `java.lang.String.trim()` strips only chars <= U+0020 and would leave a
     * CJK-padded query unmatchable.
     */
    fun foldQuery(query: String): String {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return ""
        val out = StringBuilder(trimmed.length)
        var i = 0
        while (i < trimmed.length) {
            val cp = trimmed.codePointAt(i)
            foldCodePoint(cp) { out.appendCodePoint(it) }
            i += Character.charCount(cp)
        }
        return out.toString()
    }

    /**
     * The rendered text for an UNFILTERED row: its match title (or [UNTITLED_LABEL]) with ranges
     * empty BY TYPE — this function has no range source, so it cannot mispair. Called per VISIBLE
     * row, exactly like the sheet's existing per-row `remember`.
     */
    fun plainRowText(entry: TocEntry): TocRowText {
        val title = matchTitle(entry)
        return TocRowText.untinted(if (title.isEmpty()) UNTITLED_LABEL else title)
    }

    /**
     * The filter pass. Both early returns leave `foldedToc` UNFORCED — that is why it is a `Lazy`
     * and not a [TocFoldedToc]; passing `.value` at the call site would reinstate the deferred cost.
     * A blank [trimmedQuery] is "not filtering"; a non-blank one whose [foldedQuery] is empty (a
     * lone combining mark) is "filtering with no results", as iOS behaves — NOT the full list.
     */
    fun filter(
        trimmedQuery: String,
        foldedQuery: String,
        foldedToc: Lazy<TocFoldedToc>,
    ): TocFilterResult {
        if (trimmedQuery.isEmpty()) return TocFilterResult.Unfiltered
        if (foldedQuery.isEmpty()) return TocFilterResult.Matched(IntArray(0))
        return TocFilterResult.Matched(foldedToc.value.filter(foldedQuery))
    }

    /**
     * True when a filtering query has filtered the active chapter OUT — the signal to pin the
     * design's "Reading" row. False when not filtering, when there is no active chapter
     * ([activeIndex] < 0), or when it still matches. [TocFilterResult.Matched.indices] is ascending,
     * so this is a binary search: it runs on every composition over a list reaching ~1 859 rows.
     */
    fun isActiveFilteredOut(result: TocFilterResult, activeIndex: Int): Boolean = when (result) {
        TocFilterResult.Unfiltered -> false
        is TocFilterResult.Matched ->
            activeIndex >= 0 && Arrays.binarySearch(result.indices, activeIndex) < 0
    }
}

/** The live result-count line below the filter field. Pure, so its wording is pinned without rendering. */
object TocFilterCountLabel {
    /**
     * `"N of M chapters"` (singular `chapter` for exactly one) while filtering, `"No chapters match"`
     * on an empty result, `null` (hidden) when [trimmedQuery] is blank — iOS `TOCFilterCountLabel`
     * verbatim, singular rule included.
     */
    fun text(result: TocFilterResult, totalCount: Int, trimmedQuery: String): String? {
        if (trimmedQuery.isEmpty()) return null
        val visible = when (result) {
            TocFilterResult.Unfiltered -> return null
            is TocFilterResult.Matched -> result.indices.size
        }
        if (visible == 0) return "No chapters match"
        return "$visible of $totalCount ${if (visible == 1) "chapter" else "chapters"}"
    }
}

/**
 * Folds ONE display code point, emitting every SURVIVING folded code point to [emit].
 *
 * The ASCII short-circuit is exact, not an approximation: within U+0000..U+007F full case folding
 * maps only `A`..`Z` (to `a`..`z`), NFD is the identity, and no code point is a non-spacing mark. It
 * exists because the corpus fold runs over every character of every title.
 */
private inline fun foldCodePoint(codePoint: Int, emit: (Int) -> Unit) {
    if (codePoint < 0x80) {
        emit(if (codePoint in 0x41..0x5A) codePoint + 0x20 else codePoint)
        return
    }
    val folded = UCharacter.foldCase(String(Character.toChars(codePoint)), UCharacter.FOLD_CASE_DEFAULT)
    val decomposed =
        if (Normalizer.isNormalized(folded, Normalizer.Form.NFD)) folded
        else Normalizer.normalize(folded, Normalizer.Form.NFD)
    var i = 0
    while (i < decomposed.length) {
        val cp = decomposed.codePointAt(i)
        if (Character.getType(cp) != Character.NON_SPACING_MARK.toInt()) emit(cp)
        i += Character.charCount(cp)
    }
}

/** A minimal growable int buffer — the index maps are built per title, so boxing is not affordable. */
private class IntBuf(initialCapacity: Int) {
    private var values = IntArray(if (initialCapacity < 4) 4 else initialCapacity)
    private var count = 0

    fun add(value: Int) {
        if (count == values.size) values = values.copyOf(values.size * 2)
        values[count++] = value
    }

    /** Widen the most recently added value (the `ends`-extension rule). No-op when empty. */
    fun extendLastTo(value: Int) {
        if (count > 0) values[count - 1] = value
    }

    fun toArray(): IntArray = values.copyOf(count)
}
