package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Feature #132 WI-7-EPUB — [tocIndexFor], the pure mapping from the live Readium reading position
 * (href + progression) to the nearest/containing flattened-TOC entry index. This is the JVM-testable
 * core of the EPUB host's `currentTocIndex` update: as the reader scrolls, the current-chapter row in
 * the Contents sheet is highlighted. The rule (mirroring how a spine-ordered TOC works): the current
 * entry is the LAST entry whose position is at-or-before the reading position, comparing first by
 * spine order (href) then by intra-chapter progression. Before the first entry → 0 (highlight the
 * first row, never -1 when a TOC exists); an empty TOC → -1 (no row to highlight).
 *
 * [tocIndexFor] takes plain [TocPosition] descriptors (href + progression) rather than Readium
 * `Locator` objects, so the mapping is pure/JVM-testable with no Readium/Robolectric dependency — the
 * host extracts each entry's descriptor from its retained native `epubReadiumLocator`.
 */
class ReaderChromeModelTest {

    /** Positions in spine order (the flattened-TOC order): three chapters, each a distinct href. */
    private val chapters = listOf(
        TocPosition(href = "ch1.xhtml", progression = 0.0),
        TocPosition(href = "ch2.xhtml", progression = 0.0),
        TocPosition(href = "ch3.xhtml", progression = 0.0),
    )

    @Test fun locatorInsideMiddleChapter_mapsToThatIndex() {
        // Reading ch2 (any progression) → index 1.
        assertEquals(1, tocIndexFor("ch2.xhtml", 0.5, chapters))
    }

    @Test fun locatorInFirstChapter_mapsToZero() {
        assertEquals(0, tocIndexFor("ch1.xhtml", 0.0, chapters))
    }

    @Test fun locatorInLastChapter_mapsToLastIndex() {
        assertEquals(2, tocIndexFor("ch3.xhtml", 0.9, chapters))
    }

    @Test fun locatorBeforeFirstEntry_mapsToZero() {
        // A reading href that sorts before every TOC entry → highlight the first row (0, never -1).
        assertEquals(0, tocIndexFor("ch0.xhtml", 0.0, chapters))
    }

    @Test fun emptyEntries_mapsToMinusOne() {
        assertEquals(-1, tocIndexFor("ch1.xhtml", 0.0, emptyList()))
    }

    @Test fun nullHref_mapsToMinusOneWhenEntriesEmpty() {
        assertEquals(-1, tocIndexFor(null, null, emptyList()))
    }

    @Test fun nullHref_withEntries_mapsToZero() {
        // No positional signal but a TOC exists → default to the first row (0), never -1.
        assertEquals(0, tocIndexFor(null, null, chapters))
    }

    @Test fun sameHrefFinerProgression_picksTheDeeperTocEntry() {
        // Two TOC entries within the SAME chapter (a section split by progression): 0.0 and 0.5.
        val sections = listOf(
            TocPosition(href = "ch1.xhtml", progression = 0.0),
            TocPosition(href = "ch1.xhtml", progression = 0.5),
        )
        // Reading at progression 0.6 within ch1 → the second (deeper) section, index 1.
        assertEquals(1, tocIndexFor("ch1.xhtml", 0.6, sections))
        // Reading at 0.2 → still the first section, index 0.
        assertEquals(0, tocIndexFor("ch1.xhtml", 0.2, sections))
        // Exactly at the boundary (0.5) → the second section (at-or-before is inclusive).
        assertEquals(1, tocIndexFor("ch1.xhtml", 0.5, sections))
    }

    @Test fun nullProgression_onCurrentChapter_staysWithinThatChapter() {
        // A null progression is treated as 0.0 for the intra-chapter comparison.
        val sections = listOf(
            TocPosition(href = "ch1.xhtml", progression = 0.0),
            TocPosition(href = "ch1.xhtml", progression = 0.5),
        )
        assertEquals(0, tocIndexFor("ch1.xhtml", null, sections))
    }

    @Test fun laterChapterWins_evenWhenEarlierChapterHasHigherProgression() {
        // href ordering dominates progression: reading ch2@0.0 is AFTER ch1@0.9.
        val entries = listOf(
            TocPosition(href = "ch1.xhtml", progression = 0.9),
            TocPosition(href = "ch2.xhtml", progression = 0.0),
        )
        assertEquals(1, tocIndexFor("ch2.xhtml", 0.0, entries))
    }

    @Test fun defaultModel_isEmpty() {
        val model = ReaderChromeModel()
        assertEquals("", model.title)
        assertEquals(emptyList<Any>(), model.tocEntries)
        assertEquals(-1, model.currentTocIndex)
        assertEquals(emptyList<Any>(), model.annotations.highlights)
        assertEquals(emptyList<Any>(), model.annotations.notes)
    }
}
