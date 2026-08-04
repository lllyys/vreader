package com.vreader.app.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Feature #164 WI-1 — the logcat level column maps onto exactly the six priorities the
 * platform can emit, and nothing else. `S` is the suppression threshold, never an entry.
 */
class DiagnosticsLevelTest {

    @Test
    fun fromPriorityChar_mapsEveryEmittablePriority() {
        assertEquals(DiagnosticsLevel.VERBOSE, DiagnosticsLevel.fromPriorityChar('V'))
        assertEquals(DiagnosticsLevel.DEBUG, DiagnosticsLevel.fromPriorityChar('D'))
        assertEquals(DiagnosticsLevel.INFO, DiagnosticsLevel.fromPriorityChar('I'))
        assertEquals(DiagnosticsLevel.WARN, DiagnosticsLevel.fromPriorityChar('W'))
        assertEquals(DiagnosticsLevel.ERROR, DiagnosticsLevel.fromPriorityChar('E'))
        assertEquals(DiagnosticsLevel.ASSERT, DiagnosticsLevel.fromPriorityChar('F'))
    }

    @Test
    fun fromPriorityChar_returnsNullForSilentAndUnknown() {
        assertNull("S is a threshold, not an emitted level", DiagnosticsLevel.fromPriorityChar('S'))
        assertNull(DiagnosticsLevel.fromPriorityChar('A'))
        assertNull(DiagnosticsLevel.fromPriorityChar('?'))
        assertNull(DiagnosticsLevel.fromPriorityChar(' '))
        assertNull("the column is uppercase; a lowercase char is not a level",
            DiagnosticsLevel.fromPriorityChar('w'))
        assertNull(DiagnosticsLevel.fromPriorityChar('中'))
    }

    @Test
    fun everyLevelRoundTripsThroughItsOwnPriorityChar() {
        DiagnosticsLevel.entries.forEach { level ->
            assertEquals(level, DiagnosticsLevel.fromPriorityChar(level.priorityChar))
        }
    }

    @Test
    fun exportTagsAreStableUppercaseTokens() {
        // The export payload's on-disk format depends on these — a rename of an enum
        // constant must not silently change them.
        assertEquals("VERBOSE", DiagnosticsLevel.VERBOSE.exportTag)
        assertEquals("DEBUG", DiagnosticsLevel.DEBUG.exportTag)
        assertEquals("INFO", DiagnosticsLevel.INFO.exportTag)
        assertEquals("WARN", DiagnosticsLevel.WARN.exportTag)
        assertEquals("ERROR", DiagnosticsLevel.ERROR.exportTag)
        assertEquals("ASSERT", DiagnosticsLevel.ASSERT.exportTag)
    }

    @Test
    fun priorityCharsAreDistinct() {
        val chars = DiagnosticsLevel.entries.map { it.priorityChar }
        assertEquals(chars.size, chars.toSet().size)
    }
}
