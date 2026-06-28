package com.vreader.app.annotations

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.data.Book
import com.vreader.app.data.BookEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import vreader.contracts.BookFormat

/**
 * Feature #123 WI-3 — on-device slice: a Readium selection → real `AnnotationsRepository` → real Room
 * (SQLite) → reload → `EpubAnnotationMapper.readiumLocatorFor` reconstructs the Readium locator via
 * `Locator.fromJSON` (the exact path `ReaderHighlightController.applyHighlights` uses to re-render the
 * decoration on reopen). Proves the persist + re-render substance end-to-end on the emulator.
 */
@RunWith(AndroidJUnit4::class)
class AnnotationsConnectedTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: AnnotationsRepository
    private val key = "epub:${"a".repeat(64)}:2048"
    private val book = Book(
        fingerprintKey = key, title = "Moby Dick", originalFormat = BookFormat.epub,
        contentSHA256 = "a".repeat(64), fileByteCount = 2048L, addedAt = 1L,
    )

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            InstrumentationRegistry.getInstrumentation().targetContext, VReaderDatabase::class.java,
        ).build()
        repo = AnnotationsRepository(db.annotationDao())
        runBlocking { db.bookDao().upsert(BookEntity(key, "Moby Dick", "epub", "a".repeat(64), 2048L, null, null, 1L, null)) }
    }

    @After fun tearDown() = db.close()

    private fun selection(highlight: String) = ReadiumLocator(
        href = Url("chapter1.xhtml")!!, mediaType = MediaType.XHTML,
        locations = ReadiumLocator.Locations(progression = 0.42, totalProgression = 0.1),
        text = ReadiumLocator.Text(before = "Call me ", highlight = highlight, after = "."),
    )

    @Test fun selection_persists_andReconstructsForDecoration_onDevice() = runBlocking {
        val inputs = EpubAnnotationMapper.selectionToInputs(selection("Ishmael"), book)!!
        val created = repo.addHighlight(key, AnnotationColor.green, inputs.selectedText, inputs.locator, inputs.anchor)

        // reload from real SQLite + map back to a record (the reopen path)
        val reloaded = repo.findHighlight(created.id)
        assertNotNull("highlight persisted to real Room", reloaded)
        assertEquals(AnnotationColor.green, reloaded!!.color)
        assertEquals("Ishmael", reloaded.selectedText)

        // the stored record reconstructs a valid Readium locator → a decoration would re-render
        val readium = EpubAnnotationMapper.readiumLocatorFor(reloaded)
        assertNotNull("decoration locator reconstructs via Locator.fromJSON on-device", readium)
        assertEquals("chapter1.xhtml", readium!!.href.toString())
        assertEquals("Ishmael", readium.text.highlight)

        // edit color + remove (the create/edit lifecycle through real Room)
        repo.updateHighlight(created.id, AnnotationColor.red, "a thought")
        assertEquals(AnnotationColor.red, repo.findHighlight(created.id)!!.color)
        repo.removeHighlight(created.id)
        assertEquals(0, repo.highlightCount(key))
    }

    @Test fun reHighlightSameRange_dedupes_onDevice() = runBlocking {
        val inputs = EpubAnnotationMapper.selectionToInputs(selection("Ishmael"), book)!!
        val a = repo.addHighlight(key, AnnotationColor.yellow, inputs.selectedText, inputs.locator, inputs.anchor)
        val b = repo.addHighlight(key, AnnotationColor.blue, inputs.selectedText, inputs.locator, inputs.anchor)
        assertEquals("same selection → one persisted row", 1, repo.highlightsForBook(key).size)
        assertEquals("returns the live persisted id", a.id, b.id)
        assertEquals(AnnotationColor.blue, repo.findHighlight(b.id)!!.color)
    }
}
