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
 * Feature #125 WI-3 — on-device: an MD highlight (anchored in SOURCE coords, `md` locator format)
 * persists to real Room and the wash recompute through a `MarkdownChunkTextMapper` projects it onto the
 * RENDERED range (markers stripped). Proves the MD persist → re-render path end-to-end (the live gesture
 * + visual paint are WI-4). The `md` locator format (not hardcoded "txt") is the Gate-2 Critical.
 */
@RunWith(AndroidJUnit4::class)
class MdHighlightConnectedTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: AnnotationsRepository
    // chunk 0 = "# Title\n" (src [0,8)); chunk 1 = "**bold**x\n" (src [8,18))
    private val text = "# Title\n**bold**x\n"
    private val doc = TxtDocument.of(text)
    private val mapper = MarkdownChunkTextMapper(doc)
    private val sha = "a".repeat(64)
    private val key = "md:$sha:${text.length}"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            InstrumentationRegistry.getInstrumentation().targetContext, VReaderDatabase::class.java,
        ).build()
        repo = AnnotationsRepository(db.annotationDao())
        runBlocking { db.bookDao().upsert(BookEntity(key, "T", "md", sha, text.length.toLong(), null, null, 1L, null)) }
    }

    @After fun tearDown() = db.close()

    @Test fun mdHighlightPersists_andWashRecomputesToRenderedRange_onDevice() = runBlocking {
        // "bold" in chunk 1: source [10,14). Persist a highlight anchored in SOURCE coords with the md locator.
        val locator = Locator(sha, text.length.toLong(), "md", charRangeStartUTF16 = 10, charRangeEndUTF16 = 14, textQuote = "bold**x".substring(0, 4))
        repo.addHighlight(key, AnnotationColor.green, "bold", locator, AnnotationAnchor.Text("text-document:$key", 10, 14))

        val highlights = repo.highlights(key).first()
        assertEquals(1, highlights.size)
        assertEquals("the md locator format must round-trip (not 'txt')", "md", highlights.single().locator.format)

        // The wash recompute projects the SOURCE highlight onto chunk 1's RENDERED range [0,4) ("bold").
        val map = TxtWashMapper.washesByChunk(doc, highlights, mapper)
        assertTrue("wash projected onto chunk 1", map.containsKey(1))
        assertEquals(WashSpan(Utf16Range(0, 4), AnnotationColor.green), map[1]!!.single())
    }
}
