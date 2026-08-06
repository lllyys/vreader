package com.vreader.app.reader.nav

import android.icu.lang.UCharacter
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator
import java.lang.reflect.Modifier
import java.util.Locale

/**
 * Feature #141 WI-1 — [TocTitleFilter] / [TocFoldedToc] / [TocRowText] / [TocFilterCountLabel]:
 * the pure core of the filterable Contents sheet (plan §5.1, test catalogue §8.1).
 *
 * `@RunWith(RobolectricTestRunner::class)` is REQUIRED, not stylistic: the folding pipeline calls
 * `android.icu.lang.UCharacter.foldCase`, a framework class the stub `android.jar` answers with
 * "not mocked". Exact precedent: `SearchTextNormalizerTest.kt`.
 *
 * Two disciplines this suite is written to:
 *  - **Bounds, not counts.** Range assertions state the exact inclusive `(first, last)` pair against
 *    a hand-computed expectation. A test that only counts ranges is what let the original
 *    wrong-string defect through (plan §5.2.1).
 *  - **Every assertion is reachable from the production seam.** Ranges are read through
 *    `TocFoldedToc.rowText`, matches through `TocTitleFilter.filter` — never through a test-only
 *    back door — so a shape change cannot pass by leaving the seam behind.
 */
@RunWith(RobolectricTestRunner::class)
class TocTitleFilterTest {

    // ---- helpers ---------------------------------------------------------------------------------

    private fun entry(title: String?): TocEntry = TocEntry(
        title = title,
        depth = 0,
        pageLabel = null,
        canonicalLocator = Locator(
            contentSHA256 = "a".repeat(64),
            fileByteCount = 1_024L,
            format = "txt",
            charOffsetUTF16 = 0,
        ),
        epubReadiumLocator = null,
    )

    /** The production call shape: trim → fold → filter, with the corpus behind a `Lazy`. */
    private fun filterOf(entries: List<TocEntry>, query: String): TocFilterResult {
        val trimmed = query.trim()
        return TocTitleFilter.filter(
            trimmedQuery = trimmed,
            foldedQuery = TocTitleFilter.foldQuery(trimmed),
            foldedToc = lazy { TocFoldedToc.of(entries) },
        )
    }

    private fun matchedIndices(result: TocFilterResult): IntArray = when (result) {
        is TocFilterResult.Matched -> result.indices
        TocFilterResult.Unfiltered -> throw AssertionError("expected Matched, got Unfiltered")
    }

    private fun matches(title: String?, query: String): Boolean {
        val result = filterOf(listOf(entry(title)), query)
        return when (result) {
            TocFilterResult.Unfiltered -> true
            is TocFilterResult.Matched -> result.indices.isNotEmpty()
        }
    }

    /** The rendered row text for a single-entry TOC under [query] — the exact production seam. */
    private fun rowTextOf(title: String?, query: String): TocRowText =
        TocFoldedToc.of(listOf(entry(title))).rowText(0, TocTitleFilter.foldQuery(query))

    private fun rangesOf(title: String?, query: String): List<IntRange> =
        rowTextOf(title, query).matchRanges

    private companion object {
        /** U+0301 COMBINING ACUTE ACCENT — a dead key / pasted mark; folds away to "". */
        const val ACUTE = "́"
        const val IDEOGRAPHIC_SPACE = "　"
        const val NBSP = " "
    }

    @After
    fun restoreLocale() {
        Locale.setDefault(Locale.US)
    }

    // ---- the not-filtering path (plan §6's standing note: cost keeps re-entering here) -----------

    @Test fun emptyQuery_returnsAllEntriesWithOriginalIndices() {
        val entries = listOf(entry("One"), entry("Two"), entry("Three"))
        // "Unfiltered" IS the identity answer: the composable iterates `entries` directly, so every
        // row keeps its original index by construction rather than by a carried projection.
        assertSame(TocFilterResult.Unfiltered, filterOf(entries, ""))
    }

