// Purpose: Text normalization for search indexing and query processing.
// Applies NFKC, case folding, diacritic folding, and full-width → half-width conversion.
//
// Key decisions:
// - Uses Foundation's built-in folding options for maximum compatibility.
// - NFKC applied first to decompose compatibility characters (e.g., ﬁ → fi).
// - Diacritic folding via String.folding(options:) for locale-independent behavior.
// - Full-width → half-width handled by NFKC (Unicode compatibility decomposition).
// - Stateless enum — all methods are static.
//
// @coordinates-with SearchIndexStore.swift

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
}
