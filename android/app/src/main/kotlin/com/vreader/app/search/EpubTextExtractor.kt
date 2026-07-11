// Purpose: Extract EPUB text for the library search index via Readium's Publication content service,
// streaming each finished section chunk to the SectionSink — feature #128 WI-3. Genuinely
// bounded-memory (O(batch)): `content.iterator()` yields elements incrementally and only the current
// section's in-progress buffer (+ one ~4 KB chunk) is resident — never `content.elements()` (which
// materializes the whole publication) and never a growing List of all sections.
//
// Key decisions:
// - `publication.content(locator = null)` is NULLABLE (no content service → protected/malformed EPUB)
//   → typed ExtractResult.Unsupported.
// - Section boundary = a change of reading-order resource (Locator.href) OR a Heading-role element
//   (which starts a new titled section). Title = the element Locator's `title`, or the normalized-href
//   TOC lookup (strip fragment + normalize percent-encoding before matching).
// - A long section is chunked at ~4 KB with a UNIQUE monotonic `chunkOrdinal` across the WHOLE book so
//   multiple chunks of one resource never collide on sectionIndex (deterministic first hit — WI-5 SQL).
// - `finally { publication.close() }` on EVERY path (success, unsupported after open, exception) — the
//   sink spans the open publication, so the close must be guaranteed.
package com.vreader.app.search

import com.vreader.app.data.Book
import com.vreader.app.reader.BookOpener
import kotlinx.coroutines.CancellationException
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.content
import java.io.File

