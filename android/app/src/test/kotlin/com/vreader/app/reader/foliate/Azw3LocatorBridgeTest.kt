package com.vreader.app.reader.foliate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.json.Json
import vreader.contracts.BookFormat
import vreader.contracts.ReaderLocatorEngine
import vreader.contracts.VReaderLocator

/** Feature #126 WI-5 — relocate → persistable VReaderLocator. */
class Azw3LocatorBridgeTest {

    private val sha = "a".repeat(64)
    private val bytes = 6_291_456L

    private fun relocate(cfi: String? = "/6/4!/2", fraction: Double? = 0.42, idx: Int = 3, total: Int = 85) =
        FoliateMessage.Relocate(cfi = cfi, fraction = fraction, sectionIndex = idx, sectionTotal = total)

    @Test fun mapsToLegacyEnvelope_azw3() {
        val env = Azw3LocatorBridge.toEnvelope(relocate(), sha, bytes)
        assertEquals(ReaderLocatorEngine.epubWKWebView, env.engine)
        assertEquals(BookFormat.azw3, env.originalFormat)
        assertNull("foliate uses the legacy lane, not Readium JSON", env.readiumLocatorJSON)
        val loc = env.legacyLocator!!
        assertEquals("azw3", loc.format)
        assertEquals(sha, loc.contentSHA256)
        assertEquals(bytes, loc.fileByteCount)
        assertEquals("/6/4!/2", loc.cfi)
        assertEquals(0.42, loc.progression!!, 0.0)
    }

    @Test fun fingerprintKey_isBookIdentity() {
        val env = Azw3LocatorBridge.toEnvelope(relocate(), sha, bytes)
        assertEquals("azw3:$sha:$bytes", env.fingerprintKey)
        assertEquals(env.fingerprintKey, env.legacyLocator!!.fingerprintKey)
    }

    @Test fun nullCfi_isOmitted() {
        val loc = Azw3LocatorBridge.toEnvelope(relocate(cfi = null), sha, bytes).legacyLocator!!
        assertNull(loc.cfi)
    }

    @Test fun blankCfi_isOmitted() {
        val loc = Azw3LocatorBridge.toEnvelope(relocate(cfi = "   "), sha, bytes).legacyLocator!!
        assertNull(loc.cfi)
    }

    @Test fun nullFraction_isOmittedProgression() {
        val loc = Azw3LocatorBridge.toEnvelope(relocate(fraction = null), sha, bytes).legacyLocator!!
        assertNull(loc.progression)
    }

    @Test fun nonFiniteFraction_isDropped() {
        val loc = Azw3LocatorBridge.toEnvelope(relocate(fraction = Double.NaN), sha, bytes).legacyLocator!!
        assertNull(loc.progression)
        val loc2 = Azw3LocatorBridge.toEnvelope(relocate(fraction = Double.POSITIVE_INFINITY), sha, bytes).legacyLocator!!
        assertNull(loc2.progression)
    }

    @Test fun fractionZero_isPreserved() {
        val loc = Azw3LocatorBridge.toEnvelope(relocate(fraction = 0.0), sha, bytes).legacyLocator!!
        assertEquals(0.0, loc.progression!!, 0.0)
    }

    @Test fun outOfRangeFiniteFraction_isPreserved_notClamped() {
        // The shared Locator contract does NOT clamp; the bridge preserves any finite value.
        assertEquals(-0.1, Azw3LocatorBridge.toEnvelope(relocate(fraction = -0.1), sha, bytes).legacyLocator!!.progression!!, 0.0)
        assertEquals(1.2, Azw3LocatorBridge.toEnvelope(relocate(fraction = 1.2), sha, bytes).legacyLocator!!.progression!!, 0.0)
    }

    @Test fun canonicalJson_isDeterministic_andNfcNormalizesStrings() {
        // Foliate CFI stored verbatim (NFD here); the canonical layer NFC-normalizes downstream.
        val nfdCfi = "/6/4!/2[caf\u0065\u0301]" // 'e' + U+0301 combining acute = NFD "caf\u00e9"
        val loc = Azw3LocatorBridge.toEnvelope(relocate(cfi = nfdCfi), sha, bytes).legacyLocator!!
        val canon = loc.canonicalJson()
        assertEquals("canonicalJson must be deterministic", canon, loc.canonicalJson())
        assertTrue("canonical JSON must NFC-normalize (caf\u00e9): $canon", canon.contains("caf\u00e9"))
        assertTrue("canonical JSON must not retain the NFD combining mark", !canon.contains("\u0301"))
    }

    @Test fun envelope_canonicalRoundTrips() {
        // The persisted envelope must decode→re-encode stably (the shared backup contract).
        val env = Azw3LocatorBridge.toEnvelope(relocate(cfi = "/6/4!/2[ch3]"), sha, bytes)
        val codec = Json { encodeDefaults = true }
        val json = codec.encodeToString(VReaderLocator.serializer(), env)
        val back = codec.decodeFromString(VReaderLocator.serializer(), json)
        assertEquals(env, back)
        assertTrue(json.contains("\"azw3\""))
    }
}
