package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import vreader.contracts.ReaderLocatorEngine
import vreader.contracts.VReaderLocator

/**
 * ResumeResolver: precise-first / canonical-fallback (feature #106 WI-6, the
 * cross-platform resume rule in contracts/identity/locator.md).
 */
class ResumeResolverTest {
    private val sha = "b".repeat(64)
    private fun legacy(progression: Double) = Locator(
        contentSHA256 = sha, fileByteCount = 100, format = "epub", href = "/c.xhtml", progression = progression,
    )

    @Test
    fun nullEnvelope_isNone() {
        assertSame(ResumeTarget.None, ResumeResolver.resolve(null))
    }

    @Test
    fun readiumEngineWithJSON_isPrecise() {
        val json = """{"href":"/c.xhtml","locations":{"progression":0.7}}"""
        val env = VReaderLocator(
            fingerprintKey = "epub:$sha:100", originalFormat = BookFormat.epub,
            engine = ReaderLocatorEngine.readium, readiumLocatorJSON = json, legacyLocator = legacy(0.7),
        )
        val target = ResumeResolver.resolve(env)
        assertTrue(target is ResumeTarget.Precise)
        assertEquals(json, (target as ResumeTarget.Precise).readiumLocatorJSON)
    }

    @Test
    fun precise_carriesCanonicalFallback_forDegradedRestore() {
        // The precise target must keep the canonical fallback so the host can degrade
        // if the Readium anchor won't reapply (Gate-4 High).
        val json = """{"href":"/c.xhtml","locations":{"progression":0.7}}"""
        val fallback = legacy(0.7)
        val env = VReaderLocator(
            fingerprintKey = "epub:$sha:100", originalFormat = BookFormat.epub,
            engine = ReaderLocatorEngine.readium, readiumLocatorJSON = json, legacyLocator = fallback,
        )
        val target = ResumeResolver.resolve(env) as ResumeTarget.Precise
        assertEquals(fallback, target.canonicalFallback)
    }

    @Test
    fun readiumEngineWithBlankJSON_fallsBackToCanonical() {
        val env = VReaderLocator(
            fingerprintKey = "epub:$sha:100", originalFormat = BookFormat.epub,
            engine = ReaderLocatorEngine.readium, readiumLocatorJSON = "  ", legacyLocator = legacy(0.4),
        )
        val target = ResumeResolver.resolve(env)
        assertTrue(target is ResumeTarget.Canonical)
        assertEquals(0.4, (target as ResumeTarget.Canonical).locator.progression!!, 1e-9)
    }

    @Test
    fun legacyEngine_isCanonical() {
        val env = VReaderLocator.wrapLegacy(legacy(0.25))
        val target = ResumeResolver.resolve(env)
        assertTrue(target is ResumeTarget.Canonical)
        assertEquals(0.25, (target as ResumeTarget.Canonical).locator.progression!!, 1e-9)
    }

    @Test
    fun readiumEngineWithNoAnchors_isNone() {
        val env = VReaderLocator(
            fingerprintKey = "epub:$sha:100", originalFormat = BookFormat.epub,
            engine = ReaderLocatorEngine.readium, readiumLocatorJSON = null, legacyLocator = null,
        )
        assertSame(ResumeTarget.None, ResumeResolver.resolve(env))
    }
}
