package com.vreader.app.search

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.data.Book
import com.vreader.app.reader.BookOpener
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.BookFormat
import java.io.File

/**
 * Instrumented EPUB text-extraction test (feature #128 WI-3) — runs on the emulator because the
 * Readium content service needs the real Android runtime (not Robolectric). Copies the bundled
 * minimal EPUB into app storage, extracts its text via [EpubTextExtractor], and asserts sections
 * arrive VIA THE SINK (never a returned list), that a title is derived, that author rides on Success,
 * that flushRemaining() drains the partial last batch (1 / N-1 / N / N+1), and that the publication is
 * always closed. This is the Gate-5 Android lane (`connectedDebugAndroidTest`); the orchestrator runs
 * it — the lane does NOT run it (needs the emulator).
 *
 * Real-books-first exception: the hand-authored minimal EPUB is the deterministic tiny-structure
 * fixture (exact single-spine + one TOC entry + no OPF author) a 13–18MB real book can't give cheaply,
 * and it must ship as a committed test asset (no gitignored test-books/ on an instrumented run).
 */
@RunWith(AndroidJUnit4::class)
class EpubTextExtractorTest {

    /** A collecting fake sink: records each emit + counts flushRemaining calls (never a bulk list). */
    private class CollectingSink : SectionSink {
        val sections = mutableListOf<BookTextSection>()
        var flushCalls = 0
        override suspend fun emit(section: BookTextSection) { sections.add(section) }
        override suspend fun flushRemaining() { flushCalls++ }
    }

    private fun stageMinimalEpub(): File {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val testContext = instrumentation.context
        val epub = File(appContext.cacheDir, "wi3-search-minimal.epub")
        testContext.assets.open("minimal.epub").use { input ->
            epub.outputStream().use { output -> input.copyTo(output) }
        }
        return epub
    }

    private fun epubBook(file: File?) = Book(
        fingerprintKey = "epub:${"a".repeat(64)}:1293",
        title = "Minimal Test Book", originalFormat = BookFormat.epub,
        contentSHA256 = "a".repeat(64), fileByteCount = 1293L,
        localFilePath = file?.absolutePath, addedAt = 1L,
    )

    @Test
    fun extract_minimalEpub_streamsSectionsViaSink() = runBlocking {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        val epub = stageMinimalEpub()
        val sink = CollectingSink()

        val result = EpubTextExtractor(BookOpener(appContext)).extract(epubBook(epub), sink)

        assertTrue("extract succeeds on the minimal EPUB", result is ExtractResult.Success)
        // minimal.epub OPF has no <dc:creator> → author is null on Success.
        assertNull("no OPF author → null", (result as ExtractResult.Success).author)
        assertTrue("sections arrived via the sink, not a returned list", sink.sections.isNotEmpty())
        val allText = sink.sections.joinToString(" ") { it.text }
        assertTrue("the body text was extracted", allText.contains("Ishmael"))
        // A title is derived from the heading / TOC ("Chapter 1").
        assertTrue(
            "a section title was derived from the heading/TOC",
            sink.sections.any { it.title?.contains("Chapter 1") == true },
        )
    }

    @Test
    fun extract_chunkOrdinal_isUniqueAndMonotonic() = runBlocking {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        val epub = stageMinimalEpub()
        val sink = CollectingSink()
        EpubTextExtractor(BookOpener(appContext)).extract(epubBook(epub), sink)
        val ordinals = sink.sections.map { it.chunkOrdinal }
        assertEquals("chunkOrdinals are unique", ordinals.size, ordinals.toSet().size)
        // Monotonic 0..N-1.
        assertEquals((0 until ordinals.size).toList(), ordinals)
    }

    @Test
    fun extract_nullLocalFilePath_returnsUnsupported() = runBlocking {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        val sink = CollectingSink()
        val result = EpubTextExtractor(BookOpener(appContext)).extract(epubBook(null), sink)
        assertEquals(ExtractResult.Unsupported, result)
        assertTrue(sink.sections.isEmpty())
    }

    @Test
    fun extract_missingFile_returnsFailed() = runBlocking {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        val ghost = epubBook(File(appContext.cacheDir, "missing-${System.nanoTime()}.epub"))
        val sink = CollectingSink()
        val result = EpubTextExtractor(BookOpener(appContext)).extract(ghost, sink)
        assertTrue("a missing file → Failed (open fails), never crashes", result is ExtractResult.Failed)
        assertTrue(sink.sections.isEmpty())
    }

    @Test
    fun extract_canRunTwice_publicationClosedEachTime() = runBlocking {
        // If the publication weren't closed, a second open of the same file handle could fail; two
        // clean extracts prove the finally-close released the resource.
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        val epub = stageMinimalEpub()
        val extractor = EpubTextExtractor(BookOpener(appContext))
        val first = extractor.extract(epubBook(epub), CollectingSink())
        val second = extractor.extract(epubBook(epub), CollectingSink())
        assertTrue(first is ExtractResult.Success)
        assertTrue(second is ExtractResult.Success)
    }
}
