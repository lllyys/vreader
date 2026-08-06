// Purpose: feature #142 WI-2 — maps between the foliate-js (AZW3/MOBI/KF8) selection world and the
// annotation domain. A `selection` bridge message -> (canonical Locator + AnnotationAnchor.Epub +
// selectedText) for persistence; a stored highlight -> the CFI handed back to
// `readerAPI.addAnnotation`/`deleteAnnotation` to re-paint it; a tapped CFI -> the highlight it
// belongs to. The `EpubAnnotationMapper` analog for the Foliate render path (iOS parity:
// FoliateSpikeView+Selection.swift and FoliateHighlightTapResolver.swift).
//
// Kept free of Compose/Activity/WebView so the whole mapping is unit-testable; the bridge wiring
// lives in Azw3Document (WI-4) and the host wiring in Azw3ReaderAnnotations (WI-5/WI-6).
//
// @coordinates-with: FoliateMessage.kt (Selection), AnnotationAnchor.kt, Annotation.kt
//   (HighlightRecord), AnnotationsRepository.kt (restoreAnnotations — the anchor-less restore path)
package com.vreader.app.annotations

import com.vreader.app.data.Book
import com.vreader.app.reader.foliate.FoliateMessage
import vreader.contracts.Locator

/** The persistable inputs derived from a foliate selection (the [EpubSelectionInputs] analog). */
data class Azw3SelectionInputs(
    val selectedText: String,
    val locator: Locator,
    val anchor: AnnotationAnchor.Epub,
)

object Azw3AnnotationMapper {

    /**
     * Derive the persistable inputs from a foliate [FoliateMessage.Selection]. Returns null when the
     * selection is unusable — without text there is nothing to store, without a CFI nothing to
     * anchor or re-paint. (The parser already rejects both, so this is defence in depth, not the
     * primary gate.)
     *
     * The CFI is stored TWICE by design — in `Locator.cfi` and in the anchor — because only the
     * locator survives a backup round-trip (see [cfiFor]).
     *
     * Field shape mirrors iOS `FoliateSpikeView+Selection.swift`: no `href` (foliate exposes no
     * stable per-section href in a selection event), no `progression` (the event carries none), and
     * the format taken from the book's OWN identity rather than a hardcoded `azw3` — iOS derives it
     * from the book fingerprint, and hardcoding would mint a locator addressing a different identity
     * (an orphan annotation) for any non-Kindle book that ever reached here. For a
     * repository-originated [Book] (whose `fingerprintKey` is derived from the same hash/size/format
     * triple) this makes `locator.fingerprintKey == book.fingerprintKey`; [Book] is a plain DTO with
     * independent fields, so it is a consequence of well-formed input, not a type-level guarantee.
     *
     * `sectionIndex` is deliberately NOT stored: for MOBI/KF8 the CFI's first step already encodes
     * the spine index, and a second copy would only drift. The selection `rect` is view-only (valid
     * for one layout) and is likewise dropped.
     */
    fun selectionToInputs(selection: FoliateMessage.Selection, book: Book): Azw3SelectionInputs? {
        val text = selection.text.takeUnless { it.isBlank() } ?: return null
        val cfi = selection.cfi.takeUnless { it.isBlank() } ?: return null
        val locator = Locator(
            contentSHA256 = book.contentSHA256,
            fileByteCount = book.fileByteCount,
            format = book.originalFormat.name,
            href = null,
            progression = null,
            cfi = cfi,
            textQuote = text,
        )
        // serializedRange / readiumLocatorJSON stay null: foliate exposes no DOM range on this path
        // and there is no Readium locator here.
        val anchor = AnnotationAnchor.Epub(href = "", cfi = cfi)
        return Azw3SelectionInputs(selectedText = text, locator = locator, anchor = anchor)
    }

    /**
     * The CFI to hand `readerAPI.addAnnotation` / `deleteAnnotation` for a stored [record], or null
     * when the record carries none (the caller then skips it rather than painting the wrong range).
     *
     * Precedence: the Epub anchor's CFI, then `record.locator.cfi`.
     *
     * **The locator fallback is load-bearing, not defensive.** The backup wire carries no anchor:
     * `AnnotationsRepository.restoreAnnotations` inserts every restored highlight and note with
     * `anchor = null`, and the on-wire `locatorJSON` is a plain `Locator` — the CFI survives there
     * and nowhere else. An anchor-only lookup would make every AZW3 highlight restored from a backup
     * permanently invisible: stored, listed in the Notes sheet, and impossible to paint.
     *
     * A blank anchor CFI falls through for the same reason a missing one does — an empty string
     * resolves to no range, so it is not a usable annotation key. A non-Epub anchor (a `Text` anchor
     * on an AZW3 row, i.e. a mixed or corrupt import) carries no CFI and falls through too.
     */
    fun cfiFor(record: HighlightRecord): String? =
        (record.anchor as? AnnotationAnchor.Epub)?.cfi?.takeUnless { it.isBlank() }
            ?: record.locator.cfi?.takeUnless { it.isBlank() }

    /**
     * A tapped CFI (`annotation-show`) -> the matching highlight's id, or null for no match. The iOS
     * `FoliateHighlightTapResolver` analog: walk [records] in order, first exact match wins (so the
     * result is a deterministic function of the caller's sort order), blank CFI is a no-match.
     *
     * Matching goes through [cfiFor], NOT the anchor alone: an overlay is painted under whatever
     * [cfiFor] returned, so a restored (anchor-less) highlight is painted under its LOCATOR CFI and
     * reports that same CFI when tapped. Resolving against the anchor only would leave every restored
     * highlight visible but untappable — no EDIT popover, no way to remove it.
     *
     * Comparison is exact string equality: a CFI differing by whitespace or case denotes a different
     * range, and a fuzzy match would paint or delete the wrong one.
     *
     * KNOWN LIMITATION (pre-existing, cross-format, NOT introduced here). A live row and a row
     * restored from a backup for the same range share a `profileKey` but not an `anchorKey` — the
     * restore path drops the anchor, so `anchorKeyFor(null)` yields the `__nil_anchor__` sentinel and
     * the `(profileKey, anchorKey)` unique index admits both. Every format's restore path behaves
     * this way (#123 EPUB, #124/#125 TXT/MD), so reconciling it belongs to the shared persistence
     * seam, not to this mapper. Under such a duplicate both rows resolve to the same CFI — foliate's
     * `addAnnotation` removes and re-adds under that value, so one overlay is painted — and this
     * function returns the caller's first matching row, which makes the choice deterministic rather
     * than arbitrary.
     */
    fun highlightIdForCfi(cfi: String, records: List<HighlightRecord>): String? {
        if (cfi.isBlank()) return null
        return records.firstOrNull { cfiFor(it) == cfi }?.id
    }
}
