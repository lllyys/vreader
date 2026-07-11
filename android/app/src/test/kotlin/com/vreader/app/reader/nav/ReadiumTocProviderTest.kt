package com.vreader.app.reader.nav

import com.vreader.app.data.Book
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat

/**
 * Feature #132 WI-1 — [ReadiumTocProvider]: flattens a Readium publication's
 * table-of-contents into [TocEntry] rows, retaining each entry's native Readium
 * [ReadiumLocator] for zero-reconstruction TOC jumps and deriving the canonical
 * vreader `Locator` via the adapter-(i) `toJSON()` → `ReadiumLocatorBridge.toEnvelope`
 * hop (identity triple threaded from the [Book]).
 *
 * Robolectric: Readium's `Locator.toJSON()` and `Url`/`MediaType` construction touch
 * the Android `org.json`/`android.net.Uri` runtime.
 */
@RunWith(RobolectricTestRunner::class)
class ReadiumTocProviderTest {

    private val book = Book(
        fingerprintKey = "epub:${"a".repeat(64)}:2048",
        title = "Moby Dick",
        originalFormat = BookFormat.epub,
        contentSHA256 = "a".repeat(64),
        fileByteCount = 2048L,
        addedAt = 1L,
    )

    private fun link(
        href: String,
        title: String?,
        children: List<Link> = emptyList(),
    ) = Link(
        href = org.readium.r2.shared.publication.Href(Url(href)!!),
        mediaType = MediaType.XHTML,
        title = title,
        children = children,
    )

    private fun readiumLocator(href: String, position: Int? = null) = ReadiumLocator(
        href = Url(href.substringBefore('#'))!!,
        mediaType = MediaType.XHTML,
        locations = ReadiumLocator.Locations(
            progression = 0.0,
            position = position,
            fragments = if (href.contains('#')) listOf(href.substringAfter('#')) else emptyList(),
        ),
    )

    /** A test seam: each link resolves to the mapped Readium locator, or null when absent. */
    private fun source(
        toc: List<Link>,
        resolve: (Link) -> ReadiumLocator?,
    ) = object : PublicationTocSource {
        override val tableOfContents: List<Link> = toc
        override fun locatorFromLink(link: Link): ReadiumLocator? = resolve(link)
    }

    @Test
    fun canonicalLocator_carriesBookIdentityTriple() = runTest {
        val l = link("ch1.xhtml", "Chapter 1")
        val provider = ReadiumTocProvider(source(listOf(l)) { readiumLocator("ch1.xhtml") }, book)

        val entries = provider.toc()

        assertEquals(1, entries.size)
        val loc = entries[0].canonicalLocator
        assertEquals(book.contentSHA256, loc.contentSHA256)
        assertEquals(book.fileByteCount, loc.fileByteCount)
        assertEquals(book.originalFormat.name, loc.format)
        assertEquals(book.fingerprintKey, loc.fingerprintKey)
        assertEquals("ch1.xhtml", loc.href)
    }

    @Test
    fun nestedChildren_flattenWithCorrectDepth() = runTest {
        val grandchild = link("part1/ch1.1.1.xhtml", "1.1.1")
        val child = link("part1/ch1.1.xhtml", "1.1", children = listOf(grandchild))
        val top = link("part1.xhtml", "Part 1", children = listOf(child))
        val provider = ReadiumTocProvider(
            source(listOf(top)) { readiumLocator(it.href.toString()) }, book,
        )

        val entries = provider.toc()

        assertEquals(listOf("Part 1", "1.1", "1.1.1"), entries.map { it.title })
        assertEquals(listOf(0, 1, 2), entries.map { it.depth })
    }

    @Test
    fun linkWithNullLocator_isSkipped() = runTest {
        val a = link("a.xhtml", "A")
        val b = link("b.xhtml", "B")
        val c = link("c.xhtml", "C")
        // Only a and c resolve; b resolves to null → skipped.
        val provider = ReadiumTocProvider(
            source(listOf(a, b, c)) { l ->
                if (l.href.toString() == "b.xhtml") null else readiumLocator(l.href.toString())
            },
            book,
        )

        val entries = provider.toc()

        assertEquals(listOf("A", "C"), entries.map { it.title })
    }

    @Test
    fun nullTitle_isTolerated() = runTest {
        val provider = ReadiumTocProvider(
            source(listOf(link("ch1.xhtml", null))) { readiumLocator("ch1.xhtml") }, book,
        )

        val entries = provider.toc()

        assertEquals(1, entries.size)
        assertNull(entries[0].title)
        assertNotNull("canonical locator still built for an untitled entry", entries[0].canonicalLocator)
    }

    @Test
    fun emptyPublication_yieldsEmptyList() = runTest {
        val provider = ReadiumTocProvider(source(emptyList()) { readiumLocator("x") }, book)
        assertTrue(provider.toc().isEmpty())
    }

    @Test
    fun emptyProvider_yieldsEmptyList() = runTest {
        assertTrue(EmptyTocProvider.toc().isEmpty())
    }

    @Test
    fun duplicateHrefs_differentFragments_yieldDistinctEntries() = runTest {
        val a = link("ch1.xhtml#s1", "Section 1")
        val b = link("ch1.xhtml#s2", "Section 2")
        val provider = ReadiumTocProvider(
            source(listOf(a, b)) { readiumLocator(it.href.toString()) }, book,
        )

        val entries = provider.toc()

        assertEquals(2, entries.size)
        assertEquals(listOf("Section 1", "Section 2"), entries.map { it.title })
        // Distinct native locators (different fragments) retained per entry.
        assertNotNull(entries[0].epubReadiumLocator)
        assertNotNull(entries[1].epubReadiumLocator)
        assertFalse(
            "distinct fragment locators are not the same object",
            entries[0].epubReadiumLocator === entries[1].epubReadiumLocator,
        )
    }

    @Test
    fun epubReadiumLocator_isRetainedPerEntry() = runTest {
        val native = readiumLocator("ch5.xhtml", position = 42)
        val provider = ReadiumTocProvider(source(listOf(link("ch5.xhtml", "Ch 5"))) { native }, book)

        val entries = provider.toc()

        assertEquals(1, entries.size)
        assertTrue("the exact native Readium locator is retained", entries[0].epubReadiumLocator === native)
    }

    @Test
    fun pageLabel_derivedFromReadiumPosition_elseNull() = runTest {
        val withPos = link("ch1.xhtml", "Ch 1")
        val noPos = link("ch2.xhtml", "Ch 2")
        val provider = ReadiumTocProvider(
            source(listOf(withPos, noPos)) { l ->
                if (l.href.toString() == "ch1.xhtml") readiumLocator("ch1.xhtml", position = 7)
                else readiumLocator("ch2.xhtml", position = null)
            },
            book,
        )

        val entries = provider.toc()

        assertEquals("7", entries[0].pageLabel)
        assertNull(entries[1].pageLabel)
    }
}
