package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/** Feature #122 WI-2 — TxtProgress.fraction edge cases. */
class TxtProgressTest {
    @Test fun emptyTextIsZero() = assertEquals(0f, TxtProgress.fraction(0, 0))
    @Test fun start() = assertEquals(0f, TxtProgress.fraction(0, 1000))
    @Test fun midway() = assertEquals(0.5f, TxtProgress.fraction(500, 1000))
    @Test fun eofClampsToOne() = assertEquals(1f, TxtProgress.fraction(1200, 1000))
    @Test fun negativeClampsToZero() = assertEquals(0f, TxtProgress.fraction(-5, 1000))
}
