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
import java.util.Collections

/**
 * What one Contents row renders: a title string and the inclusive ranges that index THAT string.
 *
 * **Nothing anywhere can pair an arbitrary title with arbitrary ranges.** A `sealed class` whose only
 * constructor is `private` cannot be subclassed even from another file in this package — a subclass
 * would have to invoke that constructor — and its single implementation is private to the class. The
 * two factories below are therefore the only expressions that can build one, and NEITHER accepts a
 * title and a range list as independent arguments: [plain] has no range parameter at all, and
 * [forRow] derives both halves from ONE corpus index.
 *
 * (A sealed *interface* is weaker and was rejected at Gate-4 round 2: a future file in the same
 * package + module could have implemented it and forged a mismatched pair.)
 */
sealed class TocRowText private constructor(
    val title: String,
    matchRanges: List<IntRange>,
) {
    /**
     * The matched runs, as an UNMODIFIABLE SNAPSHOT.
     *
     * Both halves matter (Gate-4 round 3). The copy breaks aliasing to the fold's own list; the
     * unmodifiable wrapper defeats `(row.matchRanges as MutableList).clear(); addAll(otherRow)`,
     * which would otherwise re-point one row's tint at another row's ranges through a nominally
     * read-only `List` — no constructor and no subclass required. The empty case reuses the shared
     * immutable `emptyList()`, so the unfiltered path still allocates nothing.
     */
    val matchRanges: List<IntRange> =
        if (matchRanges.isEmpty()) emptyList()
        else Collections.unmodifiableList(ArrayList(matchRanges))

    /** The one and only implementation. Private to [TocRowText], so no other subtype can exist. */
    private class Row(title: String, matchRanges: List<IntRange>) : TocRowText(title, matchRanges)

    internal companion object {
        /** An UNFILTERED row: no range parameter exists, so the ranges are empty BY TYPE. */
        fun plain(entry: TocEntry): TocRowText {
            val title = TocTitleFilter.matchTitle(entry)
            return Row(if (title.isEmpty()) TocTitleFilter.UNTITLED_LABEL else title, emptyList())
        }

        /**
         * A FILTERED row. One [index] into [corpus] drives the title AND the ranges, so the two
         * cannot describe different strings. A blank match title takes the presentational label with
         * empty ranges WITHOUT consulting the fold, so the label can never carry a tint.
         */
        fun forRow(corpus: TocFoldedToc, index: Int, foldedQuery: String): TocRowText {
            val title = corpus.matchTitleAt(index)
            if (title.isEmpty()) return Row(TocTitleFilter.UNTITLED_LABEL, emptyList())
            return Row(title, corpus.matchRangesAt(index, foldedQuery))
        }
    }
}

/**
 * Which rows the Contents list shows. Deliberately NOT a list of row projections: the unfiltered
 * case must materialise nothing per row, because that is the cost this shape exists to remove.
 */
sealed interface TocFilterResult {
    /** Not filtering: NO per-row data — nothing normalized, nothing folded, nothing allocated. */
    data object Unfiltered : TocFilterResult

    /**
     * Filtering: the survivors, addressed by position and carrying their ORIGINAL entry indices.
     *
     * Hardened exactly like [TocRowText] (Gate-4 round 3): a `sealed class` whose only constructor is
     * `private`, so no other file can supply an implementation with inconsistent `size`/`get` — which
     * would crash a consumer iterating `0 until size`, not merely misplace the pinned row. The
     * backing array is never exposed either: [contains] is a binary search, sound ONLY while the
     * indices are strictly ascending, and a handed-out `IntArray` would make that a convention a
     * caller could break after the fact.
     */
    sealed class Matched private constructor() : TocFilterResult {
        /** How many rows survived. */
        abstract val size: Int

        /** The ORIGINAL entry index of the [position]-th survivor — what the row's ordinal, its
         *  highlight and its `onJump` all read. */
        abstract operator fun get(position: Int): Int

        /** Whether the entry at [originalIndex] survived. O(log [size]). */
        abstract fun contains(originalIndex: Int): Boolean

        /** The one and only implementation; private, so no other subtype can exist. */
        private class Indices(private val indices: IntArray) : Matched() {
            override val size: Int get() = indices.size
            override fun get(position: Int): Int = indices[position]
            override fun contains(originalIndex: Int): Boolean =
                Arrays.binarySearch(indices, originalIndex) >= 0
        }

        internal companion object {
            /** "Filtering, nothing matched" — shared, so a fold-away keystroke allocates nothing. */
            val EMPTY: Matched = Indices(IntArray(0))

            /**
             * The only producer. [ascending] must be strictly ascending and must not be retained by
             * the caller; [TocFoldedToc.filter] guarantees both, building a fresh array it drops.
             */
            fun of(ascending: IntArray): Matched = Indices(ascending)
        }
    }
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
    fun rowText(index: Int, foldedQuery: String): TocRowText =
        TocRowText.forRow(this, index, foldedQuery)

    /**
     * This row's match string. `internal` so [TocRowText.forRow] can read it — and SAFE despite that,
     * because it hands back a bare `String`: nothing outside [TocRowText] can assemble a title and a
     * range list into a row, so there is no mispairing to enable.
     */
    internal fun matchTitleAt(index: Int): String = matchTitles[index]

    /** This row's match ranges, resolved from its OWN fold. Same reasoning as [matchTitleAt]. */
    internal fun matchRangesAt(index: Int, foldedQuery: String): List<IntRange> =
        folds[index].matchRanges(foldedQuery)

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
    fun plainRowText(entry: TocEntry): TocRowText = TocRowText.plain(entry)

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
        if (foldedQuery.isEmpty()) return TocFilterResult.Matched.EMPTY
        return TocFilterResult.Matched.of(foldedToc.value.filter(foldedQuery))
    }

    /**
     * True when a filtering query has filtered the active chapter OUT — the signal to pin the
     * design's "Reading" row. False when not filtering, when there is no active chapter
     * ([activeIndex] < 0), or when it still matches. Delegates to
     * [TocFilterResult.Matched.contains], a binary search over the implementation-owned ascending
     * indices: this runs on every composition, over a list reaching ~1 859 rows.
     */
    fun isActiveFilteredOut(result: TocFilterResult, activeIndex: Int): Boolean = when (result) {
        TocFilterResult.Unfiltered -> false
        is TocFilterResult.Matched -> activeIndex >= 0 && !result.contains(activeIndex)
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
            is TocFilterResult.Matched -> result.size
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