    @Test fun blankQuery_returnsUnfilteredSingleton_notAList() {
        // Fails against any shape that returns a per-row list from the blank branch (plan r3 edit 2).
        val entries = List(1_859) { entry("第${it}章") }
        val result = filterOf(entries, "   ")
        assertSame(
            "the not-filtering path must return the singleton, materialising NO per-row object",
            TocFilterResult.Unfiltered,
            result,
        )
    }

    @Test fun whitespaceOnlyQuery_treatedAsEmpty() {
        val entries = listOf(entry("Chapter One"))
        listOf(" ", "\t", "\n", IDEOGRAPHIC_SPACE, NBSP, " $IDEOGRAPHIC_SPACE$NBSP ").forEach { q ->
            assertSame("query ${q.map { it.code }} must not filter", TocFilterResult.Unfiltered, filterOf(entries, q))
        }
    }

    @Suppress("PLATFORM_CLASS_MAPPED_TO_KOTLIN")
    @Test fun javaTrimWouldLeaveIdeographicSpace() {
        val padded = "${IDEOGRAPHIC_SPACE}第十$IDEOGRAPHIC_SPACE"
        // Kotlin's trim() uses Char.isWhitespace() = Character.isWhitespace || isSpaceChar.
        assertEquals("第十", padded.trim())
        // java.lang.String.trim() strips only chars <= U+0020, so U+3000 survives it. Pinned so a
        // future "simplification" back to Java's trim fails loudly instead of shipping a query that
        // can never match.
        assertEquals(padded, (padded as java.lang.String).trim())
    }

    @Test fun blankQuery_neverForcesTheFold() {
        val corpus = lazy { TocFoldedToc.of(List(1_859) { entry("第${it}章") }) }
        TocTitleFilter.filter(trimmedQuery = "", foldedQuery = "", foldedToc = corpus)
        assertFalse("a Contents open must not pay the corpus fold (cost B)", corpus.isInitialized())
    }

    @Test fun foldAwayQuery_neverForcesTheFold() {
        val corpus = lazy { TocFoldedToc.of(List(1_859) { entry("第${it}章") }) }
        val result = TocTitleFilter.filter(
            trimmedQuery = ACUTE,
            foldedQuery = TocTitleFilter.foldQuery(ACUTE),
            foldedToc = corpus,
        )
        assertEquals(0, matchedIndices(result).size)
        assertFalse("a dead-key keystroke must not pay cost B either", corpus.isInitialized())
    }

    @Test fun queryFoldingToNothing_showsNoMatchNotFullList() {
        val entries = listOf(entry("Chapter One"), entry("Chapter Two"))
        val result = filterOf(entries, ACUTE)
        // Trims non-empty ⇒ we ARE filtering; folds to "" ⇒ zero matches. iOS shows "No chapters
        // match" here; gating on the FOLDED query would have shown the full list instead.
        assertEquals("", TocTitleFilter.foldQuery(ACUTE))
        assertArrayEquals(IntArray(0), matchedIndices(result))
        // And no infinite indexOf("") loop: reaching this assertion at all proves termination.
    }

    // ---- case folding ----------------------------------------------------------------------------

    @Test fun caseInsensitive_ascii() {
        assertTrue(matches("The Street", "STREET"))
        assertTrue(matches("the street", "Street"))
    }

    @Test fun caseInsensitive_nonAscii() {
        assertTrue(matches("Ähre", "ä"))
        assertTrue(matches("ähre", "Ä"))
    }

    @Test fun caseFold_sharpS() {
        // Closed by ICU FULL case folding (ß → ss). Fails under String.lowercase().
        assertTrue(matches("Straße des Lichts", "strasse"))
        assertTrue(matches("STRASSE DES LICHTS", "straße"))
    }

    @Test fun caseFold_greekFinalAndMedialSigma() {
        // The user-facing gap lowercase() cannot close: Σ → σ but ς stays ς, so a chapter ending in
        // a final sigma is unreachable by the word's uppercase spelling.
        assertTrue(matches("Οδός Ονείρων", "ΟΔΟΣ"))
        assertTrue(matches("Οδός Ονείρων", "οδος"))
        assertTrue(matches("ΟΔΟΣ Ονείρων", "οδός"))
    }