/** Extracts EPUB text via Readium's content service, streaming section chunks to a [SectionSink]. */
@OptIn(ExperimentalReadiumApi::class)
class EpubTextExtractor(
    private val bookOpener: BookOpener,
    /** Approx max chunk size in UTF-16 chars before a section is split (deterministic ordinal). */
    private val maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS,
) : BookTextExtractor {

    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
        val path = book.localFilePath ?: return ExtractResult.Unsupported
        val file = File(path)
        if (!file.exists()) return ExtractResult.Failed("file not found: $path")

        val publication = try {
            bookOpener.open(file)
        } catch (e: CancellationException) {
            throw e   // never swallow structured cancellation as a per-book failure
        } catch (e: Exception) {
            return ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
        }
        try {
            val author = publication.metadata.authors.firstOrNull()?.name
            val content = publication.content(null)
                ?: return ExtractResult.Unsupported   // no content service → metadata-only book
            val tocTitles = tocTitlesByHref(publication)
            streamSections(content, tocTitles, sink)
            return ExtractResult.Success(author)
        } catch (e: CancellationException) {
            throw e   // rethrow cancellation; the finally still closes the publication
        } catch (e: Exception) {
            return ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
        } finally {
            publication.close()
        }
    }

    /**
     * Streams the publication's text via the content iterator, emitting each finished chunk. Groups
     * text by reading-order resource (href) into `sectionIndex`; a Heading role starts a new titled
     * section; a running `chunkOrdinal` is unique across the whole book.
     */
    private suspend fun streamSections(
        content: Content,
        tocTitles: Map<String, String>,
        sink: SectionSink,
    ) {
        val iterator = content.iterator()
        // Mutable extraction state carried across boundaries; the running chunkOrdinal is unique
        // across the whole book, sectionIndex groups a resource's chunks for chapter attribution.
        val state = StreamState()

        while (iterator.hasNext()) {
            val element = iterator.next()
            if (element !is Content.TextElement) continue
            val href = normalizeHref(element.locator.href.toString())
            val isHeading = element.role is Content.TextElement.Role.Heading
            // A resource change OR a heading starts a new section: drain the prior buffer first.
            if (href != state.currentHref || isHeading) {
                drainRemaining(state, sink)
                state.sectionIndex++
                state.currentHref = href
                state.currentTitle = element.locator.title
                    ?: tocTitles[href]
                    ?: if (isHeading) element.text.trim().ifEmpty { null } else null
            }
            val text = element.text
            if (text.isNotEmpty()) {
                if (state.buffer.isNotEmpty()) state.buffer.append('\n')
                state.buffer.append(text)
                // Emit completed chunks from the FRONT as soon as the buffer crosses the threshold,
                // retaining only a short (< maxChunkChars) tail — so at most ~one chunk + tail is
                // resident regardless of the resource size (bounded-memory / O(batch), not O(book)).
                emitFullChunks(state, sink)
            }
        }
        drainRemaining(state, sink)
    }

    /** Emits every completed leading chunk (buffer ≥ maxChunkChars), keeping only the sub-chunk tail. */
    private suspend fun emitFullChunks(state: StreamState, sink: SectionSink) {
        while (state.buffer.length >= maxChunkChars) {
            val end = splitBoundary(state.buffer, maxChunkChars)
            if (end <= 0 || end >= state.buffer.length) break
            emitChunk(state, sink, state.buffer.substring(0, end))
            state.buffer.delete(0, end)
        }
    }

    /** Drains any remaining buffered text for the current section (the partial tail). */
    private suspend fun drainRemaining(state: StreamState, sink: SectionSink) {
        while (state.buffer.length >= maxChunkChars) {
            val end = splitBoundary(state.buffer, maxChunkChars)
            val cut = if (end in 1 until state.buffer.length) end else state.buffer.length
            emitChunk(state, sink, state.buffer.substring(0, cut))
            state.buffer.delete(0, cut)
        }
        if (state.buffer.isNotEmpty()) {
            emitChunk(state, sink, state.buffer.toString())
            state.buffer.setLength(0)
        }
    }

    private suspend fun emitChunk(state: StreamState, sink: SectionSink, chunk: String) {
        if (chunk.isBlank()) return
        sink.emit(
            BookTextSection(
                sectionIndex = state.sectionIndex,
                chunkOrdinal = state.chunkOrdinal++,
                title = state.currentTitle,
                text = chunk,
            ),
        )
    }

    /** The split length for the FIRST chunk of [buffer] (≥ [target]), preferring a newline, never
     *  mid-surrogate-pair. Returns the exclusive end index within `buffer`. */
    private fun splitBoundary(buffer: CharSequence, target: Int): Int {
        val n = buffer.length
        if (n <= target) return n
        var end = target.coerceAtMost(n)
        // Prefer a newline boundary within the last quarter of the chunk for readable snippets.
        val minNl = target * 3 / 4
        val nl = lastNewline(buffer, minNl, end)
        if (nl in 1 until end) end = nl + 1
        // Never split between a high and low surrogate.
        if (end < n && Character.isHighSurrogate(buffer[end - 1])) end++
        return end.coerceAtMost(n)
    }

    private fun lastNewline(buffer: CharSequence, from: Int, to: Int): Int {
        var i = to - 1
        while (i >= from) {
            if (buffer[i] == '\n') return i
            i--
        }
        return -1
    }

    /** Mutable per-book extraction state carried across section boundaries. */
    private class StreamState {
        var chunkOrdinal = 0
        var sectionIndex = -1
        var currentHref: String? = null
        var currentTitle: String? = null
        val buffer = StringBuilder()
    }

    /** Builds an href → TOC title map, normalizing each TOC entry's href the same way. */
    private fun tocTitlesByHref(publication: Publication): Map<String, String> {
        val map = mutableMapOf<String, String>()
        fun walk(links: List<Link>) {
            for (link in links) {
                val title = link.title
                if (!title.isNullOrBlank()) {
                    val href = normalizeHref(link.href.toString())
                    map.putIfAbsent(href, title)
                }
                if (link.children.isNotEmpty()) walk(link.children)
            }
        }
        walk(publication.tableOfContents)
        return map
    }

    /** Strip the fragment and normalize percent-encoding so `chapter1.xhtml#a` matches `chapter1.xhtml`. */
    private fun normalizeHref(href: String): String {
        val noFragment = href.substringBefore('#')
        return try {
            java.net.URLDecoder.decode(noFragment, Charsets.UTF_8.name())
        } catch (e: Exception) {
            noFragment
        }
    }

    companion object {
        const val DEFAULT_MAX_CHUNK_CHARS = 4000
    }
}
