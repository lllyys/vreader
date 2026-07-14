// Purpose: feature #131 WI-7b — the EPUB ChapterTextProvider (plan §171). Unlike TXT/MD
// (which key on a UTF-16 char offset), EPUB keys a translation UNIT on the CURRENT resource
// href — the honest divergence from iOS's uniform Readium Locator (the iOS Locator carries an
// href; Android's TXT/MD path carries a char offset, so the shared ChapterTextProvider seam
// exposes both). `units()` = the publication's spine hrefs in reading order; `unitAfter(unit)`
// = the next spine href or null at the end; `sourceSegments(unit)` is the render's OWN
// DOM-enumerated block texts (direct-block 1:1) — but the DOM enumeration lives in the
// controller (it needs the live navigator), so the provider does NOT re-enumerate: it holds no
// per-resource text and returns the empty list for `sourceSegments`/`sourceText`. The provider
// exists so the controller/VM seam is uniform; the controller keys the current unit off
// `nav.currentLocator.href`, not off a char offset (`unitContaining` returns null — an EPUB
// position is an href, not an offset).
//
// Built ONCE per open book from the spine href list the ReaderActivity extracts from
// `publication.readingOrder` (a plain `List<String>`, so the provider stays pure/JVM-testable —
// the same seam posture ReadiumTocProvider uses because Readium's Publication is a final class).
//
// @coordinates-with: ChapterTextProvider.kt, TranslationUnitId.kt, EpubBilingualController.kt,
//   reader/ReaderActivity.kt (extracts the spine hrefs),
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-7b §171)
package com.vreader.app.bilingual

/**
 * A [ChapterTextProvider] over an EPUB publication's spine, keyed by resource href.
 *
 * @param spineHrefs the publication's reading-order resource hrefs (extracted by the host from
 *   `publication.readingOrder`, in order). Duplicates are de-duplicated preserving first order;
 *   blank hrefs are dropped. The list may be empty (a publication with no reading order).
 */
class EpubChapterTextProvider(spineHrefs: List<String>) : ChapterTextProvider {

    /** The de-duplicated, non-blank spine hrefs in reading order — the unit ordering basis. */
    private val hrefs: List<String> = spineHrefs.filter { it.isNotBlank() }.distinct()

    /** Each spine href as an `epubHref` unit, in reading order. */
    private val unitsInOrder: List<TranslationUnitId> =
        hrefs.map { TranslationUnitId(TranslationUnitId.Kind.epubHref, it) }

    override fun units(): List<TranslationUnitId> = unitsInOrder

    /**
     * The EPUB divergence: a unit's source segments are the render's OWN DOM-enumerated leaf
     * blocks, which require the live navigator — so the provider (pure, no navigator) returns
     * the empty list here. The controller enumerates the blocks directly from the navigator
     * and drives the direct-block translate; it never asks the provider for source segments.
     */
    override fun sourceSegments(unit: TranslationUnitId): List<String> = emptyList()

    /** No plain-text source for an EPUB unit at the provider layer (see [sourceSegments]). */
    override fun sourceText(unit: TranslationUnitId): String = ""

    /**
     * An EPUB position is an href, NOT a UTF-16 char offset — so this offset-keyed resolver
     * returns null by construction (the honest divergence). The controller keys the current
     * unit off `nav.currentLocator.href` via [unitForHref], not this method.
     */
    override fun unitContaining(charOffsetUtf16: Int): TranslationUnitId? = null

    /** The unit after [unit] in spine order, or null at the end (or when [unit] is unknown). */
    override fun unitAfter(unit: TranslationUnitId): TranslationUnitId? {
        val i = unitsInOrder.indexOf(unit)
        if (i < 0 || i + 1 >= unitsInOrder.size) return null
        return unitsInOrder[i + 1]
    }

    /**
     * The EPUB-specific resolver: the `epubHref` unit for a live resource [href], or null when
     * [href] is blank or not part of the spine. This is the controller's entry point (it reads
     * `nav.currentLocator.href`), replacing the offset-based [unitContaining] for EPUB.
     */
    fun unitForHref(href: String): TranslationUnitId? {
        val clean = href.takeIf { it.isNotBlank() } ?: return null
        return unitsInOrder.firstOrNull { it.value == clean }
    }
}
