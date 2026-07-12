// Purpose: feature #131 WI-1 — the bilingual target-language catalogue. The set
// reproduces the designed `BILINGUAL_LANGS` from
// dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx EXACTLY:
// the same keys, glyphs, and script classification, in the same order. The
// default target is Chinese (the first entry) — matching the design's
// `BILINGUAL_LANGS[0]` fallback.
//
// @coordinates-with: dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx,
//   dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1)
package com.vreader.app.bilingual

/** Writing-system classification, driving glyph shaping / direction downstream. */
enum class BilingualScript {
    latin,
    cjk,
    rtl,
    cyrillic,
}

/**
 * A selectable bilingual target language.
 *
 * @property key the stable language name (persisted; matches the design's `k`).
 * @property glyph the short pill glyph (e.g. "中", "Fr").
 * @property script the writing-system classification.
 */
data class BilingualLanguage(
    val key: String,
    val glyph: String,
    val script: BilingualScript,
)

/** The designed catalogue of bilingual target languages (default = Chinese). */
object BilingualLanguages {

    /** The designed set, in design order (BILINGUAL_LANGS). First entry = default. */
    val ALL: List<BilingualLanguage> = listOf(
        BilingualLanguage("Chinese", "中", BilingualScript.cjk),
        BilingualLanguage("Japanese", "日", BilingualScript.cjk),
        BilingualLanguage("Korean", "한", BilingualScript.cjk),
        BilingualLanguage("Spanish", "Es", BilingualScript.latin),
        BilingualLanguage("French", "Fr", BilingualScript.latin),
        BilingualLanguage("German", "De", BilingualScript.latin),
        BilingualLanguage("Italian", "It", BilingualScript.latin),
        BilingualLanguage("Arabic", "ع", BilingualScript.rtl),
        BilingualLanguage("Russian", "Ru", BilingualScript.cyrillic),
    )

    /** Returns the language whose [BilingualLanguage.key] matches, or Chinese (the default). */
    fun findOrDefault(key: String): BilingualLanguage =
        ALL.firstOrNull { it.key == key } ?: ALL.first()
}
