package com.vreader.app.annotations

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #123 WI-2 — [AnnotationAnchor] serialization round-trip + hash stability. */
class AnnotationAnchorTest {
    @Test fun textAnchor_roundTrips() {
        val a = AnnotationAnchor.Text(sourceUnitId = "chunk-12", startUTF16 = 40, endUTF16 = 55)
        val decoded = AnnotationAnchor.decodeOrNull(AnnotationAnchor.encode(a))
        assertEquals(a, decoded)
    }

    @Test fun epubAnchor_withRange_roundTrips() {
        val a = AnnotationAnchor.Epub(
            href = "chapter1.xhtml", cfi = "/4/2[p1]:3",
            serializedRange = EpubSerializedRange("/4/2", 3, "/4/2", 18),
        )
        assertEquals(a, AnnotationAnchor.decodeOrNull(AnnotationAnchor.encode(a)))
    }

    @Test fun epubAnchor_nullRange_roundTrips() {
        val a = AnnotationAnchor.Epub(href = "c.xhtml", cfi = "/4/2:1", serializedRange = null)
        val decoded = AnnotationAnchor.decodeOrNull(AnnotationAnchor.encode(a)) as AnnotationAnchor.Epub
        assertEquals(a, decoded)
        assertNull(decoded.serializedRange)
    }

    @Test fun anchorHash_isStable_acrossInstances() {
        val a1 = AnnotationAnchor.Text("u", 1, 9)
        val a2 = AnnotationAnchor.Text("u", 1, 9)
        assertEquals(a1.anchorHash, a2.anchorHash)
        assertTrue("hex sha-256", a1.anchorHash.matches(Regex("[0-9a-f]{64}")))
    }

    @Test fun anchorHash_differs_byRangeAndKind() {
        assertNotEquals(AnnotationAnchor.Text("u", 1, 9).anchorHash, AnnotationAnchor.Text("u", 1, 10).anchorHash)
        assertNotEquals(
            AnnotationAnchor.Text("u", 1, 9).anchorHash,
            AnnotationAnchor.Epub("u", "/4:1").anchorHash,
        )
    }

    @Test fun decode_corruptOrNull_returnsNull() {
        assertNull(AnnotationAnchor.decodeOrNull(null))
        assertNull(AnnotationAnchor.decodeOrNull("not json"))
        assertNull(AnnotationAnchor.decodeOrNull("""{"kind":"bogus"}"""))
    }
}
