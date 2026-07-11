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
                pageLabel = locator.page?.let { "p. ${it + 1}" },
                dateLabel = dateLabel,
            )

            BookFormat.txt, BookFormat.md -> {
                val offset = (locator.charOffsetUTF16 ?: 0).coerceAtLeast(0)
                val raw = previewProvider?.snippet(offset, PREVIEW_MAX_LEN)
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
     * The rightmost (deepest-in-reading-order) TOC entry whose position is at or before [target], via a
     * binary search over the reading-ordered TOC — O(log n) for huge books. Returns null when the target
     * precedes the first entry or the TOC is empty. The position order is defined by [positionKey]: the
     * book-wide `totalProgression` when present (the Readium/EPUB norm), else in-chapter `progression`
     * (best-effort), so entries authored in reading order stay monotonically ordered by this key.
     */
    private fun nearestTocEntryAtOrAbove(entries: List<TocEntry>, target: Locator): TocEntry? {
        if (entries.isEmpty()) return null
        val targetKey = positionKey(target)
        var lo = 0
        var hi = entries.size - 1
        var found = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (positionKey(entries[mid].canonicalLocator) <= targetKey) {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return if (found >= 0) entries[found] else null
    }

    /**
     * A monotonic ordering key for a locator's reading position: book-wide `totalProgression` when set,
     * else in-chapter `progression`, else 0.0. A reading-ordered EPUB TOC (and the bookmarks that point
     * into it) is monotonic under this key, which is what makes the binary search correct.
     */
    private fun positionKey(locator: Locator): Double =
        locator.totalProgression ?: locator.progression ?: 0.0

    /** Clamp a raw snippet to a single line, at most [maxLen] chars, ellipsized when truncated. */
    private fun clampPreview(raw: String, maxLen: Int): String {
        // Collapse any line breaks (and the surrounding whitespace runs) into single spaces.
        val singleLine = raw.replace(Regex("\\s+"), " ").trim()
        if (singleLine.length <= maxLen) return singleLine
        // Reserve one char for the ellipsis so the total stays <= maxLen.
        return singleLine.take(maxLen - 1).trimEnd() + "…"
    }
}
