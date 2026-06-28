// Purpose: feature #123 WI-3 — wraps Readium's selection + decoration APIs (EpubNavigatorFragment
// implements SelectableNavigator + DecorableNavigator) so ReaderActivity stays thin. Builds
// Decorations from stored highlights and applies them; reads the current selection; relays
// decoration-activation taps (an existing highlight) back to the host (used in WI-4's edit/remove).
package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.EpubAnnotationMapper
import com.vreader.app.annotations.HighlightRecord
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator as ReadiumLocator

@OptIn(ExperimentalReadiumApi::class)
class ReaderHighlightController(private val navigator: EpubNavigatorFragment) {

    /** Render the given highlights as Readium decorations (skipping any whose anchor can't be
     *  reconstructed). Idempotent — re-applying the full set replaces the group. Returns the number of
     *  decorations actually BUILT + applied (≤ highlights.size; reconstruction failures are skipped). */
    suspend fun applyHighlights(highlights: List<HighlightRecord>): Int {
        val decorations = highlights.mapNotNull { rec ->
            val loc: ReadiumLocator = EpubAnnotationMapper.readiumLocatorFor(rec) ?: return@mapNotNull null
            Decoration(
                id = rec.id,
                locator = loc,
                style = Decoration.Style.Highlight(tint = tintOf(rec.color), isActive = true),
            )
        }
        navigator.applyDecorations(decorations, GROUP)
        return decorations.size
    }

    /** The Readium locator of the current text selection, or null if nothing is selected. */
    suspend fun currentSelectionLocator(): ReadiumLocator? = navigator.currentSelection()?.locator

    fun clearSelection() = navigator.clearSelection()

    /** Relay taps on an existing highlight decoration → its id (WI-4 opens the edit/remove popover). */
    fun observeActivations(onActivated: (highlightId: String) -> Unit) {
        navigator.addDecorationListener(
            GROUP,
            object : DecorableNavigator.Listener {
                override fun onDecorationActivated(event: DecorableNavigator.OnActivatedEvent): Boolean {
                    onActivated(event.decoration.id)
                    return true
                }
            },
        )
    }

    companion object {
        const val GROUP = "highlights"

        /** Readium applies its own wash alpha; pass the solid color. */
        fun tintOf(color: AnnotationColor): Int = android.graphics.Color.parseColor(color.dotHex)
    }
}