    @Test fun caseFold_usesFullFoldingNotSimple() {
        // A refactor to UCharacter.foldCase(int, Boolean) — which can only do SIMPLE folding —
        // leaves ß as ß and silently reopens the gap above. Asserted at the fold, not via a match,
        // so the failure names the cause.
        assertEquals("ss", TocTitleFilter.foldQuery("ß"))
        assertEquals("strasse", TocTitleFilter.foldQuery("Straße"))
    }

    @Test fun asciiFastPath_agreesWithIcuForEveryPrintableAsciiCodePoint() {
        // The fold has an ASCII short-circuit for cost B. Differential oracle: it must be
        // indistinguishable from the ICU pipeline it skips, for every printable ASCII code point.
        for (cp in 0x21..0x7E) {
            val ch = cp.toChar().toString()
            val viaIcu = UCharacter.foldCase(ch, UCharacter.FOLD_CASE_DEFAULT)
            assertEquals("ASCII fast path diverges at U+%04X".format(cp), viaIcu, TocTitleFilter.foldQuery(ch))
        }
    }

    @Test fun turkishLocale_doesNotChangeMatching() {
        Locale.setDefault(Locale.forLanguageTag("tr"))
        // Case FOLDING is locale-independent by construction — there is no locale to pass wrong.
        // Kept as a regression pin against a refactor to a locale-sensitive lowercase().
        assertTrue(matches("Inn at the End", "I"))
        assertTrue(matches("Inn at the End", "inn"))
    }

    // ---- diacritics + the index map ---------------------------------------------------------------

    @Test fun diacriticInsensitive_precomposed() {
        assertTrue(matches("Café Royale", "cafe"))
        // "Café" — é is ONE display char, so the range ends at index 3.
        assertEquals(listOf(0..3), rangesOf("Café Royale", "cafe"))
    }

    @Test fun diacriticInsensitive_decomposed() {
        // "Cafe" + U+0301 — é is TWO display chars. The design bundle's JS mock gets exactly this
        // case wrong (it slices the ORIGINAL string with FOLDED indices).
        assertTrue(matches("Café Royale", "cafe"))
        assertEquals(listOf(0..4), rangesOf("Café Royale", "cafe"))
    }

    @Test fun matchRanges_endExtendsOverTrailingCombiningMark() {
        // A match ending immediately before a stripped mark must tint the mark with its base char,
        // otherwise the accent floats outside the highlight.
        assertEquals(listOf(0..4), rangesOf("café bar", "cafe"))
        // The same rule with the mark INSIDE the match rather than at its edge.
        assertEquals(listOf(0..8), rangesOf("café bar", "cafe bar"))
    }

    @Test fun matchRanges_exactBounds() {
        // Hand-computed, inclusive on both ends, in UTF-16 Char units of the MATCH title.
        assertEquals(listOf(4..9), rangesOf("The Street", "street"))
        assertEquals(listOf(0..2), rangesOf("The Street", "the"))
        // Every occurrence, each a single Char: T@0, t@5, t@9.
        assertEquals(listOf(0..0, 5..5, 9..9), rangesOf("The Street", "t"))
    }

    @Test fun matchRanges_mapBackToDisplay_afterLengthChangingFold() {
        // İ (U+0130) folds to "i" + U+0307; the mark is stripped ⇒ 1 folded char for 1 display char.
        assertEquals(listOf(1..4), rangesOf("İstanbul", "stan"))
        // A Hangul syllable NFD-decomposes into 3 jamo, NONE of them category Mn ⇒ 3 folded chars
        // for 1 display char. Every following display index must still map back correctly.
        assertEquals(listOf(1..7), rangesOf("각Chapter", "chapter"))
        // ß folds to "ss" ⇒ 2 folded chars for 1 display char, before and inside the match.
        assertEquals(listOf(0..5), rangesOf("Straße", "strasse"))
        assertEquals(listOf(4..5), rangesOf("Straße", "sse"))
        // "Straße Chapter": S0 t1 r2 a3 ß4 e5 ␣6 C7 h8 a9 p10 t11 e12 r13 — the ß→ss expansion adds
        // a folded char BEFORE the match, so the display range must NOT shift with it.
        assertEquals(listOf(7..13), rangesOf("Straße Chapter", "chapter"))
    }

