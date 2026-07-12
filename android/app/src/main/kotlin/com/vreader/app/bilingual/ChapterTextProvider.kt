// Purpose: feature #131 WI-4a — the host-agnostic addressing seam between the
// reader's saved position (a UTF-16 char offset) and a bilingual translation
// UNIT (the cache/prefetch granularity). A `ChapterTextProvider` resolves which
// unit contains a given offset, enumerates the source segments of a unit, and
// walks to the next unit — so the VM/prefetcher can drive current+next prefetch
// without knowing whether the host is TXT/MD (offset-addressed) or EPUB
// (href-addressed). This is the honest divergence from iOS's uniform Readium
// `Locator`: TXT/MD key on `charOffsetUtf16`, EPUB keys on the resource href.
//
// @coordinates-with: TxtChapterTextProvider.kt, TranslationUnitId.kt,
//   ChapterTranslationPrefetcher.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-4a)
package com.vreader.app.bilingual

/**
 * Maps a reader position to a bilingual translation [TranslationUnitId] and
 * exposes the source text of a unit. Resolution is host-specific:
 * - TXT/MD key on the saved UTF-16 char offset → the segment window it falls in;
 * - EPUB keys on the current resource href.
 *
 * All methods are pure (no I/O): a provider is built ONCE over a document and
 * answers from its precomputed segment spans.
 */
interface ChapterTextProvider {

    /** Every translation unit in the document, in reading order. */
    fun units(): List<TranslationUnitId>

    /** The ordered source segment strings of [unit] (one per translatable segment). */
    fun sourceSegments(unit: TranslationUnitId): List<String>

    /** The joined source text of [unit] (the segments concatenated for a plain-text translate). */
    fun sourceText(unit: TranslationUnitId): String

    /**
     * The unit whose source contains the reader's saved UTF-16 [charOffsetUtf16],
     * or null when the document has no translatable content. An out-of-range
     * offset clamps to the nearest end (never returns null just because the offset
     * is past EOF).
     */
    fun unitContaining(charOffsetUtf16: Int): TranslationUnitId?

    /** The unit after [unit] in reading order, or null at the document's end. */
    fun unitAfter(unit: TranslationUnitId): TranslationUnitId?
}
