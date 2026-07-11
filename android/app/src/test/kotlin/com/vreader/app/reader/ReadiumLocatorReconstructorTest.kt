package com.vreader.app.reader

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator

/**
 * Feature #135 WI-1 - [ReadiumLocatorReconstructor]: turns a vreader canonical
 * [Locator] (a persisted bookmark carries only this - NO precise Readium JSON) into
 * a real Readium [ReadiumLocator] so the bookmark can be jumped to after reopen /
 * backup-restore. The faithful in-codebase seam is
 *   Url(href)? -> publication.linkWithHref(Url) -> publication.locatorFromLink(Link)
 *     -> .copyWithLocations(progression, fragments = cfi?) (+ text from textQuote/context).
 * EVERY degrade returns null so the caller keeps the bookmark sheet open.
 *
 * Mirrors [com.vreader.app.reader.nav.ReadiumTocProviderTest]: [Publication] is a
 * `final` unmockable class, so the two operations are extracted behind the
 * [PublicationLocatorSource] seam and driven with real Readium [Link]/[Locator]
 * objects under Robolectric (Readium `Url`/`MediaType`/`toJSON` touch the Android
 * `android.net.Uri`/`org.json` runtime).
 */
@RunWith(RobolectricTestRunner::class)
class ReadiumLocatorReconstructorTest {

    private val sha = "a".repeat(64)

    private fun canonical(
        href: String? = "chapter1.xhtml",
        progression: Double? = 0.42,
        cfi: String? = null,
        textQuote: String? = null,
        textContextBefore: String? = null,
        textContextAfter: String? = null,
        page: Int? = null,
        format: String = "epub",
        contentSHA256: String = sha,
        fileByteCount: Long = 2048L,
    ) = Locator(
        contentSHA256 = contentSHA256,
        fileByteCount = fileByteCount,
        format = format,
        href = href,
        progression = progression,
        cfi = cfi,
        textQuote = textQuote,
        textContextBefore = textContextBefore,
        textContextAfter = textContextAfter,
        page = page,
    )

    /** The identity of the "current book" the publication represents (matches [canonical]'s default). */
    private val bookFingerprintKey = canonical().fingerprintKey

    /** Builds the subject bound to [bookFingerprintKey] unless a mismatching key is requested. */
    private fun reconstructor(
        source: PublicationLocatorSource,
        expectedFingerprintKey: String = bookFingerprintKey,
    ) = ReadiumLocatorReconstructor(expectedFingerprintKey, source)

    private fun readiumLink(href: String) = Link(
        href = org.readium.r2.shared.publication.Href(Url(href)!!),
        mediaType = MediaType.XHTML,
    )

    /** The base locator `locatorFromLink` returns: resolved href + a NON-null mediaType. */
    private fun resolvedLocator(href: String) = ReadiumLocator(
        href = Url(href)!!,
        mediaType = MediaType.XHTML,
        locations = ReadiumLocator.Locations(),
    )

    /**
     * A test seam mirroring [com.vreader.app.reader.nav.PublicationTocSource]: resolves
     * an href -> [Link] (or null when unresolvable), and a [Link] -> base [ReadiumLocator]
     * (or null when the link cannot be located).
     */
    private fun source(
        knownHrefs: Set<String>,
        locatable: Set<String> = knownHrefs,
    ) = object : PublicationLocatorSource {
        override fun linkWithHref(href: Url): Link? =
            if (href.toString() in knownHrefs) readiumLink(href.toString()) else null

        override fun locatorFromLink(link: Link): ReadiumLocator? {
            val h = link.href.toString()
            return if (h in locatable) resolvedLocator(h) else null
        }
    }

    // --- resolvable href + progression -> a valid Readium locator ---

    @Test
    fun resolvableHrefAndProgression_reconstructsValidLocator() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        val readium = subject.toReadium(canonical(href = "chapter1.xhtml", progression = 0.42))

