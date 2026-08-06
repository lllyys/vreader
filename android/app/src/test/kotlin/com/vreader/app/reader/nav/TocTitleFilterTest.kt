package com.vreader.app.reader.nav

import android.icu.lang.UCharacter
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
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
 * Three disciplines this suite is written to:
 *  - **Bounds, not counts.** Range assertions state the exact inclusive `(first, last)` pair against
 *    a hand-computed expectation. A test that only counts ranges is what let the original
 *    wrong-string defect through (plan §5.2.1).
 *  - **Every assertion goes through a production seam.** Ranges are read via `TocFoldedToc.rowText`,
 *    matches via `TocTitleFilter.filter`, and even a [TocFilterResult.Matched] used to probe
 *    `isActiveFilteredOut` is BUILT by the filter — never forged — so a shape change cannot pass by
 *    leaving the seam behind.
 *  - **No invisible character appears inline.** Combining marks, U+3000, NBSP and the astral code
 *    points are NAMED constants whose KDoc states the code point, and every decomposed fixture is
 *    built by concatenating one (`"Cafe$ACUTE"`, never a literal `"Café"` whose composition a reader
 *    cannot see). #139's Gate-2 rounds 3 and 4 both caught invisible characters being silently
 *    normalized inside a source file — which here would quietly turn a decomposed fixture into a
 *    precomposed one and pass for the wrong reason. `codePointsAreTheIntendedOnes` pins the
 *    constants themselves, so a normalization accident fails one obvious test instead of silently
 *    weakening a dozen.
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
        is TocFilterResult.Matched -> IntArray(result.size) { result[it] }
        TocFilterResult.Unfiltered -> throw AssertionError("expected Matched, got Unfiltered")
    }

    /**
     * A PRODUCTION-BUILT [TocFilterResult.Matched] whose survivors are exactly [survivors] out of
     * [total] rows. `Matched` is sealed with a file-private implementation, so a test CANNOT forge
     * one — which is the point of the invariant, and means these assertions run against the same
     * object the sheet will hold.
     */
    private fun matchedResult(total: Int, vararg survivors: Int): TocFilterResult {
        val keep = survivors.toSet()
        val entries = List(total) { entry(if (it in keep) "Needle $it" else "Chapter $it") }
        val result = filterOf(entries, "needle")
        assertArrayEquals(
            "the fixture must produce exactly the requested survivors",
            survivors, matchedIndices(result),
        )
        return result
    }

    private fun matches(title: String?, query: String): Boolean {
        val result = filterOf(listOf(entry(title)), query)
        return when (result) {
            TocFilterResult.Unfiltered -> true
            is TocFilterResult.Matched -> result.size > 0
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

        /** U+0327 COMBINING CEDILLA — the second mark in the stacked-marks fixtures. */
        const val CEDILLA = "̧"

        /** U+3000 IDEOGRAPHIC SPACE — the normal separator in Chinese typesetting. */
        const val IDEOGRAPHIC_SPACE = "　"

        /** U+00A0 NO-BREAK SPACE — `isSpaceChar`, so Kotlin's `trim()` strips it and Java's does not. */
        const val NBSP = " "

        /** U+1F600 GRINNING FACE — an astral code point, i.e. a UTF-16 surrogate PAIR. */
        const val EMOJI = "😀"

        /** U+20000 — CJK Extension B, astral, and real book content rather than a novelty. */
        const val CJK_EXT_B = "𠀀"
    }

    @After
    fun restoreLocale() {
        Locale.setDefault(Locale.US)
    }

    @Test fun codePointsAreTheIntendedOnes() {
        // The tripwire for the discipline above: every fixture constant is checked against its
        // documented code point, so an editor or tool that silently normalizes this file fails HERE,
        // loudly and once, instead of quietly turning a dozen hostile fixtures into benign ones.
        assertArrayEquals(intArrayOf(0x0301), ACUTE.codePoints().toArray())
        assertArrayEquals(intArrayOf(0x0327), CEDILLA.codePoints().toArray())
        assertArrayEquals(intArrayOf(0x3000), IDEOGRAPHIC_SPACE.codePoints().toArray())
        assertArrayEquals(intArrayOf(0x00A0), NBSP.codePoints().toArray())
        assertArrayEquals(intArrayOf(0x1F600), EMOJI.codePoints().toArray())
        assertArrayEquals(intArrayOf(0x20000), CJK_EXT_B.codePoints().toArray())
        // Both astral constants must be surrogate PAIRS in UTF-16 — the reason the index map exists.
        assertEquals(2, EMOJI.length)
        assertEquals(2, CJK_EXT_B.length)
        // And the precomposed/decomposed pair the diacritic tests rely on really are different.
        assertEquals(1, "é".length)
        assertEquals(2, "e$ACUTE".length)
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
        assertSame(
            "the not-filtering path must return the singleton, materialising NO per-row object",
            TocFilterResult.Unfiltered,
            filterOf(entries, "   "),
        )
    }

    @Test fun whitespaceOnlyQuery_treatedAsEmpty() {
        val entries = listOf(entry("Chapter One"))
        listOf(" ", "\t", "\n", IDEOGRAPHIC_SPACE, NBSP, " $IDEOGRAPHIC_SPACE$NBSP ").forEach { q ->
            assertSame(
                "query ${q.map { it.code }} must not filter",
                TocFilterResult.Unfiltered, filterOf(entries, q),
            )
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
        // The user-facing gap lowercase() cannot close: Σ → σ but final ς stays ς, so a chapter
        // ending in a final sigma is unreachable by the word's uppercase spelling.
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
            assertEquals(
                "ASCII fast path diverges at U+%04X".format(cp),
                viaIcu, TocTitleFilter.foldQuery(ch),
            )
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
        // é is U+00E9 — ONE display char, so the range ends at index 3.
        assertTrue(matches("Café Royale", "cafe"))
        assertEquals(listOf(0..3), rangesOf("Café Royale", "cafe"))
    }

    @Test fun diacriticInsensitive_decomposed() {
        // e + U+0301 — TWO display chars. The design bundle's JS mock gets exactly this case wrong
        // (it slices the ORIGINAL string with FOLDED indices).
        assertTrue(matches("Cafe$ACUTE Royale", "cafe"))
        assertEquals(listOf(0..4), rangesOf("Cafe$ACUTE Royale", "cafe"))
    }

    @Test fun matchRanges_endExtendsOverTrailingCombiningMark() {
        // A match ending immediately before a stripped mark must tint the mark with its base char,
        // otherwise the accent floats outside the highlight.
        assertEquals(listOf(0..4), rangesOf("cafe$ACUTE bar", "cafe"))
        // The same rule with the mark INSIDE the match rather than at its edge.
        assertEquals(listOf(0..8), rangesOf("cafe$ACUTE bar", "cafe bar"))
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
        assertEquals(listOf(3..9), rangesOf("$EMOJI Chapter", "chapter"))
    }

    @Test fun surrogatePairs_before_inside_after_andAsTheQuery() {
        // AFTER the match: the emoji must not disturb an earlier range.
        assertEquals(listOf(0..6), rangesOf("Chapter $EMOJI", "chapter"))
        // INSIDE the matched slice: the range must span all four Chars of "A<emoji>B".
        assertEquals(listOf(0..3), rangesOf("A${EMOJI}B", "a${EMOJI}b"))
        // The query IS the astral code point — two folded Chars, two display Chars.
        assertEquals(listOf(1..2), rangesOf("A${EMOJI}B", EMOJI))
        // CJK Extension B before the match, and as the query. NOTE the braces: CJK characters are
        // valid Kotlin identifier characters, so a bare `$CJK_EXT_B第一章` parses as one enormous
        // identifier name rather than a template followed by text.
        assertEquals(listOf(2..3), rangesOf("${CJK_EXT_B}第一章", "第一"))
        assertEquals(listOf(0..1), rangesOf("${CJK_EXT_B}第一章", CJK_EXT_B))
    }

    @Test fun stackedCombiningMarks_allExtendTheSameBaseCharacter() {
        // "a" + COMBINING ACUTE + COMBINING CEDILLA: BOTH marks must fold into the base char's
        // display span, so the tint covers the whole grapheme rather than stopping after the first.
        assertEquals(listOf(0..2), rangesOf("a$ACUTE$CEDILLA", "a"))
        assertEquals(listOf(0..3), rangesOf("a$ACUTE${CEDILLA}b", "ab"))
    }

    @Test fun orphanCombiningMarkBeforeAMatch_doesNotShiftTheRange() {
        // A leading mark has no preceding folded char to extend, so it is simply not covered — and
        // critically, the FOLLOWING base character's index must still be its own.
        assertEquals(listOf(1..1), rangesOf("${ACUTE}a", "a"))
        assertEquals(listOf(1..7), rangesOf("${ACUTE}Chapter", "chapter"))
    }

    @Test fun lengthChangingFoldAdjacentToAStackedMark() {
        // ß folds to TWO chars and a following mark extends the LAST of them, so a query straddling
        // the boundary still maps back onto the whole ß + mark (you cannot tint half a ß).
        assertEquals(listOf(0..1), rangesOf("ß${ACUTE}x", "ss"))
        assertEquals(listOf(0..2), rangesOf("ß${ACUTE}x", "sx"))
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
        // MEASURED, not assumed. Unicode FULL case folding maps U+FB01 (ﬁ) to "fi" — CaseFolding.txt
        // carries a full mapping for the Latin ligatures — so ICU closes this and Android AGREES
        // with iOS. Plan §3's table predicted "no match" and called it an accepted divergence; that
        // row is an erratum. The implementation follows the plan's normative ALGORITHM (ICU full
        // folding) rather than its predicted table, and this test pins what the algorithm does.
        assertEquals("fi", TocTitleFilter.foldQuery("ﬁ"))
        assertTrue(matches("The ﬁrst Chapter", "fi"))
        // One display char expands to TWO folded chars, so the range is a single Char wide.
        assertEquals(listOf(4..4), rangesOf("The ﬁrst Chapter", "fi"))
    }

    @Test fun arabicHamza_overMatchesVsIos() {
        // NFD + strip-Mn removes the hamza (U+0654, category Mn) that iOS's collation keeps, so
        // Android matches where iOS does not. Over-matching is the benign direction for a title
        // narrower — the user sees a superset, never loses a row. Pinned so a change to the strip
        // rule is deliberate.
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

    @Test fun tocRowText_cannotBeSubclassedOrForgedAnywhere() {
        // The strongest guarantee Kotlin offers, and it is the one this type needs: TocRowText is a
        // SEALED CLASS whose only constructor is PRIVATE, so a subclass — which would have to invoke
        // that constructor — cannot be written even from another file in this same package. Its one
        // implementation is private to the class.
        //
        // Gate-4 history, both rounds, because this seam has now moved twice:
        //  r1: a private constructor plus an `internal` companion factory taking (title, ranges) —
        //      ANY module code could pair one row's title with another row's ranges.
        //  r2: a `sealed interface` + file-private impl — better, but a sealed INTERFACE may still be
        //      implemented by another file in the same package + module, so a forged pair remained
        //      writable.
        // Now: no constructor is reachable, no subtype is writable, and NEITHER factory takes a title
        // and a range list as independent arguments (plain(entry) has no range parameter at all;
        // forRow(corpus, index, query) derives both halves from one index).
        val klass = TocRowText::class.java
        assertFalse("TocRowText must be a sealed CLASS, not an interface", klass.isInterface)
        assertTrue("TocRowText must be abstract", Modifier.isAbstract(klass.modifiers))
        assertTrue(
            "every TocRowText constructor must be private — this is what forbids a subclass",
            klass.declaredConstructors.filterNot { it.isSynthetic }
                .all { Modifier.isPrivate(it.modifiers) },
        )
        assertTrue(
            "TocRowText must not be a data class (no synthesised copy/componentN)",
            klass.declaredMethods.none { it.name == "copy" || it.name.startsWith("component") },
        )
        // The implementation is a private nested class, so a caller cannot even name it.
        val impl = TocTitleFilter.plainRowText(entry("Chapter One")).javaClass
        assertTrue("the implementation must be a subclass, not TocRowText itself", impl != klass)
        assertEquals("the implementation must be nested inside TocRowText", klass, impl.enclosingClass)
        assertTrue("the implementation must be private", Modifier.isPrivate(impl.modifiers))
    }

    @Test fun rowText_rangesAreAnImmutableSnapshotNotTheFoldsOwnList() {
        // Gate-4 round 3, the escape that needed neither a constructor nor a subclass: `matchRanges`
        // was the ArrayList the fold had just built, so `(row.matchRanges as MutableList).clear();
        // addAll(otherRowsRanges)` re-pointed one row's tint at another row's ranges through a
        // nominally read-only List. Both halves of the fix are pinned here — the wrapper (mutation
        // throws) and the copy (no aliasing to the fold).
        val corpus = TocFoldedToc.of(listOf(entry("Chapter One"), entry("A Chapter, Later")))
        val row = corpus.rowText(0, TocTitleFilter.foldQuery("chapter"))
        assertEquals(listOf(0..6), row.matchRanges)

        val stolen = corpus.matchRangesAt(1, TocTitleFilter.foldQuery("chapter"))
        assertEquals("the fixture must give the two rows DIFFERENT ranges", listOf(2..8), stolen)

        @Suppress("UNCHECKED_CAST")
        val asMutable = row.matchRanges as MutableList<IntRange>
        try {
            asMutable.clear()
            fail("row.matchRanges must reject mutation, not silently accept a foreign pairing")
        } catch (expected: UnsupportedOperationException) {
            // exactly what an unmodifiable snapshot does
        }
        try {
            asMutable.addAll(stolen)
            fail("row.matchRanges must reject mutation, not silently accept a foreign pairing")
        } catch (expected: UnsupportedOperationException) {
            // exactly what an unmodifiable snapshot does
        }
        assertEquals("the row's ranges must be unchanged after both attempts", listOf(0..6), row.matchRanges)
    }

    @Test fun tocRowText_hasNoProducerThatAcceptsARawTitleAndRangePair() {
        // The shape assertions above pin "cannot subclass"; this pins "cannot pair". A future edit
        // that re-adds an of(title, ranges) factory to the companion — the round-1 defect — trips
        // here even though the class shape would still look correct.
        val producers = TocRowText.Companion::class.java.declaredMethods.filterNot { it.isSynthetic }
        assertEquals("TocRowText must expose exactly two producers", 2, producers.size)
        assertTrue(
            "no producer may accept a raw (title, ranges) pair — both halves must be derived from " +
                "one entry or one corpus index",
            producers.none { m ->
                m.parameterTypes.firstOrNull() == String::class.java &&
                    m.parameterTypes.any { List::class.java.isAssignableFrom(it) }
            },
        )
    }

    @Test fun matched_cannotBeSubclassedAndOwnsItsIndices() {
        // Hardened to match TocRowText at Gate-4 round 3. The earlier sealed-INTERFACE form could be
        // implemented by another file in this package with inconsistent size/get — which crashes a
        // consumer iterating `0 until size`, not merely misplaces the pinned row, so the asymmetry
        // this test used to claim was not defensible.
        val klass = TocFilterResult.Matched::class.java
        assertFalse("Matched must be a sealed CLASS, not an interface", klass.isInterface)
        assertTrue("Matched must be abstract", Modifier.isAbstract(klass.modifiers))
        assertTrue(
            "every Matched constructor must be private — this is what forbids a subclass",
            klass.declaredConstructors.filterNot { it.isSynthetic }
                .all { Modifier.isPrivate(it.modifiers) },
        )
        assertTrue(
            "Matched must expose no array-typed member (that would leak the ascending invariant)",
            klass.methods.none { it.returnType.isArray },
        )
        val impl = matchedResult(total = 3, 1).javaClass
        assertTrue("the implementation must be a subclass, not Matched itself", impl != klass)
        assertEquals("the implementation must be nested inside Matched", klass, impl.enclosingClass)
        assertTrue("the implementation must be private", Modifier.isPrivate(impl.modifiers))
    }

    // ---- original indices + the pinned-current predicate ------------------------------------------

    @Test fun filter_preservesOriginalIndices() {
        val entries = List(2_000) { if (it == 1_500) entry("Needle Chapter") else entry("第${it}章") }
        assertArrayEquals(intArrayOf(1_500), matchedIndices(filterOf(entries, "needle")))

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
        val result = matchedResult(total = 10, 0, 3, 7)
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, 3))
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, 0))
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, 7))
    }

    @Test fun isActiveFilteredOut_activeFilteredOut_isTrue() {
        val result = matchedResult(total = 10, 0, 3, 7)
        assertTrue(TocTitleFilter.isActiveFilteredOut(result, 4))
        assertTrue(TocTitleFilter.isActiveFilteredOut(result, 9))
        assertTrue(TocTitleFilter.isActiveFilteredOut(matchedResult(total = 10), 0))
        // No active chapter (-1) is not "filtered out" — there is nothing to pin.
        assertFalse(TocTitleFilter.isActiveFilteredOut(result, -1))
    }

    // ---- the count line ----------------------------------------------------------------------------

    @Test fun countLabel_hiddenWhenTrimmedQueryIsBlank() {
        assertNull(TocFilterCountLabel.text(TocFilterResult.Unfiltered, 16, ""))
        assertNull(TocFilterCountLabel.text(matchedResult(total = 16, 4), 16, ""))
    }

    @Test fun countLabel_singularForOneMatch() {
        assertEquals("1 of 16 chapter", TocFilterCountLabel.text(matchedResult(total = 16, 4), 16, "q"))
    }

    @Test fun countLabel_pluralForMany() {
        val result = matchedResult(total = 16, 0, 1, 2, 3, 4)
        assertEquals("5 of 16 chapters", TocFilterCountLabel.text(result, 16, "q"))
    }

    @Test fun countLabel_noMatch() {
        assertEquals("No chapters match", TocFilterCountLabel.text(matchedResult(total = 16), 16, "q"))
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
