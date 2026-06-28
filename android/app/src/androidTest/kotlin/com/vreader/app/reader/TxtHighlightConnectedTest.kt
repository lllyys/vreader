package com.vreader.app.reader

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.annotations.AnnotationAnchor
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.data.BookEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator

/**
 * Feature #124 WI-2 — on-device: a TXT highlight persists to real Room and the wash recompute
 * (`TxtWashMapper.washesByChunk`) projects it onto the right chunk. Proves the persist → re-render
 * substance end-to-end on the emulator (the visual `drawBehind` wash + the live gesture are WI-3/WI-4).
 */
@RunWith(AndroidJUnit4::class)
class TxtHighlightConnectedTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: AnnotationsRepository
    private val text = "AAAA\nBBBB\nCCCC\nDDDD\n"
    private val doc = TxtDocument.of(text, maxChunkChars = 6)
    private val key = "txt:${"a".repeat(64)}:${text.length}"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            InstrumentationRegistry.getInstrumentation().targetContext, VReaderDatabase::class.java,
        ).build()
        repo = AnnotationsRepository(db.annotationDao())
        runBlocking { db.bookDao().upsert(BookEntity(key, "T", "txt", "a".repeat(64), text.length.toLong(), null, null, 1L, null)) }
    }

    @After fun tearDown() = db.close()

    @Test fun highlightPersists_andWashRecomputesToChunk_onDevice() = runBlocking {
        val base1 = doc.offsetForChunk(1)
        val locator = Locator("a".repeat(64), text.length.toLong(), "txt", charRangeStartUTF16 = base1 + 1, charRangeEndUTF16 = base1 + 3, textQuote = "BB")
        repo.addHighlight(key, AnnotationColor.green, "BB", locator, AnnotationAnchor.Text("text-document:$key", base1 + 1, base1 + 3))

        val highlights = repo.highlights(key).first()
        assertEquals(1, highlights.size)
        val map = TxtWashMapper.washesByChunk(doc, highlights)
        assertTrue("wash projected onto chunk 1", map.containsKey(1))
        assertEquals(WashSpan(Utf16Range(1, 3), AnnotationColor.green), map[1]!!.single())
    }
}
