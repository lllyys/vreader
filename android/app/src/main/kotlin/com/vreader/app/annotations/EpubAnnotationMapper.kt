// Purpose: feature #123 WI-3 — maps between Readium's selection/locator world and the annotation
// domain. Selection -> (vreader Locator + AnnotationAnchor.Epub + selectedText) for persistence; a
// stored highlight -> a Readium Locator for `DecorableNavigator.applyDecorations` re-render on reopen.
// Kept free of Compose/Activity so the mapping is unit-testable; the navigator wiring lives in
// ReaderHighlightController.
package com.vreader.app.annotations

import com.vreader.app.data.Book
import org.json.JSONObject
import vreader.contracts.Locator
import org.readium.r2.shared.publication.Locator as ReadiumLocator

/** The persistable inputs derived from a Readium text selection. */
data class EpubSelectionInputs(
    val selectedText: String,
    val locator: Locator,
    val anchor: AnnotationAnchor.Epub,
)

object EpubAnnotationMapper {
    /**
     * Derive the persistable inputs from a Readium selection [locator]. Returns null when there is no
     * usable highlighted text (a selection must carry `text.highlight`). The canonical vreader
     * [Locator] carries href/progression/text so the record is self-describing + cross-platform; the
     * [AnnotationAnchor.Epub] additionally keeps the verbatim Readium JSON for lossless re-application.
     */
    fun selectionToInputs(locator: ReadiumLocator, book: Book): EpubSelectionInputs? {
        val highlighted = locator.text.highlight?.takeUnless { it.isBlank() } ?: return null
        val href = locator.href.toString()
        val cfi = locator.locations.fragments.firstOrNull { it.startsWith("epubcfi(") } ?: ""
        val vloc = Locator(
            contentSHA256 = book.contentSHA256,
            fileByteCount = book.fileByteCount,
            format = book.originalFormat.name,
            href = href,
            progression = locator.locations.progression,
            totalProgression = locator.locations.totalProgression,
            cfi = cfi.ifBlank { null },
            textQuote = highlighted,
            textContextBefore = locator.text.before,
            textContextAfter = locator.text.after,
        )
        val anchor = AnnotationAnchor.Epub(
            href = href,
            cfi = cfi,
            serializedRange = null,
            readiumLocatorJSON = locator.toJSON().toString(),
        )
        return EpubSelectionInputs(selectedText = highlighted, locator = vloc, anchor = anchor)
    }

    /**
     * Reconstruct the Readium [ReadiumLocator] to re-apply a stored highlight as a decoration. Prefers
     * the verbatim Readium JSON on the anchor (lossless, via `Locator.fromJSON` — the proven
     * position-restore path); returns null if it can't be parsed (caller skips that decoration).
     */
    fun readiumLocatorFor(record: HighlightRecord): ReadiumLocator? {
        val json = (record.anchor as? AnnotationAnchor.Epub)?.readiumLocatorJSON ?: return null
        return runCatching { ReadiumLocator.fromJSON(JSONObject(json)) }.getOrNull()
    }
}
