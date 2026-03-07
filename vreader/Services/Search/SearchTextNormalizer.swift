// Purpose: Text normalization for search indexing and query processing.
// Applies NFKC, case folding, diacritic folding, full-width → half-width,
// and CJK character segmentation.
//
// Key decisions:
// - Uses Foundation's built-in folding options for maximum compatibility.
// - NFKC applied first to decompose compatibility characters (e.g., ﬁ → fi).
// - Diacritic folding via String.folding(options:) for locale-independent behavior.
// - Full-width → half-width handled by NFKC (Unicode compatibility decomposition).
// - CJK characters are space-separated so FTS5 unicode61 tokenizes them individually.
//   Without this, Chinese/Japanese/Korean text forms one giant token and substring
//   search fails.
// - Stateless enum — all methods are static.
//
// @coordinates-with SearchIndexStore.swift, SearchTokenizer.swift

import Foundation

/// Normalizes text for search indexing and query matching.
enum SearchTextNormalizer {

    /// Applies all normalization steps to the input text.
    ///
    /// Steps (in order):
    /// 1. Unicode NFKC (compatibility decomposition + canonical composition)
    /// 2. Case folding (lowercase)
    /// 3. Diacritic folding (remove combining marks)
    ///
    /// NFKC handles full-width → half-width conversion as part of compatibility decomposition.
    static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        // Step 1: NFKC normalization — decomposes compatibility chars (ﬁ→fi, ０→0, Ａ→A)
        let nfkc = text.precomposedStringWithCompatibilityMapping

        // Step 2+3: Case folding + diacritic folding in one pass
        // .caseInsensitive = lowercase, .diacriticInsensitive = strip combining marks
        let folded = nfkc.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil  // nil = locale-independent
        )

        return folded
    }

    /// Inserts spaces between CJK characters so FTS5 unicode61 tokenizes each
    /// ideograph individually. Without this, a run like "关于编程" is a single
    /// token and searching for "编程" returns no results.
    ///
    /// CJK ranges covered:
    /// - CJK Unified Ideographs (U+4E00–U+9FFF)
    /// - CJK Extension A (U+3400–U+4DBF)
    /// - CJK Extension B+ (U+20000–U+2FA1F)
    /// - CJK Compatibility Ideographs (U+F900–U+FAFF)
    /// - Hangul Syllables (U+AC00–U+D7AF)
    /// - Katakana (U+30A0–U+30FF), Hiragana (U+3040–U+309F)
    static func segmentCJK(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var result = String()
        result.reserveCapacity(text.count * 2)
        var prevWasCJK = false

        for char in text {
            let isCJK = Self.isCJKCharacter(char)
            if isCJK && !result.isEmpty && !prevWasCJK {
                // Non-CJK → CJK boundary: insert space if last char isn't already space
                if result.last != " " {
                    result.append(" ")
                }
            } else if !isCJK && prevWasCJK && char != " " {
                // CJK → non-CJK boundary
                result.append(" ")
            } else if isCJK && prevWasCJK {
                // CJK → CJK: separate each character
                result.append(" ")
            }
            result.append(char)
            prevWasCJK = isCJK
        }
        return result
    }

    /// Checks if a character is a CJK ideograph, kana, or Hangul syllable/jamo.
    static func isCJKCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)      // CJK Unified Ideographs
            || (0x3400...0x4DBF).contains(v)       // CJK Extension A
            || (0x20000...0x2FA1F).contains(v)     // CJK Extension B+
            || (0xF900...0xFAFF).contains(v)       // CJK Compatibility
            || (0xAC00...0xD7AF).contains(v)       // Hangul Syllables
            || (0x1100...0x11FF).contains(v)       // Hangul Jamo
            || (0x3130...0x318F).contains(v)       // Hangul Compatibility Jamo
            || (0x30A0...0x30FF).contains(v)       // Katakana
            || (0xFF65...0xFF9F).contains(v)       // Halfwidth Katakana
            || (0x3040...0x309F).contains(v)       // Hiragana
    }
}
