package com.vreader.app.search

import com.vreader.app.data.Book
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat
import java.io.File
import java.nio.charset.Charset

/**
 * Feature #128 WI-3 — [TxtMdTextExtractor]: TxtDecoder chunk-stream. Verifies streaming emit (via a
 * collecting fake sink), UTF-16LE BOM + GBK + CJK decode, flush semantics at 1/N-1/N/N+1 sections,
 * null localFilePath → Unsupported, decode failure → Failed.
 */
class TxtMdTextExtractorTest {

    /** A collecting fake sink: records every emit + counts flushRemaining calls. */
    private class CollectingSink : SectionSink {
        val sections = mutableListOf<BookTextSection>()
        var flushCalls = 0
        override suspend fun emit(section: BookTextSection) { sections.add(section) }
        override suspend fun flushRemaining() { flushCalls++ }
    }

    private fun bookFor(file: File?, format: BookFormat = BookFormat.txt) = Book(
        fingerprintKey = "${format.name}:${"a".repeat(64)}:100",
        title = "T", originalFormat = format, contentSHA256 = "a".repeat(64),
        fileByteCount = 100L, localFilePath = file?.absolutePath, addedAt = 1L,
    )

    private fun writeTemp(name: String, bytes: ByteArray): File {
        // createTempFile requires a prefix >= 3 chars.
        val f = File.createTempFile("wi3-$name", ".txt")
        f.writeBytes(bytes)
        f.deleteOnExit()
        return f
    }

    @Test fun nullLocalFilePath_returnsUnsupported() = runTest {
        val sink = CollectingSink()
        val result = TxtMdTextExtractor().extract(bookFor(null), sink)
        assertEquals(ExtractResult.Unsupported, result)
        assertTrue("no sections emitted on Unsupported", sink.sections.isEmpty())
    }

    @Test fun missingFile_returnsFailed() = runTest {
        val sink = CollectingSink()
        val ghost = bookFor(File("/nonexistent/does-not-exist.txt"))
        val result = TxtMdTextExtractor().extract(ghost, sink)
        assertTrue("missing file → Failed", result is ExtractResult.Failed)
    }

    @Test fun utf16LeBom_decodedAndStreamed() = runTest {
        val bom = byteArrayOf(0xFF.toByte(), 0xFE.toByte())
        val body = "Hello world\nsecond line".toByteArray(Charset.forName("UTF-16LE"))
        val file = writeTemp("utf16le", bom + body)
        val sink = CollectingSink()
        val result = TxtMdTextExtractor().extract(bookFor(file), sink)
        assertEquals(ExtractResult.Success(null), result)
        assertTrue(sink.sections.isNotEmpty())
        val all = sink.sections.joinToString("") { it.text }
        assertTrue("decoded text present", all.contains("Hello world"))
        assertTrue("second line present", all.contains("second line"))
    }

    @Test fun gbkChinese_decodedAndStreamed() = runTest {
        val gbk = Charset.forName("GBK")
        val file = writeTemp("gbk", "关于编程的书".toByteArray(gbk))
        val sink = CollectingSink()
        val result = TxtMdTextExtractor().extract(bookFor(file), sink)
        assertTrue(result is ExtractResult.Success)
        assertTrue("CJK content decoded", sink.sections.joinToString("") { it.text }.contains("关于编程"))
    }

    @Test fun streamingEmit_chunkOrdinalMonotonicPerChunk() = runTest {
        // A runaway single line longer than the max-chunk char count hard-splits into multiple chunks.
        val long = "x".repeat(9000) + "\n"  // > 2 * DEFAULT_MAX_CHUNK_CHARS (4000)
        val file = writeTemp("long", long.toByteArray(Charsets.UTF_8))
        val sink = CollectingSink()
        TxtMdTextExtractor().extract(bookFor(file), sink)
        assertTrue("multiple chunks for a runaway line", sink.sections.size >= 2)
        // chunkOrdinal is a monotonic 0..N-1 running counter; sectionIndex == chunkOrdinal for TXT.
        sink.sections.forEachIndexed { i, s ->
            assertEquals(i, s.chunkOrdinal)
            assertEquals(i, s.sectionIndex)
            assertEquals(null, s.title)
        }
    }

    @Test fun emptyFile_zeroEmissions_stillSuccess() = runTest {
        val file = writeTemp("empty", ByteArray(0))
        val sink = CollectingSink()
        val result = TxtMdTextExtractor().extract(bookFor(file), sink)
        assertEquals(ExtractResult.Success(null), result)
        assertTrue("empty file → zero sections", sink.sections.isEmpty())
    }

    @Test fun mdFormat_alsoExtracted() = runTest {
        val file = writeTemp("md", "# Heading\n\nBody text here.".toByteArray(Charsets.UTF_8))
        val sink = CollectingSink()
        val result = TxtMdTextExtractor().extract(bookFor(file, BookFormat.md), sink)
        assertTrue(result is ExtractResult.Success)
        assertTrue(sink.sections.joinToString("") { it.text }.contains("Heading"))
    }

    @Test fun sectionsMatchTxtDocumentChunkCount() = runTest {
        // Streaming emits exactly one BookTextSection per TxtDocument chunk (1 / N-1 / N / N+1 parity).
        val text = "line one\nline two\nline three\nline four"
        val file = writeTemp("multi", text.toByteArray(Charsets.UTF_8))
        val sink = CollectingSink()
        TxtMdTextExtractor().extract(bookFor(file), sink)
        // Four newline-terminated-ish lines → four chunks (the last has no trailing newline).
        assertEquals(4, sink.sections.size)
        assertEquals(text, sink.sections.joinToString("") { it.text })
    }
}
