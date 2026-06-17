package vreader.contracts

import kotlinx.serialization.json.*
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Asserts the Kotlin Identity impl matches the SHARED golden vectors in
 * contracts/vectors/ — the same vectors the Swift conformance suite
 * (vreaderTests) asserts against. Both green against one vector set = the
 * cross-platform identity contract holds.
 */
class IdentityConformanceTest {
    private val vectorsDir = File(System.getProperty("vreader.vectors.dir") ?: "../../vectors")
    private fun load(name: String) =
        Json.parseToJsonElement(File(vectorsDir, name).readText()).jsonObject

    @Test fun fingerprintVectors() {
        val data = load("fingerprint.json")
        var n = 0
        for (v in data["vectors"]!!.jsonArray) {
            val o = v.jsonObject
            val got = Identity.canonicalKey(
                o["format"]!!.jsonPrimitive.content,
                o["contentSHA256"]!!.jsonPrimitive.content,
                o["fileByteCount"]!!.jsonPrimitive.long,
            )
            assertEquals(o["expectedCanonicalKey"]!!.jsonPrimitive.content, got)
            // Round-trip parity with Swift: parse the key back to the triple.
            val parsed = Identity.parseCanonicalKey(got)
            assertEquals(o["format"]!!.jsonPrimitive.content, parsed?.format?.name)
            assertEquals(o["contentSHA256"]!!.jsonPrimitive.content, parsed?.contentSHA256)
            assertEquals(o["fileByteCount"]!!.jsonPrimitive.long, parsed?.fileByteCount)
            n++
        }
        assertTrue(n > 0, "no fingerprint vectors loaded")
        for (v in data["invalid"]!!.jsonArray) {
            val o = v.jsonObject
            val fmt = o["format"]!!.jsonPrimitive.content
            val sha = o["contentSHA256"]!!.jsonPrimitive.content
            val bytes = o["fileByteCount"]!!.jsonPrimitive.long
            assertNull(
                Identity.validatedCanonicalKey(fmt, sha, bytes),
                "invalid vector should be rejected by validatedCanonicalKey: ${o["_why"]?.jsonPrimitive?.content}",
            )
            assertNull(
                Identity.parseCanonicalKey("$fmt:$sha:$bytes"),
                "invalid vector should not parse: ${o["_why"]?.jsonPrimitive?.content}",
            )
        }
        // Malformed keys reject (mirrors Swift parse failures).
        assertNull(Identity.parseCanonicalKey("epub:tooShort:1"))
        assertNull(Identity.parseCanonicalKey("notaformat:${"a".repeat(64)}:1"))
        assertNull(Identity.parseCanonicalKey("epub:${"a".repeat(64)}:notANumber"))
        assertNull(Identity.parseCanonicalKey("missing:parts"))
    }

    @Test fun locatorVectors() {
        val data = load("locator.json")
        var n = 0
        for (v in data["vectors"]!!.jsonArray) {
            val o = v.jsonObject
            fun str(k: String) = o[k]?.jsonPrimitive?.contentOrNull
            fun int(k: String) = o[k]?.jsonPrimitive?.intOrNull
            fun dbl(k: String) = o[k]?.jsonPrimitive?.doubleOrNull
            val got = CanonicalLocator.canonicalJson(
                contentSHA256 = o["contentSHA256"]!!.jsonPrimitive.content,
                fileByteCount = o["fileByteCount"]!!.jsonPrimitive.long,
                format = o["format"]!!.jsonPrimitive.content,
                cfi = str("cfi"),
                charOffsetUTF16 = int("charOffsetUTF16"),
                charRangeEndUTF16 = int("charRangeEndUTF16"),
                charRangeStartUTF16 = int("charRangeStartUTF16"),
                href = str("href"),
                page = int("page"),
                progression = dbl("progression"),
                textContextAfter = str("textContextAfter"),
                textContextBefore = str("textContextBefore"),
                textQuote = str("textQuote"),
                totalProgression = dbl("totalProgression"),
            )
            assertEquals(o["expectedCanonicalJSON"]!!.jsonPrimitive.content, got)
            n++
        }
        assertTrue(n > 0, "no locator vectors loaded")
    }

    @Test fun canonicalLocatorOmitsNonFinite() {
        // NaN/Inf can't be JSON vectors (Codex Gate-4) — assert in code that the
        // finite gate omits them, mirroring Swift `if let p, p.isFinite`.
        for (p in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            val js = CanonicalLocator.canonicalJson(
                contentSHA256 = "a".repeat(64), fileByteCount = 1, format = "epub",
                progression = p, totalProgression = p,
            )
            // "progression" is a substring of "totalProgression", so its absence covers both.
            assertTrue(!js.contains("progression"), "non-finite progression must be omitted: $js")
        }
    }

    @Test fun cacheKeyVectors() {
        val data = load("cache-key.json")
        var n = 0
        for (v in data["vectors"]!!.jsonArray) {
            val o = v.jsonObject
            val got = Identity.lookupKey(
                o["bookFingerprintKey"]!!.jsonPrimitive.content,
                o["unitStorageKey"]!!.jsonPrimitive.content,
                o["targetLanguage"]!!.jsonPrimitive.content,
                o["promptVersion"]!!.jsonPrimitive.content,
            )
            assertEquals(o["expectedLookupKey"]!!.jsonPrimitive.content, got)
            n++
        }
        assertTrue(n > 0, "no cache-key vectors loaded")
    }
}