    @Test fun surrogatePairBeforeMatch_rangesAreCharIndices() {
        // AnnotatedString spans are Char indices, so an astral emoji must shift the range by TWO.
        assertEquals(listOf(3..9), rangesOf("😀 Chapter", "chapter"))
    }

    @Test fun multipleOccurrences_allRangesNonOverlapping() {
        assertEquals(listOf(0..1, 2..3), rangesOf("aaaa", "aa"))
        assertEquals(listOf(0..2, 4..6), rangesOf("The Theatre", "the"))
    }

    // ---- matching contract ------------------------------------------------------------------------

    @Test fun noWordPrefixRule() {
        assertTrue(matches("The Spouter-Inn", "inn"))
    }

    @Test fun queryLongerThanEveryTitle_returnsEmpty() {
        val entries = listOf(entry("One"), entry("Two"))
        assertArrayEquals(IntArray(0), matchedIndices(filterOf(entries, "a title nobody has")))
    }

    @Test fun cjk_singleCharacterSubstring() {
        val entries = listOf(entry("第一章 剑起"), entry("第二章 黎明"), entry("第三章 断剑"))
        assertArrayEquals(intArrayOf(0, 2), matchedIndices(filterOf(entries, "剑")))
        assertEquals(listOf(4..4), rangesOf("第一章 剑起", "剑"))
    }

    @Test fun cjk_multiCharacterAndChapterNumber() {
        val entries = listOf(entry("第一章 故人"), entry("第十章"), entry("第十一章"), entry("第十九章"))
        assertArrayEquals(intArrayOf(0), matchedIndices(filterOf(entries, "故人")))
        // 第十 matches 第十 / 第十一 / 第十九 and NOT 第一.
        assertArrayEquals(intArrayOf(1, 2, 3), matchedIndices(filterOf(entries, "第十")))
    }

    @Test fun fullWidthLatin_doesNotMatch() {
        // The one exclusion that genuinely agrees with iOS: NFD (not NFKC) leaves full-width alone.
        assertFalse(matches("ＣＡＦＥ Royale", "cafe"))
    }

    @Test fun ligature_foldsLikeIcuFullCaseFolding() {
        // MEASURED, not assumed (see the class KDoc's erratum note in the WI's handoff): Unicode
        // FULL case folding maps U+FB01 to "fi", so ICU closes this and Android agrees with iOS.
        // The plan's §3 table predicted "no match"; the implementation follows the plan's ALGORITHM
        // (ICU full folding) and this test pins what that algorithm actually does.
        assertEquals("fi", TocTitleFilter.foldQuery("ﬁ"))
        assertTrue(matches("The ﬁrst Chapter", "fi"))
        assertEquals(listOf(4..4), rangesOf("The ﬁrst Chapter", "fi"))
    }

    @Test fun arabicHamza_overMatchesVsIos() {
        // NFD + strip-Mn removes the hamza (U+0654, category Mn) that iOS's collation keeps, so
        // Android matches where iOS does not. Over-matching is the benign direction for a title
        // narrower; pinned so any change to the strip rule is deliberate.
        assertTrue(matches("الأول", "الاول"))
    }

    // ---- null / blank titles: the presentational fallback must never be matchable -----------------

    @Test fun nullOrBlankTitle_neverMatchesNonEmptyQuery_butCountsInTotal() {
        val entries = listOf(entry(null), entry(""), entry("   "), entry("Real Chapter"))
        val result = filterOf(entries, "chapter")
        assertArrayEquals(intArrayOf(3), matchedIndices(result))
        assertEquals("1 of 4 chapter", TocFilterCountLabel.text(result, entries.size, "chapter"))
    }

    @Test fun queryUntitled_matchesZeroRows_inTocWithBlankTitles() {
        // Fails against any spec where the producer emits the "Untitled" LABEL as the match string.
        val entries = listOf(entry(null), entry(""), entry("   "), entry("Real Chapter"))
        assertArrayEquals(IntArray(0), matchedIndices(filterOf(entries, "untitled")))
        assertArrayEquals(IntArray(0), matchedIndices(filterOf(entries, "Untitled")))
    }