        assertNotNull(readium)
        assertEquals("chapter1.xhtml", readium!!.href.toString())
        assertEquals(0.42, readium.locations.progression!!, 1e-9)
        // locatorFromLink supplied a non-null mediaType (the whole reason not to hand-build).
        assertNotNull(readium.mediaType)
    }

    @Test
    fun nullProgression_stillReconstructsFromResolvedHref() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        val readium = subject.toReadium(canonical(href = "chapter1.xhtml", progression = null))

        assertNotNull(readium)
        assertEquals("chapter1.xhtml", readium!!.href.toString())
        assertNull(readium.locations.progression)
    }

    // --- cfi -> fragments ---

    @Test
    fun cfi_carriedAsFragment() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        val readium = subject.toReadium(
            canonical(href = "chapter1.xhtml", progression = 0.5, cfi = "epubcfi(/6/4!/4/2/1:0)"),
        )

        assertNotNull(readium)
        assertEquals(listOf("epubcfi(/6/4!/4/2/1:0)"), readium!!.locations.fragments)
        assertEquals(0.5, readium.locations.progression!!, 1e-9)
    }

    // --- textQuote -> text.highlight (+ context) ---

    @Test
    fun textQuoteAndContext_carriedAsText() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        val readium = subject.toReadium(
            canonical(
                href = "chapter1.xhtml",
                textQuote = "Call me Ishmael",
                textContextBefore = "before-context ",
                textContextAfter = " Some years ago",
            ),
        )

        assertNotNull(readium)
        assertEquals("Call me Ishmael", readium!!.text.highlight)
        assertEquals("before-context ", readium.text.before)
        assertEquals(" Some years ago", readium.text.after)
    }

    @Test
    fun noTextQuote_leavesTextEmpty() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        val readium = subject.toReadium(canonical(href = "chapter1.xhtml", textQuote = null))

        assertNotNull(readium)
        assertNull(readium!!.text.highlight)
    }

    // --- degrade paths, ALL return null ---

    @Test
    fun malformedHref_nullUrl_returnsNull() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        // A space is not a valid URL character, so Url("...") is null.
        val readium = subject.toReadium(canonical(href = "a b c not a url"))

        assertNull(readium)
    }

    @Test
    fun blankHref_returnsNull() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        assertNull(subject.toReadium(canonical(href = "")))
    }

    @Test
    fun nullHref_returnsNull() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        assertNull(subject.toReadium(canonical(href = null)))
    }

    @Test
    fun unresolvableHref_linkWithHrefNull_returnsNull() = runTest {
        // renamed/missing resource: a well-formed Url, but not in the publication.
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        assertNull(subject.toReadium(canonical(href = "renamed-or-missing.xhtml")))
    }

    @Test
    fun linkResolvesButLocatorFromLinkNull_returnsNull() = runTest {
        // The link exists but cannot be located (e.g. not in the reading order).
        val subject = reconstructor(
            source(knownHrefs = setOf("cover.xhtml"), locatable = emptySet()),
        )

        assertNull(subject.toReadium(canonical(href = "cover.xhtml")))
    }

    @Test
    fun structurallyInvalidCanonical_returnsNull() = runTest {
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        // Negative page -> Locator.validate() rejects; reconstruction must not proceed.
        val invalid = canonical(href = "chapter1.xhtml", page = -1)
        assertNull(subject.toReadium(invalid))
    }

    @Test
    fun fingerprintMismatch_returnsNull_withoutTouchingPublication() = runTest {
        // A locator for a DIFFERENT book (different content bytes -> different
        // fingerprintKey) must be rejected BEFORE the publication is queried, even when
        // its href would coincidentally resolve here. Assert the seam is never invoked.
        var linkWithHrefCalls = 0
        var locatorFromLinkCalls = 0
        val countingSource = object : PublicationLocatorSource {
            override fun linkWithHref(href: Url): Link? {
                linkWithHrefCalls++
                return readiumLink(href.toString())
            }

            override fun locatorFromLink(link: Link): ReadiumLocator? {
                locatorFromLinkCalls++
                return resolvedLocator(link.href.toString())
            }
        }
        val subject = reconstructor(countingSource)

        // Same href as the current book, but different content bytes -> different book.
        val otherBook = canonical(href = "chapter1.xhtml", contentSHA256 = "b".repeat(64))
        val readium = subject.toReadium(otherBook)

        assertNull(readium)
        assertEquals("linkWithHref must not be called on a foreign locator", 0, linkWithHrefCalls)
        assertEquals("locatorFromLink must not be called on a foreign locator", 0, locatorFromLinkCalls)
    }

    @Test
    fun matchingFingerprint_reconstructs() = runTest {
        // Same book identity (default sha/byteCount) resolves normally - the identity
        // gate is a filter on FOREIGN locators, not a blanket rejection.
        val subject = reconstructor(source(setOf("chapter1.xhtml")))

        val readium = subject.toReadium(canonical(href = "chapter1.xhtml"))

        assertNotNull(readium)
        assertEquals(bookFingerprintKey, canonical(href = "chapter1.xhtml").fingerprintKey)
    }

    // --- round-trip: a resolved bookmark reconstructs to the same href + progression ---

    @Test
    fun roundTrip_hrefAndProgressionPreserved() = runTest {
        val subject = reconstructor(source(setOf("part2/ch3.xhtml")))
        val original = canonical(href = "part2/ch3.xhtml", progression = 0.73, cfi = "epubcfi(/6/8!/4/10)")

        val readium = subject.toReadium(original)

        assertNotNull(readium)
        assertEquals(original.href, readium!!.href.toString())
        assertEquals(original.progression!!, readium.locations.progression!!, 1e-9)
        assertEquals(listOf(original.cfi), readium.locations.fragments)
    }
}
