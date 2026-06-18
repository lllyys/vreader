package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import vreader.contracts.ReaderLocatorEngine

/**
 * ReadiumLocatorBridge maps Readium's Locator JSON ↔ the VReaderLocator envelope
 * (feature #106 WI-6). Pure JVM — no Android/Readium dependency, just the documented
 * Readium Locator JSON shape.
 */
class ReadiumLocatorBridgeTest {
    private val bridge = ReadiumLocatorBridge()
    private val sha = "a".repeat(64)
    private val bytes = 4096L

    @Test
    fun toEnvelope_keepsVerbatimJSON_andDerivesCanonicalFallback() {
        val readiumJson = """
            {"href":"/OEBPS/ch3.xhtml","type":"application/xhtml+xml","title":"Ch 3",
             "locations":{"progression":0.4213,"totalProgression":0.18,"position":12},
             "text":{"before":"… and then ","highlight":"Call me Ishmael","after":" . Some"}}
        """.trimIndent()

        val env = bridge.toEnvelope(readiumJson, sha, bytes, BookFormat.epub)

        assertEquals(ReaderLocatorEngine.readium, env.engine)
        assertEquals("verbatim Readium JSON kept for precise restore", readiumJson, env.readiumLocatorJSON)
        assertEquals(BookFormat.epub, env.originalFormat)
        assertEquals(Identity.canonicalKey("epub", sha, bytes), env.fingerprintKey)

        val fb = env.legacyLocator!!
        assertEquals("/OEBPS/ch3.xhtml", fb.href)
        assertEquals(0.4213, fb.progression!!, 1e-9)
        assertEquals(0.18, fb.totalProgression!!, 1e-9)
        assertEquals("Call me Ishmael", fb.textQuote)
        assertEquals("… and then ", fb.textContextBefore)
        assertEquals(" . Some", fb.textContextAfter)
        assertEquals(sha, fb.contentSHA256)
        assertEquals(bytes, fb.fileByteCount)
    }

    @Test
    fun toEnvelope_minimalJSON_derivesNullableFields() {
        val env = bridge.toEnvelope("""{"href":"/c.xhtml"}""", sha, bytes, BookFormat.epub)
        val fb = env.legacyLocator!!
        assertEquals("/c.xhtml", fb.href)
        assertNull(fb.progression)
        assertNull(fb.textQuote)
    }

    @Test
    fun toEnvelope_ignoresUnknownReadiumFields() {
        // Real Readium locators carry cssSelector/domRange/fragments/etc. — must not break.
        val json = """
            {"href":"/c.xhtml","locations":{"progression":0.5,"cssSelector":"#x","fragments":["t=1"],
             "domRange":{"start":{"cssSelector":"#x"}}},"text":{"highlight":"q"}}
        """.trimIndent()
        val env = bridge.toEnvelope(json, sha, bytes, BookFormat.epub)
        assertEquals(0.5, env.legacyLocator!!.progression!!, 1e-9)
        assertEquals("q", env.legacyLocator!!.textQuote)
    }

    @Test
    fun readiumLocatorJSON_returnsVerbatimForReadiumEngine() {
        val json = """{"href":"/c.xhtml","locations":{"progression":0.2}}"""
        val env = bridge.toEnvelope(json, sha, bytes, BookFormat.epub)
        assertEquals(json, bridge.readiumLocatorJSON(env))
    }

    @Test
    fun toEnvelope_blankJSON_throwsTyped() {
        var threw = false
        try {
            bridge.toEnvelope("   ", sha, bytes, BookFormat.epub)
        } catch (e: ReaderLocatorParseException) {
            threw = true
        }
        assertEquals(true, threw)
    }

    @Test
    fun toEnvelope_malformedJSON_throwsTyped() {
        var threw = false
        try {
            bridge.toEnvelope("""{"href": }""", sha, bytes, BookFormat.epub)
        } catch (e: ReaderLocatorParseException) {
            threw = true
        }
        assertEquals(true, threw)
    }

    @Test
    fun readiumLocatorJSON_nullForBlankAnchor() {
        val env = vreader.contracts.VReaderLocator(
            fingerprintKey = "epub:$sha:$bytes", originalFormat = BookFormat.epub,
            engine = ReaderLocatorEngine.readium, readiumLocatorJSON = "  ", legacyLocator = null,
        )
        assertNull("blank anchor is treated as absent (consistent with ResumeResolver)", bridge.readiumLocatorJSON(env))
    }

    @Test
    fun readiumLocatorJSON_nullForLegacyEngine() {
        val legacy = vreader.contracts.VReaderLocator.wrapLegacy(
            vreader.contracts.Locator(contentSHA256 = sha, fileByteCount = bytes, format = "epub",
                href = "/c.xhtml", progression = 0.3),
        )
        assertNull("legacy engine has no Readium locator", bridge.readiumLocatorJSON(legacy))
    }
}