    @Test fun rowText_untitledRow_hasEmptyRangesEvenWhenQueryMatchesTheLabel() {
        val text = rowTextOf(null, "untitled")
        assertEquals(TocTitleFilter.UNTITLED_LABEL, text.title)
        assertTrue("the untitled branch has no range source at all", text.matchRanges.isEmpty())
        assertTrue(rowTextOf("   ", "untitled").matchRanges.isEmpty())
    }

    @Test fun plainRowText_appliesTheLabelAtRenderTimeAndCarriesNoRanges() {
        assertEquals(TocTitleFilter.UNTITLED_LABEL, TocTitleFilter.plainRowText(entry(null)).title)
        assertEquals(TocTitleFilter.UNTITLED_LABEL, TocTitleFilter.plainRowText(entry("  ")).title)
        assertEquals("Chapter One", TocTitleFilter.plainRowText(entry("  Chapter One  ")).title)
        assertTrue(TocTitleFilter.plainRowText(entry("Chapter One")).matchRanges.isEmpty())
    }

    // ---- one string, one owner --------------------------------------------------------------------

    @Test fun rowText_pairsTitleWithRangesThatIndexIt() {
        // The defect this feature's structure exists to prevent: ranges computed on the RAW title and
        // applied to the DISPLAYED one. Both cases are checked by slicing the returned title with the
        // returned ranges — if they described different strings, the slice would be wrong or throw.
        val leading = rowTextOf("   Chapter One", "chapter")
        assertEquals("Chapter One", leading.title)
        assertEquals(listOf(0..6), leading.matchRanges)
        assertEquals("Chapter", leading.title.substring(0, leading.matchRanges[0].last + 1))

        val broken = rowTextOf("第一章 \n  黎明前", "黎明")
        assertEquals("第一章 黎明前", broken.title)
        assertEquals(listOf(4..5), broken.matchRanges)
        assertEquals(
            "黎明",
            broken.title.substring(broken.matchRanges[0].first, broken.matchRanges[0].last + 1),
        )
    }

    @Test fun titleWithEmbeddedLineBreak_matchesNormalizedForm() {
        // The whitespace run spanning the break collapses to ONE space, so a query straddling it
        // matches — against the raw title it could not.
        assertTrue(matches("第一章 \n  黎明前", "章 黎"))
        assertEquals("第一章 黎明前", TocTitleFilter.matchTitle(entry("第一章 \n  黎明前")))
        assertEquals("Chapter One", TocTitleFilter.matchTitle(entry("   Chapter One")))
        assertEquals("", TocTitleFilter.matchTitle(entry(null)))
        assertEquals("", TocTitleFilter.matchTitle(entry("  \n ")))
    }

    @Test fun rowText_cannotBeConstructedOrCopiedByCallers() {
        // A compile-level invariant, asserted at the API shape so a future edit that adds `data`
        // (synthesising `copy`) or relaxes the constructor trips here. TocRowText's ONLY producers
        // are TocTitleFilter.plainRowText (no range source) and TocFoldedToc.rowText (resolves its
        // own fold from an index) — there is no seam that accepts an arbitrary title+ranges pair.
        val klass = TocRowText::class.java
        // Kotlin emits ONE real constructor (private) plus an ACC_SYNTHETIC bridge whose last
        // parameter is `DefaultConstructorMarker` — a type Kotlin source cannot supply, so it is not
        // a construction seam. Every OTHER constructor must be non-public.
        val callable = klass.declaredConstructors.filterNot { it.isSynthetic }
        assertTrue("TocRowText must have no public constructor", callable.none { Modifier.isPublic(it.modifiers) })
        assertTrue("TocRowText must declare exactly one real constructor", callable.size == 1)
        assertTrue(
            "the only public constructor may be Kotlin's synthetic private-constructor bridge",
            klass.declaredConstructors
                .filter { Modifier.isPublic(it.modifiers) }
                .all { it.isSynthetic && it.parameterTypes.last().name.endsWith("DefaultConstructorMarker") },
        )
        assertTrue(
            "TocRowText must not be a data class (no synthesised copy)",
            klass.declaredMethods.none { it.name == "copy" || it.name.startsWith("component") },
        )
    }

