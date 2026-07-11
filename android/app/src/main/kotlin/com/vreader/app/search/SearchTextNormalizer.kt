// Purpose: Text normalization for library search indexing + query processing — feature #128 WI-3.
// Mirrors the iOS SearchTextNormalizer.swift so the Android index and query normalize identically
// to iOS: NFKC → FULL Unicode case fold → diacritic strip, then CJK per-code-point segmentation.
//
// Key decisions:
// - NFKC first (java.text.Normalizer.Form.NFKC) — the iOS `precomposedStringWithCompatibilityMapping`
//   analog: folds ligatures (ﬁ→fi), full-width→half-width (０→0 Ａ→A), half-width→full-width kana,
//   and composes conjoining Hangul Jamo.
// - Full case fold via android.icu.lang.UCharacter.foldCase (NOT lowercase): folds ß→ss, unifies the
//   Greek final/medial sigma, and maps Cherokee to its UPPERCASE canonical form (Unicode stability
//   policy) — case-variant classes lowercasing would miss. Locale-independent by construction
//   (matches iOS `.caseInsensitive` with locale: nil). android.icu is bundled from API 24 (< minSdk 26).
// - Diacritic strip last (NFD decompose then drop \p{Mn}) — the iOS `.diacriticInsensitive` analog.
// - CJK segmentation iterates by CODE POINT so surrogate pairs (non-BMP Han) are never split.
//   The SAME normalize + segmentCJK pipeline runs on BOTH the index and query paths.
package com.vreader.app.search

import android.icu.lang.UCharacter
import android.icu.text.Normalizer2
import java.text.Normalizer

/** Normalizes text for search indexing and query matching (index/query parity with iOS). */
object SearchTextNormalizer {

    // NFD instance for the diacritic-strip pass (decompose canonical, drop combining marks).
    private val nfd: Normalizer2 = Normalizer2.getNFDInstance()

    /**
     * Applies all normalization steps, in order:
     * 1. Unicode NFKC (compatibility decomposition + canonical composition).
     * 2. FULL Unicode case fold (ß→ss, final sigma, Cherokee→uppercase canonical).
     * 3. Diacritic strip (NFD decompose, drop combining marks U+0300..U+036F etc.).
     */
    fun normalize(text: String): String {
        if (text.isEmpty()) return ""
        // 1. NFKC.
        val nfkc = Normalizer.normalize(text, Normalizer.Form.NFKC)
        // 2. Full case fold (locale-independent). FOLD_CASE_DEFAULT so dotted/dotless-I fold the
        //    default Unicode way (Turkish-İ NOT special-cased — matches iOS locale:nil).
        val folded = UCharacter.foldCase(nfkc, UCharacter.FOLD_CASE_DEFAULT)
        // 3. Diacritic strip: NFD decompose then drop combining marks (general category Mn).
        return stripDiacritics(folded)
    }

    private fun stripDiacritics(text: String): String {
        // NFD decomposes canonical (exposes combining marks AND splits precomposed Hangul into Jamo).
        val decomposed = nfd.normalize(text)
        val sb = StringBuilder(decomposed.length)
        var i = 0
        while (i < decomposed.length) {
            val cp = decomposed.codePointAt(i)
            // Drop non-spacing combining marks (general category Mn) — the diacritics.
            if (Character.getType(cp) != Character.NON_SPACING_MARK.toInt()) {
                sb.appendCodePoint(cp)
            }
            i += Character.charCount(cp)
        }
        // Recompose (NFC) so precomposed forms return to canonical (Hangul syllables re-form from
        // Jamo; base letters recombine) — matches iOS `.diacriticInsensitive`, which leaves output
        // composed, not decomposed.
        return Normalizer.normalize(sb, Normalizer.Form.NFC)
    }

    /**
     * Inserts a space around each CJK code point so FTS unicode61 tokenizes each ideograph
     * individually (without this, a run like "关于编程" is one token and substring search fails).
     * Iterates by CODE POINT so surrogate pairs (non-BMP Han, Ext B+) are never split.
     */
    fun segmentCJK(text: String): String {
        if (text.isEmpty()) return ""
        val result = StringBuilder(text.length * 2)
        var prevWasCJK = false
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val isCJK = isCjk(cp)
            val ch = String(Character.toChars(cp))
            when {
                isCJK && result.isNotEmpty() && !prevWasCJK -> {
                    // Non-CJK → CJK boundary: insert a space unless one is already present.
                    if (result.last() != ' ') result.append(' ')
                }
                !isCJK && prevWasCJK && ch != " " -> {
                    // CJK → non-CJK boundary.
                    result.append(' ')
                }
                isCJK && prevWasCJK -> {
                    // CJK → CJK: separate each ideograph.
                    result.append(' ')
                }
            }
            result.append(ch)
            prevWasCJK = isCJK
            i += Character.charCount(cp)
        }
        return result.toString()
    }

    /**
     * Whether [codePoint] is a CJK ideograph, kana, or Hangul syllable/jamo — the SAME ranges as
     * iOS `isCJKCharacter`.
     */
    fun isCjk(codePoint: Int): Boolean =
        codePoint in 0x4E00..0x9FFF        // CJK Unified Ideographs
            || codePoint in 0x3400..0x4DBF    // CJK Extension A
            || codePoint in 0x20000..0x2FA1F  // CJK Extension B+
            || codePoint in 0xF900..0xFAFF    // CJK Compatibility Ideographs
            || codePoint in 0xAC00..0xD7AF    // Hangul Syllables
            || codePoint in 0x1100..0x11FF    // Hangul Jamo
            || codePoint in 0x3130..0x318F    // Hangul Compatibility Jamo
            || codePoint in 0x30A0..0x30FF    // Katakana
            || codePoint in 0xFF65..0xFF9F    // Halfwidth Katakana
            || codePoint in 0x3040..0x309F    // Hiragana
}
