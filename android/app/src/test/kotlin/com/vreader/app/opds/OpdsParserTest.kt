package com.vreader.app.opds

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #117 WI-1 — OpdsParser against fixture Atom/OPDS feeds: navigation vs acquisition,
 * acquisition-kind selection, relative-href resolution, pagination/search, dedup, CJK, the default
 * Atom namespace, and the XXE defences (DOCTYPE rejected, UTF-16 not a bypass).
 */
class OpdsParserTest {
    private val base = "https://cat.example.org/opds/root.xml"

    @Test fun parses_navigationFeed_defaultAtomNamespace() {
        val xml = """<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>道诡异仙 Catalog</title><id>urn:root</id>
  <link rel="self" href="/opds/root.xml" type="application/atom+xml"/>
  <link rel="search" href="/opds/search.xml" type="application/opensearchdescription+xml"/>
  <entry><title>新书 New</title><id>urn:nav:new</id>
    <link href="/opds/new.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  </entry>
</feed>"""
        val feed = OpdsParser.parse(xml.toByteArray(), base)
        assertEquals("道诡异仙 Catalog", feed.title)
        assertEquals(OpdsFeedKind.navigation, feed.kind)
        assertEquals("https://cat.example.org/opds/search.xml", feed.searchUrl)
        val nav = feed.entries.single()
        assertEquals("新书 New", nav.title)
        assertEquals("https://cat.example.org/opds/new.xml", nav.navigationUrl(feed.baseUrl))
    }

    @Test fun parses_acquisitionFeed_selectsImportableLink() {
        val xml = """<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Books</title><id>urn:books</id>
  <link rel="next" href="page2.xml" type="application/atom+xml"/>
  <entry>
    <title>Moby-Dick</title><id>urn:b1</id><author><name>Herman Melville</name></author>
    <summary>A whale.</summary><updated>2026-06-01T00:00:00Z</updated>
    <link rel="http://opds-spec.org/acquisition/open-access" href="moby.epub" type="application/epub+zip"/>
    <link rel="http://opds-spec.org/acquisition/buy" href="moby-buy" type="application/epub+zip"/>
    <link rel="http://opds-spec.org/image" href="moby.png" type="image/png"/>
  </entry>
</feed>"""
        val feed = OpdsParser.parse(xml.toByteArray(), base)
        assertEquals(OpdsFeedKind.acquisition, feed.kind)
        assertEquals("https://cat.example.org/opds/page2.xml", feed.nextPageUrl)
        val e = feed.entries.single()
        assertEquals("Herman Melville", e.author)
        assertEquals("A whale.", e.summary)
        assertEquals("https://cat.example.org/opds/moby.png", e.coverUrl(feed.baseUrl))
        // Two acquisition links; only the open-access one auto-imports, the buy link does not.
        assertEquals(2, e.acquisitionLinks.size)
        val importable = e.acquisitionLinks.filter { it.isAutoImportable }
        assertEquals(1, importable.size)
        assertEquals(AcquisitionKind.openAccess, importable.single().acquisitionKind)
        assertEquals("epub", importable.single().formatExtension)
        assertFalse(e.acquisitionLinks.first { it.acquisitionKind == AcquisitionKind.buy }.isAutoImportable)
    }

    @Test fun resolvesRelativeAndAbsoluteHrefs() {
        val link = OpdsLink("http://opds-spec.org/acquisition", "../files/a.epub", "application/epub+zip")
        assertEquals("https://cat.example.org/files/a.epub", link.resolvedHref(base))
        val abs = OpdsLink(null, "https://other.org/x.epub", "application/epub+zip")
        assertEquals("https://other.org/x.epub", abs.resolvedHref(base))
        assertEquals("a.epub", OpdsLink(null, "a.epub", null).resolvedHref(null))  // no base → as-is
    }

    @Test fun dedupesEntriesById_firstWins() {
        val xml = """<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>T</title><id>i</id>
  <entry><title>First</title><id>dup</id></entry>
  <entry><title>Second</title><id>dup</id></entry>
  <entry><title>Other</title><id>x</id></entry>
</feed>"""
        val feed = OpdsParser.parse(xml.toByteArray(), base)
        assertEquals(listOf("First", "Other"), feed.entries.map { it.title })
    }

