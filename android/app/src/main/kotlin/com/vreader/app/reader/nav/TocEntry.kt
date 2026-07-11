// Purpose: One flattened table-of-contents row for the reader Contents sheet
// (feature #132 WI-1, box-F reader nav chrome). Carries BOTH the engine-neutral
// canonical vreader `Locator` (identity triple baked in — reused by #135's
// bookmark-from-TOC) AND, for Readium/EPUB hosts, the retained NATIVE Readium
// `Locator` (null for non-Readium hosts) so a TOC jump feeds `navigator.go` its
// own type with zero reconstruction. Produced by a [TocProvider].
package com.vreader.app.reader.nav

import org.readium.r2.shared.publication.Locator as ReadiumLocator
import vreader.contracts.Locator

/**
 * A single chapter/section row of a book's table of contents.
 *
 * @param title       the section title, or null when the source link is untitled.
 * @param depth       nesting depth in the TOC tree (0 = top level).
 * @param pageLabel   a display page label (Readium `locations.position` as a string),
 *                    or null when the source has no position.
 * @param canonicalLocator the engine-neutral vreader [Locator] with the book identity
 *                    triple baked in — persisted/reused (#135 bookmark-from-TOC).
 * @param epubReadiumLocator the retained native Readium [ReadiumLocator] for a
 *                    zero-reconstruction `navigator.go` jump; null for non-Readium hosts.
 */
data class TocEntry(
    val title: String?,
    val depth: Int,
    val pageLabel: String?,
    val canonicalLocator: Locator,
    val epubReadiumLocator: ReadiumLocator?,
)
