package com.vreader.app.reader

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #124 WI-1 — [TxtSelection.isValid] range validation (half-open, surrogate-safe). */
class TxtSelectionValidateTest {
    private val text = "Hello, world"          // 12 chars
    private val emoji = "a😀b"       // a + 😀 (surrogate pair at 1..2) + b ; length 4

    @Test fun valid_inBoundsNonEmpty() {
        assertTrue(TxtSelection.isValid(Utf16Range(0, 5), text))
        assertTrue(TxtSelection.isValid(Utf16Range(7, 12), text))   // ends at doc EOF
        assertTrue(TxtSelection.isValid(Utf16Range(0, 1), text))    // one char
    }

    @Test fun reject_emptyInvertedNegativeOutOfBounds() {
        assertFalse("zero-length", TxtSelection.isValid(Utf16Range(3, 3), text))
        assertFalse("inverted", TxtSelection.isValid(Utf16Range(5, 2), text))
        assertFalse("negative start", TxtSelection.isValid(Utf16Range(-1, 3), text))
        assertFalse("end past length", TxtSelection.isValid(Utf16Range(8, 13), text))
    }

    @Test fun reject_midSurrogateEndpoints() {
        // offset 2 is between the high (1) and low (2) halves of 😀 → invalid endpoint
        assertFalse("start mid-surrogate", TxtSelection.isValid(Utf16Range(2, 4), emoji))
        assertFalse("end mid-surrogate", TxtSelection.isValid(Utf16Range(0, 2), emoji))
        // selecting the whole emoji (1..3) is valid
        assertTrue("whole emoji", TxtSelection.isValid(Utf16Range(1, 3), emoji))
    }
}
