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
        } catch (e: Throwable) {
            return ExtractResult.Failed(e.message ?: e.javaClass.simpleName)
        }
        try {
            val author = publication.metadata.authors.firstOrNull()?.name
            val content = publication.content(null)
                ?: return ExtractResult.Unsupported   // no content service → metadata-only book
            val tocTitles = tocTitlesByHref(publication)
            streamSections(content, tocTitles, sink)
            return ExtractResult.Success(author)
        } catch (e: Throwable) {
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
        var chunkOrdinal = 0
        var sectionIndex = -1
        var currentHref: String? = null
        var currentTitle: String? = null
        val buffer = StringBuilder()

        // Emits the buffer (split into ~maxChunkChars chunks) then resets it.
        suspend fun flushSection() {
            if (buffer.isEmpty()) return
            var start = 0
            val n = buffer.length
            while (start < n) {
                val end = splitBoundary(buffer, start, n)
                val chunk = buffer.substring(start, end)
                if (chunk.isNotBlank()) {
                    sink.emit(
                        BookTextSection(
                            sectionIndex = sectionIndex,
                            chunkOrdinal = chunkOrdinal++,
                            title = currentTitle,
                            text = chunk,
                        ),
                    )
                }
                start = end
            }
            buffer.setLength(0)
        }

        while (iterator.hasNext()) {
            val element = iterator.next()
            if (element !is Content.TextElement) continue
            val href = normalizeHref(element.locator.href.toString())
            val isHeading = element.role is Content.TextElement.Role.Heading
            // A resource change OR a heading starts a new section: flush the prior buffer first.
            if (href != currentHref || isHeading) {
                flushSection()
                sectionIndex++
                currentHref = href
                currentTitle = element.locator.title
                    ?: tocTitles[href]
                    ?: if (isHeading) element.text.trim().ifEmpty { null } else null
            }
            val text = element.text
            if (text.isNotEmpty()) {
                if (buffer.isNotEmpty()) buffer.append('\n')
                buffer.append(text)
            }
        }
        flushSection()
    }

    /** Split index at ~maxChunkChars from [start], never mid-surrogate-pair, preferring a newline. */
    private fun splitBoundary(buffer: CharSequence, start: Int, n: Int): Int {
        if (n - start <= maxChunkChars) return n
        var end = (start + maxChunkChars).coerceAtMost(n)
        // Prefer a newline boundary within the last quarter of the chunk for readable snippets.
        val minNl = start + maxChunkChars * 3 / 4
        val nl = lastNewline(buffer, minNl, end)
        if (nl in (start + 1) until end) end = nl + 1
        // Never split between a high and low surrogate.
        if (end < n && end > start && Character.isHighSurrogate(buffer[end - 1])) end++
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
