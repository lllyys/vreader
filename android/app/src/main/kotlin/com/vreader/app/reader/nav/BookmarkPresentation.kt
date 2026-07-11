// Purpose: feature #135 WI-4 — the PURE, read-time per-format bookmark presentation projection. Turns
// a stored BookmarkRecord into a display row (BookmarkRowUi) DERIVED every call (Risk-7: preview/chapter
// are NEVER stored). Per format: EPUB/AZW3 = nearest-at-or-above TOC entry via an O(log n) binary search
// over the ordered TOC (huge-book safe) + that entry's page label; PDF = "p. N" (one-based); TXT/MD = a
// host-supplied snippet, clamped <=120 single-line ellipsized. Date is deterministic (injected
// zone+formatter — no now()/default-locale). No Android/Compose deps, no I/O (rule 50 boundary): every
// absence path (no TOC / no provider / null offset / offset out of range) returns null fields, never a
// crash. Feeds WI-6's Bookmarks surface + WI-7's host wiring (TXT supplies the provider).
package com.vreader.app.reader.nav

import com.vreader.app.annotations.BookmarkRecord
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** The per-format display projection of one bookmark (all fields are read-time-derived, never stored). */
data class BookmarkRowUi(
    /** TXT/MD only: a bounded, single-line, ellipsized body snippet; null otherwise / when unavailable. */
    val preview: String?,
    /** EPUB/AZW3 only: the nearest-at-or-above TOC chapter title; null otherwise / before the first entry. */
    val chapter: String?,
    /** EPUB/AZW3: the TOC entry's page label; PDF: "p. N" (one-based); null otherwise. */
    val pageLabel: String?,
    /** A deterministic formatted creation date (never localised to a machine default). */
    val dateLabel: String,
)

/**
 * Deterministic date renderer for a bookmark row. Injecting the [zone] + [formatter] makes the label
 * exact-string-assertable and free of `now()`/default-locale non-determinism.
 */
class BookmarkDateRenderer(
    private val zone: ZoneId,
    private val formatter: DateTimeFormatter,
) {
    /** Format an epoch-millis timestamp in the fixed zone with the fixed formatter. */
    fun render(epochMillis: Long): String =
        formatter.format(Instant.ofEpochMilli(epochMillis).atZone(zone))
}

/** The pure per-format bookmark → display-row projection. */
object BookmarkPresentation {

    /** The TXT/MD preview cap — bounded so a huge document can't blow up a row. */
    const val PREVIEW_MAX_LEN: Int = 120

    /**
     * Project [record] to its display row for [format].
     *
     * @param tocEntries the ordered (reading-order) TOC for EPUB/AZW3 chapter lookup; null/empty degrades
     *   to a null chapter. MUST be indexable in O(1) — the lookup binary-searches it (O(log n)).
     * @param previewProvider the TXT/MD host's snippet source; null (or a null return) degrades to a null
     *   preview.
     * @param dateRenderer the deterministic date formatter (injected zone+formatter).
     */
    fun bookmarkRow(
        record: BookmarkRecord,
        format: BookFormat,
        tocEntries: List<TocEntry>?,
        previewProvider: BookmarkPreviewProvider?,
        dateRenderer: BookmarkDateRenderer,
    ): BookmarkRowUi {
        val locator = record.locator
        val dateLabel = dateRenderer.render(record.createdAt)

        return when (format) {
            BookFormat.epub, BookFormat.azw3 -> {
                val entry = tocEntries?.let { nearestTocEntryAtOrAbove(it, locator) }
                BookmarkRowUi(
                    preview = null,
                    chapter = entry?.title,
                    pageLabel = entry?.pageLabel,
                    dateLabel = dateLabel,
                )
            }

            BookFormat.pdf -> BookmarkRowUi(
                preview = null,
                chapter = null,
                // One-based, and only for a valid (non-negative, non-overflowing) page index.
                pageLabel = locator.page
                    ?.takeIf { it in 0 until Int.MAX_VALUE }
                    ?.let { "p. ${it + 1}" },
                dateLabel = dateLabel,
            )

            BookFormat.txt, BookFormat.md -> {
                // A missing position yields NO preview (do not fabricate a start-of-book snippet);
                // a stored-but-negative offset is defensively clamped to 0.
                val raw = locator.charOffsetUTF16
                    ?.let { previewProvider?.snippet(it.coerceAtLeast(0), PREVIEW_MAX_LEN) }
                BookmarkRowUi(
                    preview = raw?.let { clampPreview(it, PREVIEW_MAX_LEN) },
                    chapter = null,
                    pageLabel = null,
                    dateLabel = dateLabel,
                )
            }
        }
    }

