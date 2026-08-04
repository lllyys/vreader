package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-3 — keeps the designed category chip row BOUNDED.
 *
 * The merged feed carries raw logcat tags from the framework and every library (Readium,
 * chromium, `SQLiteLog`, ART, `ziparchive`, …). The design shows a scrollable row of seven chips;
 * production tags left unbounded would render dozens. The rule, in order:
 *
 * 1. a tag that already IS a [DiagnosticsCategory.tag] keeps it (our own entries);
 * 2. a known third-party tag maps onto the nearest designed category via the explicit table below
 *    — explicit, because guessing from substrings mislabels more than it helps;
 * 3. everything else collapses into ONE bucket;
 * 4. the chip row is hard-capped, ranked by entry count.
 *
 * **Filtering still reaches a collapsed entry** — only the CHIP SET is capped, never the data.
 * [chipFor] is the mapping the filter uses, so "show me the bucket" shows every entry that
 * collapsed into it.
 *
 * Rule-51 note for whoever builds the chip row (WI-6a): [COLLAPSED_BUCKET]'s LABEL is not in the
 * design bundle (`DIAG_CATEGORIES` is `All` + the six [DiagnosticsCategory] tags). It is a single
 * named constant precisely so that adjudication happens in one place rather than being scattered
 * through the UI.
 *
 * @coordinates-with DiagnosticsCategory.kt, DiagnosticsLogEntry.kt
 */
object DiagnosticsCategoryBounding {

    /** The design's constant leading chip (`DIAG_CATEGORIES[0]`); never derived from the data. */
    const val ALL: String = "All"

    /** Rule 3's single bucket for every unrecognised raw tag. */
    const val COLLAPSED_BUCKET: String = "Other"

    /**
     * Rule 4's cap: the six designed categories plus the bucket. `All` is additional — it is a
     * filter constant, not a data-derived chip.
     */
    const val MAX_CATEGORY_CHIPS: Int = 7

    private val DESIGNED: Map<String, String> =
        DiagnosticsCategory.entries.associate { it.tag.lowercase() to it.tag }

    /** Rule 2 — exact third-party tags, lowercased for comparison. */
    private val KNOWN_TAGS: Map<String, DiagnosticsCategory> = mapOf(
        // Room / SQLite
        "sqlitelog" to DiagnosticsCategory.PERSISTENCE,
        "sqlitedatabase" to DiagnosticsCategory.PERSISTENCE,
        "sqliteconnectionpool" to DiagnosticsCategory.PERSISTENCE,
        "room" to DiagnosticsCategory.PERSISTENCE,
        // Rendering engines: Readium (EPUB), the WebView (AZW3/foliate), PdfRenderer (PDF)
        "chromium" to DiagnosticsCategory.READER,
        "webviewfactory" to DiagnosticsCategory.READER,
        "readium" to DiagnosticsCategory.READER,
        "epubnavigatorfragment" to DiagnosticsCategory.READER,
        "pdfrenderer" to DiagnosticsCategory.READER,
        // Network: WebDAV backup + OPDS
        "okhttp" to DiagnosticsCategory.SYNC,
        "networksecurityconfig" to DiagnosticsCategory.SYNC,
        "trafficstats" to DiagnosticsCategory.SYNC,
    )

    /** Rule 2 — tag PREFIXES, for families that number their tags (chromium's `cr_*`). */
    private val KNOWN_PREFIXES: List<Pair<String, DiagnosticsCategory>> = listOf(
        "cr_" to DiagnosticsCategory.READER,
        "readium" to DiagnosticsCategory.READER,
    )

    /** The chip an entry with this raw [category] is filed under. Never returns `All`. */
    fun chipFor(category: String): String? {
        val trimmed = category.trim()
        if (trimmed.isEmpty()) return null
        val key = trimmed.lowercase()
        DESIGNED[key]?.let { return it }
        KNOWN_TAGS[key]?.let { return it.tag }
        KNOWN_PREFIXES.firstOrNull { key.startsWith(it.first) }?.let { return it.second.tag }
        return COLLAPSED_BUCKET
    }

    /**
     * The chip row for [entries]: `All` first, then at most [MAX_CATEGORY_CHIPS] chips ranked by
     * entry count (descending), ties broken by the designed order so the row does not reshuffle
     * between two loads that happen to tie.
     */
    fun chips(entries: List<DiagnosticsLogEntry>): List<String> {
        val counts = LinkedHashMap<String, Int>()
        for (entry in entries) {
            val chip = chipFor(entry.category) ?: continue
            counts[chip] = (counts[chip] ?: 0) + 1
        }
        val ranked = counts.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { designedRank(it.key) })
            .take(MAX_CATEGORY_CHIPS)
            .map { it.key }
        return listOf(ALL) + ranked
    }

    /** Designed categories keep their design order; the bucket always sorts last. */
    private fun designedRank(chip: String): Int =
        DiagnosticsCategory.entries.indexOfFirst { it.tag == chip }.takeIf { it >= 0 }
            ?: DiagnosticsCategory.entries.size
}
