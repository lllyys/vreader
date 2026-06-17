package vreader.contracts

import kotlinx.serialization.json.*
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Asserts the Kotlin Identity impl matches the SHARED golden vectors in
 * contracts/vectors/ — the same vectors the Swift conformance suite
 * (vreaderTests) asserts against. Both green against one vector set = the
 * cross-platform identity contract holds.
 */
class IdentityConformanceTest {
    // The `:identity:test` Gradle task always injects this (the shared golden
    // vectors at contracts/vectors). Require it rather than a relative fallback —
    // after the WI-2 module move a stale relative path would mis-read + mis-emit.
    private val vectorsDir = File(
        System.getProperty("vreader.vectors.dir")
            ?: error("vreader.vectors.dir not set — run via `contracts/conformance/run.sh kotlin` (the :identity:test task injects it), not directly"),
    )
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
        val emitted = StringBuilder()
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
            emitted.appendLine(got)
            n++
        }
        assertTrue(n > 0, "no locator vectors loaded")
        // Emit this platform's ACTUAL canonical output so run.sh can byte-diff it
        // against the Swift output (bug #355 — proves the two platforms agree
        // directly, not only each-vs-the-shared-vector).
        val outDir = File(vectorsDir.parentFile, "conformance/.out").apply { mkdirs() }
        File(outDir, "kotlin-locator.txt").writeText(emitted.toString())
    }

    @Test fun canonicalLocatorNormalizesNFC() {
        // The canonical reference NFC-normalizes string fields (bug #356): NFD
        // input (base letter + U+0301 combining acute) must produce the NFC
        // precomposed form. Kotlin-only: iOS Locator.swift's matching NFC change
        // is migration-sensitive and tracked as feature #109, so the cross-platform
        // NFD vector isn't in the shared set yet (contract target: locator.md).
        val fromNfd = CanonicalLocator.canonicalJson(
            contentSHA256 = "d".repeat(64), fileByteCount = 3, format = "epub",
            href = "a\u0301.html", textQuote = "cafe\u0301",   // NFD: base + U+0301
        )
        val fromNfc = CanonicalLocator.canonicalJson(
            contentSHA256 = "d".repeat(64), fileByteCount = 3, format = "epub",
            href = "\u00e1.html", textQuote = "caf\u00e9",      // NFC: precomposed
        )
        assertEquals(fromNfc, fromNfd, "NFD input must canonicalize to the NFC form")
        assertTrue(fromNfd.contains("\u00e1") && fromNfd.contains("\u00e9"), "precomposed")
        assertTrue(!fromNfd.contains("\u0301"), "no combining mark in output")
    }

    @Test fun canonicalLocatorRejectsNonFinite() {
        // NaN/Inf can't be JSON vectors (bug #356) — assert the reference REJECTS
        // non-finite (require -> IllegalArgumentException) rather than silently
        // omitting it (which would collide an invalid locator with a valid
        // missing-progression one). Swift's guard is Locator.validate().
        for (p in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            assertFailsWith<IllegalArgumentException> {
                CanonicalLocator.canonicalJson(
                    contentSHA256 = "a".repeat(64), fileByteCount = 1, format = "epub",
                    progression = p,
                )
            }
            assertFailsWith<IllegalArgumentException> {
                CanonicalLocator.canonicalJson(
                    contentSHA256 = "a".repeat(64), fileByteCount = 1, format = "epub",
                    totalProgression = p,
                )
            }
        }
    }

    @Test fun cacheKeyVectors() {
        val data = load("cache-key.json")
        var n = 0
        val emitted = StringBuilder()
        for (v in data["vectors"]!!.jsonArray) {
            val o = v.jsonObject
            val got = Identity.lookupKey(
                o["bookFingerprintKey"]!!.jsonPrimitive.content,
                o["unitStorageKey"]!!.jsonPrimitive.content,
                o["targetLanguage"]!!.jsonPrimitive.content,
                o["promptVersion"]!!.jsonPrimitive.content,
            )
            assertEquals(o["expectedLookupKey"]!!.jsonPrimitive.content, got)
            emitted.appendLine(got)
            n++
        }
        assertTrue(n > 0, "no cache-key vectors loaded")
        val outDir = File(vectorsDir.parentFile, "conformance/.out").apply { mkdirs() }
        File(outDir, "kotlin-cachekey.txt").writeText(emitted.toString())
    }
}
