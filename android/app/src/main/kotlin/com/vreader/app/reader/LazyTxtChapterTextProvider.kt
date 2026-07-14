// Purpose: feature #131 WI-8 — a LAZY ChapterTextProvider decorator so a TXT/MD reader that never
// enables bilingual pays NOTHING for the whole-document paragraph segmentation. TxtChapterTextProvider
// scans the entire document in its constructor (ChapterSegmenter.paragraphRanges), which — before WI-8 —
// no TXT/MD open ran. Building it eagerly per reader open is a regression for large (multi-MB) books
// (round-4 audit High-3). This decorator defers the real provider's construction (and thus the scan) to
// the FIRST unit-resolving call, which only happens once bilingual is actually enabled + prefetching.
//
// Known follow-up (Gate-4 round-2 Medium, ACCEPTED — not blocking): on the FIRST enable, this provider
// AND BilingualTxtAnchors each force one paragraph scan (the provider on the position path, the anchors
// during render) — two scans of the same document. Sharing one off-main span index between them would
// require reshaping the read-only TxtChapterTextProvider (out of WI-8's write-set), so it is left as a
// follow-up; the disabled/non-bilingual open (the common hot path) is already zero-cost.
//
// @coordinates-with: com.vreader.app.bilingual.ChapterTextProvider,
//   com.vreader.app.bilingual.TxtChapterTextProvider, com.vreader.app.bilingual.TranslationUnitId,
//   reader/TxtReaderActivity.kt (WI-8),
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-8)
package com.vreader.app.reader

import com.vreader.app.bilingual.ChapterTextProvider
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.bilingual.TxtChapterTextProvider

/**
 * A [ChapterTextProvider] that constructs its backing [TxtChapterTextProvider] — and runs the
 * whole-document segmentation scan — LAZILY on first use. [document] + [kind] are the same inputs the
 * eager provider takes; the scan happens on the first `units()/sourceSegments/sourceText/unitContaining/
 * unitAfter` call (i.e. only once bilingual prefetch runs), off the reader-open path.
 */
class LazyTxtChapterTextProvider(
    private val document: TxtDocument,
    private val kind: TranslationUnitId.Kind,
) : ChapterTextProvider {

    private val delegate: TxtChapterTextProvider by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        TxtChapterTextProvider(document, kind)
    }

    override fun units(): List<TranslationUnitId> = delegate.units()

    override fun sourceSegments(unit: TranslationUnitId): List<String> = delegate.sourceSegments(unit)

    override fun sourceText(unit: TranslationUnitId): String = delegate.sourceText(unit)

    override fun unitContaining(charOffsetUtf16: Int): TranslationUnitId? =
        delegate.unitContaining(charOffsetUtf16)

    override fun unitAfter(unit: TranslationUnitId): TranslationUnitId? = delegate.unitAfter(unit)
}
