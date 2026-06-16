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