    @Test fun emptyData_throws() {
        assertThrows(OpdsError.EmptyData::class.java) { OpdsParser.parse(ByteArray(0), base) }
    }

    @Test fun malformedXml_throwsInvalidXml() {
        assertThrows(OpdsError.InvalidXml::class.java) {
            OpdsParser.parse("<feed><title>oops".toByteArray(), base)
        }
    }

    @Test fun doctypeFeed_isRejected() {
        val xml = """<?xml version="1.0"?><!DOCTYPE feed [<!ENTITY x SYSTEM "file:///etc/passwd">]>
<feed xmlns="http://www.w3.org/2005/Atom"><title>&x;</title><id>i</id></feed>"""
        assertThrows(OpdsError.InvalidXml::class.java) { OpdsParser.parse(xml.toByteArray(), base) }
    }

    @Test fun utf16Doctype_isNotABypass() {
        val xml = """<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE feed [<!ENTITY x SYSTEM "file:///etc/passwd">]>
<feed xmlns="http://www.w3.org/2005/Atom"><title>&x;</title><id>i</id></feed>"""
        // UTF-16 bytes: the UTF-8 DOCTYPE scan won't see it literally, but the parser is fed a UTF-8
        // Reader → the body is invalid UTF-8 XML → InvalidXml. Either way no entity expands.
        val result = runCatching { OpdsParser.parse(xml.toByteArray(Charsets.UTF_16), base) }
        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is OpdsError)
    }

    @Test fun acquisitionKinds_onlyGenericAndOpenAccessAutoImport() {
        fun link(rel: String?) = OpdsLink(rel, "x.epub", "application/epub+zip")
        val acq = "http://opds-spec.org/acquisition"
        assertEquals(AcquisitionKind.generic, link(acq).acquisitionKind)
        assertTrue(link(acq).isAutoImportable)
        assertEquals(AcquisitionKind.openAccess, link("$acq/open-access").acquisitionKind)
        assertTrue(link("$acq/open-access").isAutoImportable)
        // Payment / lending / sample / subscribe / unknown sub-rel: acquisitions but NOT importable.
        for (sub in listOf("buy", "borrow", "sample", "preview", "subscribe", "indirectAcquisition", "foo")) {
            val l = link("$acq/$sub")
            assertTrue("$sub is an acquisition", l.isAcquisition)
            assertFalse("$sub must not auto-import", l.isAutoImportable)
        }
        // A rel that merely STARTS with the prefix but isn't `/`-delimited is NOT an acquisition.
        assertFalse(link("${acq}XYZ").isAcquisition)
        assertEquals(AcquisitionKind.none, link("${acq}XYZ").acquisitionKind)
        assertEquals(AcquisitionKind.none, link(null).acquisitionKind)
    }

    @Test fun formatExtension_isCaseAndParamInsensitive() {
        assertEquals("epub", OpdsLink(null, "x", "Application/EPUB+ZIP; charset=utf-8").formatExtension)
        assertEquals("pdf", OpdsLink(null, "x", "APPLICATION/PDF").formatExtension)
        assertEquals("azw3", OpdsLink(null, "x", "application/x-mobipocket-ebook").formatExtension)
        assertNull(OpdsLink(null, "x", "text/html").formatExtension)
        assertNull(OpdsLink(null, "x", null).formatExtension)
    }

    @Test fun resolvesQueryAndFragmentOnlyHrefs_preserveBasePath() {
        // base path is a FILE (root.xml) — a `?`/`#`-only ref must keep root.xml, not the dir.
        assertEquals("https://cat.example.org/opds/root.xml?page=2", OpdsLink(null, "?page=2", null).resolvedHref(base))
        assertEquals("https://cat.example.org/opds/root.xml#sec", OpdsLink(null, "#sec", null).resolvedHref(base))
    }

    @Test fun missingOptionalFields_areNull() {
        val xml = """<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>T</title><id>i</id>
  <entry><title>Bare</title><id>b</id>
    <link rel="http://opds-spec.org/acquisition" href="b.epub" type="application/epub+zip"/>
  </entry>
</feed>"""
        val e = OpdsParser.parse(xml.toByteArray(), base).entries.single()
        assertNull(e.author); assertNull(e.summary); assertNull(e.updated)
        assertEquals(AcquisitionKind.generic, e.acquisitionLinks.single().acquisitionKind)
    }
}