    // ---- original indices + the pinned-current predicate ------------------------------------------

    @Test fun filter_preservesOriginalIndices() {
        val entries = List(2_000) { if (it == 1_500) entry("Needle Chapter") else entry("第${it}章") }
        val indices = matchedIndices(filterOf(entries, "needle"))
        assertArrayEquals(intArrayOf(1_500), indices)

        // Strictly ascending is the precondition isActiveFilteredOut's binary search relies on.
        val many = matchedIndices(filterOf(entries, "第"))
        assertTrue("must survive in bulk", many.size > 1_000)
        for (i in 1 until many.size) {
            assertTrue("indices must be STRICTLY ascending at $i", many[i] > many[i - 1])
        }
    }

    @Test fun isActiveFilteredOut_notFiltering_isFalse() {
        assertFalse(TocTitleFilter.isActiveFilteredOut(TocFilterResult.Unfiltered, 3))
    }

    @Test fun isActiveFilteredOut_activeSurvives_isFalse() {
        val result = TocFilterResult.Matched(intArrayOf(0, 3, 7))
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, 3))
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, 0))
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, 7))
    }

    @Test fun isActiveFilteredOut_activeFilteredOut_isTrue() {
        val result = TocFilterResult.Matched(intArrayOf(0, 3, 7))
        assertTrue(TocTitleFilter.isActiveFilteredOut(result, 4))
        assertTrue(TocTitleFilter.isActiveFilteredOut(result, 9))
        assertTrue(TocTitleFilter.isActiveFilteredOut(TocFilterResult.Matched(IntArray(0)), 0))
        // No active chapter (-1) is not "filtered out" — there is nothing to pin.
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, -1))
    }

    // ---- the count line ----------------------------------------------------------------------------

    @Test fun countLabel_hiddenWhenTrimmedQueryIsBlank() {
        assertNull(TocFilterCountLabel.text(TocFilterResult.Unfiltered, 16, ""))
        assertNull(TocFilterCountLabel.text(TocFilterResult.Matched(intArrayOf(1)), 16, ""))
    }

    @Test fun countLabel_singularForOneMatch() {
        assertEquals("1 of 16 chapter", TocFilterCountLabel.text(TocFilterResult.Matched(intArrayOf(4)), 16, "q"))
    }

    @Test fun countLabel_pluralForMany() {
        val result = TocFilterResult.Matched(intArrayOf(0, 1, 2, 3, 4))
        assertEquals("5 of 16 chapters", TocFilterCountLabel.text(result, 16, "q"))
    }

    @Test fun countLabel_noMatch() {
        assertEquals("No chapters match", TocFilterCountLabel.text(TocFilterResult.Matched(IntArray(0)), 16, "q"))
    }

    // ---- corpus edges -------------------------------------------------------------------------------

    @Test fun emptyToc_filtersToNothingWithoutThrowing() {
        assertArrayEquals(IntArray(0), matchedIndices(filterOf(emptyList(), "anything")))
        assertEquals(0, TocFoldedToc.of(emptyList()).size)
    }

    @Test fun allBlankToc_foldsWithoutThrowing() {
        val corpus = TocFoldedToc.of(listOf(entry(null), entry(""), entry("  ")))
        assertEquals(3, corpus.size)
        assertArrayEquals(IntArray(0), corpus.filter(TocTitleFilter.foldQuery("x")))
        assertEquals(TocTitleFilter.UNTITLED_LABEL, corpus.rowText(0, "x").title)
    }

    @Test fun orphanCombiningMarkTitle_foldsAwayAndNeverMatches() {
        // A title that is nothing but a combining mark folds to "" — it matches nothing, and asking
        // for its row text must not throw on an empty index map.
        assertFalse(matches(ACUTE, "a"))
        val text = rowTextOf(ACUTE, "a")
        assertEquals(ACUTE, text.title)
        assertTrue(text.matchRanges.isEmpty())
    }
}
