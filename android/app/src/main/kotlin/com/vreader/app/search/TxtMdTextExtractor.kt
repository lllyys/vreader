// Purpose: Extract TXT/MD text for the library search index, streaming each TxtDocument chunk to the
// SectionSink — feature #128 WI-3. Serves both `txt` and `md` (raw markdown text; marker-stripping is
// a nice-to-have deferred). Reuses the shipped reader decode/chunk path (TxtDecoder + TxtDocument).
//
// Memory note (Gate-2 round-3 HIGH): this path holds the whole decoded book String (via
// TxtDecoder/TxtDocument) — O(book-size), the ACCEPTED EXISTING reader bound (indexing loads exactly
// what the TXT/MD reader already loads to display the book). It is NOT O(batch). The sink still emits
// chunks incrementally so the DB-write side stays batched.
package com.vreader.app.search

import com.vreader.app.data.Book
import com.vreader.app.reader.TxtDecoder
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CancellationException
import java.io.File

/** Streams a TXT/MD book's TxtDocument chunks to a [SectionSink]; author is always null on Success. */
class TxtMdTextExtractor : BookTextExtractor {

    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
        val path = book.localFilePath ?: return ExtractResult.Unsupported
        val file = File(path)
        if (!file.exists()) return ExtractResult.Failed("file not found: $path")
        return try {
            val decoded = TxtDecoder.decode(file)
            val document = TxtDocument.of(decoded.text)
            // Emit one section per chunk; sectionIndex == chunkOrdinal == chunk index (TXT has no
            // sub-resource grouping). Empty text → chunkCount 0 → zero emissions (still Success).
            for (i in 0 until document.chunkCount) {
                sink.emit(
                    BookTextSection(
                        sectionIndex = i,
                        chunkOrdinal = i,
                        title = null,
                        text = document.textForChunk(i).toString(),
                    ),
                )
            }
            ExtractResult.Success(null)
        } catch (e: CancellationException) {
            throw e   // never swallow structured cancellation as a per-book failure
        } catch (e: Exception) {
            ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
        }
    }
}
