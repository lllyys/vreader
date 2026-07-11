// Purpose: Flatten a Readium EPUB publication's table of contents into [TocEntry]
// rows for the reader Contents sheet (feature #132 WI-1). Recursively walks
// `Link.children` tracking depth; for each link resolves a native Readium `Locator`
// (SKIPPING links that resolve to null) which it (a) retains verbatim for a
// zero-reconstruction `navigator.go` jump and (b) converts to the engine-neutral
// canonical vreader `Locator` via the adapter-(i) hop:
//   readiumLocator.toJSON() → ReadiumLocatorBridge.toEnvelope(json, <book identity>)
//     → envelope.legacyLocator.
// This keeps ReadiumLocatorBridge Readium-FREE (its whole point) — the object→JSON
// step lives here, where Readium types already live, NOT in the pure-JVM bridge.
package com.vreader.app.reader.nav

import com.vreader.app.data.Book
import com.vreader.app.reader.ReadiumLocatorBridge
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.publication.Publication

/**
 * The two Readium [Publication] operations [ReadiumTocProvider] consumes. Extracted
 * as a seam because [Publication] is a `final` class (unmockable) and `locatorFromLink`
 * is not independently controllable in a unit test — the fake seam lets the flatten /
 * skip / depth / adapter logic be exercised directly. Production wires the real
 * publication via [ReadiumTocProvider]'s `(publication, book)` constructor.
 */
interface PublicationTocSource {
    /** The publication's top-level table-of-contents links. */
    val tableOfContents: List<Link>

    /** Resolves a TOC link to a Readium locator, or null when it cannot be located. */
    fun locatorFromLink(link: Link): ReadiumLocator?
}

/** Adapts a real Readium [Publication] to the [PublicationTocSource] seam. */
private class RealPublicationTocSource(private val publication: Publication) : PublicationTocSource {
    override val tableOfContents: List<Link> get() = publication.tableOfContents
    override fun locatorFromLink(link: Link): ReadiumLocator? = publication.locatorFromLink(link)
}

/**
 * A [TocProvider] backed by a Readium publication. The [book] identity triple
 * (`contentSHA256`/`fileByteCount`/`originalFormat`) is threaded into every canonical
 * locator so the row survives an engine swap / cross-device restore.
 */
class ReadiumTocProvider internal constructor(
    private val source: PublicationTocSource,
    private val book: Book,
    private val bridge: ReadiumLocatorBridge = ReadiumLocatorBridge(),
) : TocProvider {

    /** Production constructor: wraps the real [Publication]. */
    constructor(publication: Publication, book: Book) : this(RealPublicationTocSource(publication), book)

    override suspend fun toc(): List<TocEntry> {
        val entries = mutableListOf<TocEntry>()
        flatten(source.tableOfContents, depth = 0, into = entries)
        return entries
    }

    private fun flatten(links: List<Link>, depth: Int, into: MutableList<TocEntry>) {
        for (link in links) {
            val native = source.locatorFromLink(link)
            if (native != null) {
                into.add(toEntry(link, native, depth))
            }
            // Recurse regardless — a null-locator container may still parent locatable
            // children (the container is skipped, its children are not).
            if (link.children.isNotEmpty()) {
                flatten(link.children, depth + 1, into)
            }
        }
    }

    private fun toEntry(link: Link, native: ReadiumLocator, depth: Int): TocEntry {
        // Adapter (i): Readium object → its own JSON → the pure-JVM bridge → canonical.
        val envelope = bridge.toEnvelope(
            readiumLocatorJSON = native.toJSON().toString(),
            bookContentSHA256 = book.contentSHA256,
            bookFileByteCount = book.fileByteCount,
            bookFormat = book.originalFormat,
        )
        return TocEntry(
            title = link.title,
            depth = depth,
            pageLabel = native.locations.position?.toString(),
            canonicalLocator = envelope.legacyLocator
                ?: error("bridge always derives a canonical fallback locator"),
            epubReadiumLocator = native,
        )
    }
}
