// Purpose: feature #117 WI-1 (#110 Phase 3) — parses an OPDS 1.2 Atom feed (bytes) into an
// [OpdsFeed], mirroring iOS `OPDSParser`. Namespace-aware SAX via the hardened [SafeXml] (OPDS
// feeds are untrusted remote XML — DOCTYPE-banned, UTF-8-pinned). Handles feed-level vs entry-level
// title/id/author/summary/content/updated/link, the default Atom namespace (localName-first), and
// dedups entries by id.
package com.vreader.app.opds

import com.vreader.app.xml.SafeXml
import org.xml.sax.Attributes
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler

object OpdsParser {
    /** Parse [bytes] into an [OpdsFeed]; [baseUrl] resolves relative links. */
    fun parse(bytes: ByteArray, baseUrl: String? = null): OpdsFeed {
        if (bytes.isEmpty()) throw OpdsError.EmptyData
        val handler = OpdsHandler()
        try {
            SafeXml.parse(bytes, handler)
        } catch (e: SAXException) {
            throw OpdsError.InvalidXml(e.message ?: "malformed XML")
        }
        return OpdsFeed(
            title = handler.feedTitle.orEmpty(),
            id = handler.feedId.orEmpty(),
            links = handler.feedLinks,
            entries = OpdsFeed.dedupe(handler.entries),
            baseUrl = baseUrl,
        )
    }

    private class OpdsHandler : DefaultHandler() {
        var feedTitle: String? = null
        var feedId: String? = null
        val feedLinks = mutableListOf<OpdsLink>()
        val entries = mutableListOf<OpdsEntry>()

        private val text = StringBuilder()
        private var inEntry = false
        private var inAuthor = false
        // current entry accumulators
        private var eTitle: String? = null
        private var eId: String? = null
        private var eAuthor: String? = null
        private var eSummary: String? = null
        private var eUpdated: String? = null
        private var eLinks = mutableListOf<OpdsLink>()

        /** OPDS uses the default Atom namespace (no prefix) — prefer localName, fall back to qName. */
        private fun name(localName: String?, qName: String): String =
            (localName?.takeIf { it.isNotBlank() } ?: qName).substringAfter(':')

        override fun startElement(uri: String?, localName: String?, qName: String, attrs: Attributes?) {
            text.setLength(0)
            when (name(localName, qName)) {
                "entry" -> {
                    inEntry = true
                    eTitle = null; eId = null; eAuthor = null; eSummary = null; eUpdated = null
                    eLinks = mutableListOf()
                }
                "author" -> inAuthor = true
                "link" -> {
                    val link = OpdsLink(
                        rel = attrs?.getValue("rel"),
                        href = attrs?.getValue("href").orEmpty(),
                        type = attrs?.getValue("type"),
                        title = attrs?.getValue("title"),
                    )
                    if (link.href.isNotEmpty()) {
                        if (inEntry) eLinks.add(link) else feedLinks.add(link)
                    }
                }
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) { text.append(ch, start, length) }

        override fun endElement(uri: String?, localName: String?, qName: String) {
            val t = text.toString().trim()
            when (name(localName, qName)) {
                "title" -> if (inEntry) eTitle = eTitle ?: t else feedTitle = feedTitle ?: t
                "id" -> if (inEntry) eId = eId ?: t else feedId = feedId ?: t
                "name" -> if (inEntry && inAuthor) eAuthor = eAuthor ?: t
                "author" -> inAuthor = false
                "summary" -> if (inEntry) eSummary = eSummary ?: t
                "content" -> if (inEntry && eSummary == null) eSummary = t.ifBlank { null }
                "updated" -> if (inEntry) eUpdated = eUpdated ?: t
                "entry" -> {
                    entries.add(
                        OpdsEntry(
                            title = eTitle.orEmpty(), id = eId.orEmpty(), author = eAuthor,
                            summary = eSummary, updated = eUpdated, links = eLinks.toList(),
                        )
                    )
                    inEntry = false
                }
            }
            text.setLength(0)
        }
    }
}
