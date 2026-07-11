// Purpose: feature #132 WI-7-EPUB (#110 Phase 3) — the persistent chrome model the EPUB host's
// (ReaderActivity) top/bottom touch-through ComposeView bands + Notes sheet collect via a
// MutableStateFlow. The EPUB host is the ONLY TOC-supplying host and the outlier (a Readium
// EpubNavigatorFragment View under the chrome, not a Compose body), so it cannot reuse the Compose-native
// ReaderChromeScaffold; instead it feeds this immutable model into separately-sized chrome bands. The
// model carries the book title, the flattened TOC (WI-1 [TocEntry], each retaining its native Readium
// locator for the jump), the highlighted-chapter index, and the Notes review snapshot. [tocIndexFor] is
// the pure JVM-testable core: map the live reading position (href + progression) to the nearest/containing
// TOC entry so the Contents sheet highlights the current chapter as the reader scrolls.
// @coordinates-with: ReaderActivity.kt (owns the MutableStateFlow, populates + updates it), EpubReaderChrome.kt
//   (renders the bands + sheets from it), nav/TocEntry.kt + nav/ReadiumTocProvider.kt (the TOC source).
package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.reader.nav.TocEntry

/**
 * The persistent EPUB-reader chrome model. [title] fills the top band; [tocEntries] is the flattened TOC
 * (WI-1) that drives the Contents sheet (empty → Contents control hidden); [currentTocIndex] is the
 * highlighted chapter row (-1 when there is no TOC or no positional signal maps to a row); [annotations]
 * is the one-shot Notes snapshot. Immutable — the host rebuilds it (or `copy`es a single field) and emits
 * a new value onto the [kotlinx.coroutines.flow.MutableStateFlow] the chrome bands collect.
 */
data class ReaderChromeModel(
    val title: String = "",
    val tocEntries: List<TocEntry> = emptyList(),
    val currentTocIndex: Int = -1,
    val annotations: AnnotationsSnapshot = AnnotationsSnapshot(emptyList(), emptyList()),
)

/**
 * A plain (Readium-free) descriptor of a TOC entry's reading position — its spine href and intra-chapter
 * progression. Extracted from each [TocEntry]'s retained native `epubReadiumLocator` by the host (via
 * [tocPositions]) so [tocIndexFor] stays pure/JVM-testable (no Readium/Robolectric dependency). A null
 * [progression] is treated as 0.0 (chapter start).
 */
data class TocPosition(val href: String?, val progression: Double?)

/**
 * Extract the plain [TocPosition] descriptors from [tocEntries] — this is the ONE hop that touches the
 * Readium types (`epubReadiumLocator.href` / `.locations.progression`), keeping [tocIndexFor] itself pure.
 * The host calls this on the current TOC and hands the result (plus the live reading href/progression,
 * read from the navigator's `currentLocator`) to [tocIndexFor].
 */
fun tocPositions(tocEntries: List<TocEntry>): List<TocPosition> =
    tocEntries.map { entry ->
        val loc = entry.epubReadiumLocator
        TocPosition(href = loc?.href?.toString(), progression = loc?.locations?.progression)
    }

/**
 * The index of the TOC entry that best represents the live reading position ([currentHref] +
 * [currentProgression]) among [positions] — i.e. the current chapter/section row to highlight in the
 * Contents sheet. [positions] are the plain descriptors from [tocPositions] (one per TOC entry, same
 * order), so this function is Readium-free and pure/JVM-testable.
 *
 * Rule (spine-ordered TOC): the current entry is the LAST entry whose position is at-or-before the
 * reading position, comparing first by spine order (href, ascending) then by intra-chapter progression.
 * Edge behavior:
 *  - empty [positions] → -1 (there is no row to highlight);
 *  - a non-empty TOC but no entry is at-or-before the reading position (the reading href sorts before
 *    every entry, or there is no positional signal) → 0 (highlight the first row, never -1 when a TOC
 *    exists — a missing-highlight state is worse than a best-effort first row).
 *
 * Pure function of its inputs (rule 50 §pure) — no side effects, no Readium types.
 */
fun tocIndexFor(
    currentHref: String?,
    currentProgression: Double?,
    positions: List<TocPosition>,
): Int {
    if (positions.isEmpty()) return -1
    if (currentHref == null) return 0

    val readProg = currentProgression ?: 0.0
    var best = -1
    positions.forEachIndexed { index, pos ->
        val entryHref = pos.href
        val entryProg = pos.progression ?: 0.0
        // At-or-before the reading position: an earlier href, or the same href at-or-before progression.
        val atOrBefore = when {
            entryHref == null -> false
            entryHref < currentHref -> true
            entryHref == currentHref -> entryProg <= readProg
            else -> false
        }
        if (atOrBefore) best = index
    }
    // No entry at-or-before → default to the first row (a TOC exists; never -1 here).
    return if (best >= 0) best else 0
}