    /**
     * The nearest TOC chapter at or before [target] — the row's chapter. Two strategies, both safe:
     *
     * 1. **Fast path (huge-book O(log n)):** when the target carries a book-wide `totalProgression` (the
     *    Readium/EPUB norm — the only key guaranteed monotonic across chapters), binary-search the
     *    reading-ordered TOC for the rightmost entry whose `totalProgression <=` the target's. The
     *    monotonic-ness precondition is checked WHILE searching (never via an O(n) prescan, which would
     *    defeat the huge-book bound): if any entry visited by the search lacks `totalProgression`, the
     *    TOC is not reliably monotonic under that key, so the search aborts to strategy 2. A fully
     *    populated Readium TOC never aborts, so this stays O(log n) for huge books.
     * 2. **Href fallback (correctness for partially-populated TOCs):** match on the target's `href` — the
     *    chapter file the bookmark points into — picking the last same-href entry at or before the
     *    target's in-chapter `progression`. This is what keeps a partial TOC correct: mixing book-wide
     *    `totalProgression` with chapter-local `progression` would break the binary search's monotonicity
     *    invariant and return the wrong chapter. Same-href entries are few (typically one).
     *
     * Returns null (no fabricated chapter) when the target precedes the first entry, the TOC is empty,
     * or no strategy can place it.
     */
    private fun nearestTocEntryAtOrAbove(entries: List<TocEntry>, target: Locator): TocEntry? {
        if (entries.isEmpty()) return null
        val targetTotal = target.totalProgression
        if (targetTotal != null) {
            binarySearchAtOrBelow(entries, targetTotal)?.let { return it.entryOrNull }
            // Search aborted (a visited entry lacked totalProgression) -> fall through.
        }
        return hrefFallback(entries, target)
    }

    /**
     * Wraps a binary-search outcome so an *aborted* search (a visited entry lacked `totalProgression`)
     * is distinguishable from a completed search that legitimately found nothing.
     */
    private data class SearchOutcome(val entryOrNull: TocEntry?)

    /**
     * Rightmost entry whose `totalProgression <= [targetTotal]`, via binary search (O(log n)). Returns
     * null (an ABORT) the moment a visited entry lacks `totalProgression` — the caller then degrades to
     * the href fallback; a completed search returns a [SearchOutcome] (whose [entryOrNull] may itself be
     * null when the target precedes the first entry).
     */
    private fun binarySearchAtOrBelow(entries: List<TocEntry>, targetTotal: Double): SearchOutcome? {
        var lo = 0
        var hi = entries.size - 1
        var found = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val key = entries[mid].canonicalLocator.totalProgression ?: return null // abort: not monotonic
            if (key <= targetTotal) {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return SearchOutcome(if (found >= 0) entries[found] else null)
    }

    /**
     * The last TOC entry whose `href` matches the target's and whose in-chapter `progression` is at or
     * before the target's — the chapter the bookmark lives in. Null when no entry shares the href.
     */
    private fun hrefFallback(entries: List<TocEntry>, target: Locator): TocEntry? {
        val href = target.href ?: return null
        val targetProg = target.progression ?: 0.0
        var best: TocEntry? = null
        for (entry in entries) {
            val loc = entry.canonicalLocator
            if (loc.href != href) continue
            if ((loc.progression ?: 0.0) <= targetProg) best = entry
        }
        return best
    }

    /** Clamp a raw snippet to a single line, at most [maxLen] chars, ellipsized when truncated. */
    private fun clampPreview(raw: String, maxLen: Int): String {
        // Collapse any line breaks (and the surrounding whitespace runs) into single spaces.
        val singleLine = raw.replace(Regex("\\s+"), " ").trim()
        if (singleLine.length <= maxLen) return singleLine
        // Reserve one char for the ellipsis so the total stays <= maxLen.
        return singleLine.take(maxLen - 1).trimEnd() + "…"
    }
}
