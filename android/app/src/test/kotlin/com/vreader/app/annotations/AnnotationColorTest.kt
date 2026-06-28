package com.vreader.app.annotations

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #123 WI-2 — [AnnotationColor] round-trip + the design/iOS parity guard. */
class AnnotationColorTest {
    @Test fun allFiveColors_roundTripByKey() {
        for (c in AnnotationColor.entries) {
            assertEquals(c, AnnotationColor.from(c.key))
        }
        assertEquals(5, AnnotationColor.entries.size)
    }

    @Test fun unknownOrNull_returnsNull() {
        assertNull(AnnotationColor.from("orange"))
        assertNull(AnnotationColor.from(null))
        assertNull(AnnotationColor.from(""))
    }

    @Test fun palette_isInDesignOrder() {
        assertEquals(
            listOf("yellow", "green", "blue", "pink", "red"),
            AnnotationColor.palette.map { it.key },
        )
    }

    @Test fun default_isYellow() {
        assertEquals(AnnotationColor.yellow, AnnotationColor.DEFAULT)
    }

    @Test fun red_isAndroidOnly_iOSWouldTreatAsUnknown() {
        // iOS NamedHighlightColor has only {yellow, pink, green, blue}. Android's 5th color `red`
        // is design parity, not iOS-model parity: its key "red" is NOT one of the iOS four, so iOS's
        // nil-tolerant from() returns null (graceful unknown) — it never corrupts data on restore.
        val iosColors = setOf("yellow", "pink", "green", "blue")
        assertTrue("red is the Android-only extra", AnnotationColor.red.key !in iosColors)
        for (shared in iosColors) {
            assertTrue("the 4 iOS colors all exist on Android", AnnotationColor.from(shared) != null)
        }
    }
}
