// Purpose: feature #135 WI-4 — the PURE, read-time per-format bookmark presentation projection. Turns
// a stored BookmarkRecord into a display row (BookmarkRowUi) DERIVED every call (Risk-7: preview/chapter
// are NEVER stored). Per format: EPUB/AZW3 = nearest-at-or-above TOC chapter via a PREVALIDATED
// BookmarkTocIndex (built once, O(n); each lookup is O(log n) when the TOC is complete+monotonic in
// totalProgression — the Readium/EPUB norm/huge-book path — else an href-exact fallback) + that entry's
// page label; PDF = "p. N" (one-based); TXT/MD = a host-supplied snippet, clamped <=120 single-line
// ellipsized. Date is deterministic (injected zone+formatter — no now()/default-locale). No
// Android/Compose deps, no I/O (rule 50 boundary): every absence path (no TOC / no provider / null
// offset / invalid page) returns null fields, never a crash. Feeds WI-6's Bookmarks surface + WI-7's
// host wiring (TXT supplies the provider; the host builds the BookmarkTocIndex once per TOC).
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

/**
 * A prevalidated, searchable view of a book's reading-ordered TOC for EPUB/AZW3 bookmark-chapter lookup.
 *
 * Built ONCE per TOC via [build] (O(n)) — the caller (WI-6/WI-7 host) constructs it when the TOC loads
 * and reuses it across every bookmark row, so a list of `m` bookmarks costs `O(n + m·log n)`, never
 * `O(n·m)`. Building validates the invariant the fast lookup needs — that EVERY entry carries a
 * book-wide `totalProgression` AND the sequence is non-decreasing (the Readium/EPUB norm) — so
 * [nearest] can trust it and binary-search in O(log n). When the TOC violates that invariant (a
 * partially-populated / out-of-order TOC), [nearest] degrades to an href-exact match, which is correct
 * for those degraded cases (and bounded by the few same-href entries). This is exactly the "validate
 * once, then a trusted searchable structure" shape the auditor required, instead of trying to prove
 * global completeness+monotonicity inside every O(log n) lookup.
 */
class BookmarkTocIndex private constructor(
    private val entries: List<TocEntry>,
    /** True iff every entry has a non-null totalProgression AND the sequence is non-decreasing. */
    private val monotonicByTotalProgression: Boolean,
) {
    /**
     * The nearest chapter at or before [target]:
     *  - **complete+monotonic TOC** → O(log n) binary search on `totalProgression` for the rightmost
     *    entry `<=` the target's `totalProgression` (null target key → href fallback, no fabrication);
     *  - **degraded TOC** → href-exact fallback (last same-href entry at/before the in-chapter
     *    `progression`).
     * Returns null (never a fabricated chapter) when the target can't be placed / the TOC is empty.
     */
    fun nearest(target: Locator): TocEntry? {
        if (entries.isEmpty()) return null
        val targetTotal = target.totalProgression
        if (monotonicByTotalProgression && targetTotal != null) {
            return binarySearchAtOrBelow(targetTotal)
        }
        return hrefFallback(target)
    }

    /** Rightmost entry whose `totalProgression <= [targetTotal]` (O(log n)); null before the first entry. */
    private fun binarySearchAtOrBelow(targetTotal: Double): TocEntry? {
        var lo = 0
        var hi = entries.size - 1
        var found = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            // Non-null by the build-time invariant (monotonicByTotalProgression implies all present).
            val key = entries[mid].canonicalLocator.totalProgression!!
            if (key <= targetTotal) {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return if (found >= 0) entries[found] else null
    }

    /**
     * The last TOC entry whose `href` matches the target's and whose in-chapter `progression` is at or
     * before the target's — the chapter the bookmark lives in. Null when no entry shares the href.
     */
    private fun hrefFallback(target: Locator): TocEntry? {
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

    companion object {
        /**
         * Build the index from a reading-ordered TOC, validating the fast-path invariant in a SINGLE
         * O(n) pass. The caller owns the TOC's immutability (it is loaded once and not mutated), so the
         * list is retained by reference rather than defensively copied — a copy would double the O(n)
         * build cost for a huge book to no benefit given the ownership contract.
         */
        fun build(entries: List<TocEntry>): BookmarkTocIndex {
            var monotonic = true
            var prev: Double? = null
            for (entry in entries) {
                val tp = entry.canonicalLocator.totalProgression
                if (tp == null) { monotonic = false; break }
                if (prev != null && tp < prev) { monotonic = false; break }
                prev = tp
            }
            return BookmarkTocIndex(entries, monotonic)
        }
    }
}

/** The pure per-format bookmark → display-row projection. */
object BookmarkPresentation {

    /** The TXT/MD preview cap — bounded so a huge document can't blow up a row. */
    const val PREVIEW_MAX_LEN: Int = 120

    /**
     * Project [record] to its display row for [format].
     *
     * @param tocIndex a PREVALIDATED [BookmarkTocIndex] for EPUB/AZW3 chapter lookup (built once from the
     *   TOC and reused across rows — see [BookmarkTocIndex]); null degrades to a null chapter.
     * @param previewProvider the TXT/MD host's snippet source; null (or a null return) degrades to a null
     *   preview.
     * @param dateRenderer the deterministic date formatter (injected zone+formatter).
     */
    fun bookmarkRow(
        record: BookmarkRecord,
        format: BookFormat,
        tocIndex: BookmarkTocIndex?,
        previewProvider: BookmarkPreviewProvider?,
        dateRenderer: BookmarkDateRenderer,
    ): BookmarkRowUi {
        val locator = record.locator
        val dateLabel = dateRenderer.render(record.createdAt)

        return when (format) {
            BookFormat.epub, BookFormat.azw3 -> {
                val entry = tocIndex?.nearest(locator)
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

    /** Clamp a raw snippet to a single line, at most [maxLen] chars, ellipsized when truncated. */
    private fun clampPreview(raw: String, maxLen: Int): String {
        // Collapse any line breaks (and the surrounding whitespace runs) into single spaces.
        val singleLine = raw.replace(Regex("\\s+"), " ").trim()
        if (singleLine.length <= maxLen) return singleLine
        // Reserve one char for the ellipsis so the total stays <= maxLen.
        return singleLine.take(maxLen - 1).trimEnd() + "…"
    }
}
