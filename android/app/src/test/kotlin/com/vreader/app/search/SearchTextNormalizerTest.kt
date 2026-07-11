package com.vreader.app.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #128 WI-3 — [SearchTextNormalizer]: index/query normalization parity with iOS
 * `SearchTextNormalizer.swift` (order NFKC → full case fold → diacritic strip) + surrogate-safe
 * CJK segmentation. Robolectric-run so the bundled `android.icu` case-fold/normalizer implementation
 * (API 24+) is present under the JVM (the stub android.jar would throw "not mocked").
 */
@RunWith(RobolectricTestRunner::class)
class SearchTextNormalizerTest {

    // MARK: - normalize()

    @Test fun emptyInput_returnsEmpty() {
        assertEquals("", SearchTextNormalizer.normalize(""))
    }

    @Test fun caseFold_asciiLowercases() {
        assertEquals("hello world", SearchTextNormalizer.normalize("HELLO World"))
    }

    @Test fun composedAndDecomposedAccents_normalizeToSameStrippedForm() {
        val composed = "café"                     // é = U+00E9
        val decomposed = "café"             // e + combining acute
        // Both fold to plain "cafe" (diacritic stripped).
        assertEquals("cafe", SearchTextNormalizer.normalize(composed))
        assertEquals("cafe", SearchTextNormalizer.normalize(decomposed))
        assertEquals(
            SearchTextNormalizer.normalize(composed),
            SearchTextNormalizer.normalize(decomposed),
        )
    }

    @Test fun ligatureFi_decomposesViaNfkc() {
        // ﬁ (U+FB01) → "fi" under NFKC compatibility decomposition.
        assertEquals("fi", SearchTextNormalizer.normalize("ﬁ"))
    }

    @Test fun fullWidthLatin_normalizesToHalfWidth() {
        // Full-width digit ０ (U+FF10) + Ａ (U+FF21) → "0a".
        assertEquals("0a", SearchTextNormalizer.normalize("０Ａ"))
    }

    @Test fun halfWidthKana_normalizesToFullWidthViaNfkc() {
        // Halfwidth katakana ｶ (U+FF76) → full-width カ (U+30AB) under NFKC.
        val out = SearchTextNormalizer.normalize("ｶ")
        assertEquals("カ", out)
    }

    @Test fun hangulJamo_composesToSyllableViaNfkc() {
        // Conjoining Jamo ᄒ(U+1112) ᅡ(U+1161) ᆫ(U+11AB) → 한 (U+D55C) under NFKC.
        assertEquals("한", SearchTextNormalizer.normalize("한"))
    }

    @Test fun nonBmpHan_survivesNormalizationIntact() {
        // CJK Ext B 𠀀 (U+20000) — surrogate pair must not be split/dropped.
        val han = String(Character.toChars(0x20000))
        assertEquals(han, SearchTextNormalizer.normalize(han))
    }

    // MARK: - full-case-fold regressions (Gate-2 round-2/3 — why foldCase not lowercase)

    @Test fun germanEszett_foldsToSs() {
        // ß (U+00DF) full-case-folds to "ss" — a query "strasse" must match a book "straße".
        assertEquals("strasse", SearchTextNormalizer.normalize("straße"))
        assertEquals(
            SearchTextNormalizer.normalize("STRASSE"),
            SearchTextNormalizer.normalize("Straße"),
        )
    }

    @Test fun greekFinalSigma_unifiesWithMedialSigma() {
        // Final sigma ς (U+03C2) and medial σ (U+03C3) fold to the same form.
        assertEquals(
            SearchTextNormalizer.normalize("ς"),
            SearchTextNormalizer.normalize("σ"),
        )
        // A word ending in final sigma folds identically to the same word with medial sigma.
        assertEquals(
            SearchTextNormalizer.normalize("οσ"),   // ος (medial)
            SearchTextNormalizer.normalize("ος"),   // ος (final)
        )
    }

    @Test fun cherokee_upperAndLowerFoldIdenticallyToUppercaseCanonical() {
        // Cherokee upper Ꭰ (U+13A0) and its lower Ꭰ (U+AB70) full-case-fold to the SAME string,
        // and that common form is the UPPERCASE canonical representative (Unicode stability policy).
        val upper = "Ꭰ"
        val lower = "ꭰ"
        val normUpper = SearchTextNormalizer.normalize(upper)
        val normLower = SearchTextNormalizer.normalize(lower)
        assertEquals(normUpper, normLower)
        // The canonical fold target is the uppercase code point (not the lowercase one).
        assertEquals(upper, normUpper)
    }

    // MARK: - isCjk() ranges (mirror iOS isCJKCharacter)

    @Test fun isCjk_coversAllIosRanges() {
        assertTrue(SearchTextNormalizer.isCjk(0x4E00))   // CJK Unified
        assertTrue(SearchTextNormalizer.isCjk(0x3400))   // Ext A
        assertTrue(SearchTextNormalizer.isCjk(0x20000))  // Ext B+
        assertTrue(SearchTextNormalizer.isCjk(0xF900))   // Compatibility
        assertTrue(SearchTextNormalizer.isCjk(0xAC00))   // Hangul Syllables
        assertTrue(SearchTextNormalizer.isCjk(0x1100))   // Hangul Jamo
        assertTrue(SearchTextNormalizer.isCjk(0x3130))   // Hangul Compat Jamo
        assertTrue(SearchTextNormalizer.isCjk(0x30A0))   // Katakana
        assertTrue(SearchTextNormalizer.isCjk(0xFF65))   // Halfwidth Katakana
        assertTrue(SearchTextNormalizer.isCjk(0x3040))   // Hiragana
        assertFalse(SearchTextNormalizer.isCjk('a'.code))
        assertFalse(SearchTextNormalizer.isCjk('0'.code))
        assertFalse(SearchTextNormalizer.isCjk(0x00E9))  // é
    }

    // MARK: - segmentCJK()

    @Test fun segmentCjk_emptyReturnsEmpty() {
        assertEquals("", SearchTextNormalizer.segmentCJK(""))
    }

    @Test fun segmentCjk_separatesEachIdeograph() {
        // "关于编程" — each Han char becomes its own token so unicode61 tokenizes individually.
        val out = SearchTextNormalizer.segmentCJK("关于编程")
        assertEquals("关 于 编 程", out.trim())
        // No two adjacent CJK chars are unsegmented.
        assertFalse(out.contains("关于"))
        assertFalse(out.contains("编程"))
    }

    @Test fun segmentCjk_spacesAroundCjkRun_inMixedLatin() {
        val out = SearchTextNormalizer.segmentCJK("hi关ho")
        // A space is inserted around the CJK boundary.
        assertTrue(out.contains(" 关 "))
    }

    @Test fun segmentCjk_nonBmpHan_notSplitMidSurrogate() {
        // Two adjacent non-BMP Han code points must each be its own token, never split
        // in the middle of a surrogate pair.
        val a = String(Character.toChars(0x20000))
        val b = String(Character.toChars(0x20001))
        val out = SearchTextNormalizer.segmentCJK(a + b)
        // Result splits on the code-point boundary: "𠀀 𠀁".
        assertEquals("$a $b", out.trim())
    }

    @Test fun segmentCjk_asciiUnchanged() {
        assertEquals("hello", SearchTextNormalizer.segmentCJK("hello"))
    }
}
