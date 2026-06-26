package com.vreader.app.stats

import com.vreader.app.stats.clock.SystemDateClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneId

/** Feature #122 WI-1 — SystemDateClock.splitByLocalDate (midnight / DST / same-day / empty). Pure
 *  java.time, no Android. */
class DateClockTest {
    private val utc = ZoneId.of("UTC")
    private fun ms(iso: String) = Instant.parse(iso).toEpochMilli()
    private fun clock(zone: ZoneId) = SystemDateClock(Clock.fixed(Instant.parse("2026-06-27T12:00:00Z"), zone), zone)

    @Test fun sameDay_oneSegment() {
        val segs = clock(utc).splitByLocalDate(ms("2026-06-27T10:00:00Z"), ms("2026-06-27T11:30:00Z"))
        assertEquals(1, segs.size)
        assertEquals("2026-06-27", segs.single().date)
    }

    @Test fun midnightCrossing_splitsIntoTwoLocalDays_contiguousAndCovering() {
        val start = ms("2026-06-27T23:59:00Z"); val end = ms("2026-06-28T00:02:00Z")
        val segs = clock(utc).splitByLocalDate(start, end)
        assertEquals(listOf("2026-06-27", "2026-06-28"), segs.map { it.date })
        // contiguous half-open segments that exactly cover [start, end)
        assertEquals(start, segs.first().startMs)
        assertEquals(end, segs.last().endMs)
        assertEquals(segs[0].endMs, segs[1].startMs)
    }

    @Test fun emptyOrInvertedWindow_noSegments() {
        assertTrue(clock(utc).splitByLocalDate(ms("2026-06-27T10:00:00Z"), ms("2026-06-27T10:00:00Z")).isEmpty())
        assertTrue(clock(utc).splitByLocalDate(ms("2026-06-27T11:00:00Z"), ms("2026-06-27T10:00:00Z")).isEmpty())
    }

    @Test fun dstSpringForward_dayBoundaryStillSplitsCorrectly() {
        // US DST 2026 spring-forward is 2026-03-08 (a 23-hour local day). A window straddling the
        // 03-08→03-09 midnight must still split at the LOCAL day boundary.
        val ny = ZoneId.of("America/New_York")
        val segs = clock(ny).splitByLocalDate(ms("2026-03-09T03:30:00Z"), ms("2026-03-09T05:30:00Z"))
        // 03-09T03:30Z = 2026-03-08 23:30 local (EST→EDT already shifted); crosses into 03-09 local
        assertEquals(listOf("2026-03-08", "2026-03-09"), segs.map { it.date })
        assertEquals(segs[0].endMs, segs[1].startMs)
    }

    @Test fun dstFallBack_splitsAtLocalDayBoundary() {
        // US DST 2026 fall-back is 2026-11-01 (a 25-hour local day). A window across the 11-01→11-02
        // local midnight must split there.
        val ny = ZoneId.of("America/New_York")
        val segs = clock(ny).splitByLocalDate(ms("2026-11-02T03:30:00Z"), ms("2026-11-02T05:30:00Z"))
        assertEquals(listOf("2026-11-01", "2026-11-02"), segs.map { it.date })
        assertEquals(segs[0].endMs, segs[1].startMs)
    }

    @Test fun multiDayWindow_contiguousSegmentsPerDay() {
        val segs = clock(utc).splitByLocalDate(ms("2026-06-26T22:00:00Z"), ms("2026-06-29T01:00:00Z"))
        assertEquals(listOf("2026-06-26", "2026-06-27", "2026-06-28", "2026-06-29"), segs.map { it.date })
        // every adjacent pair is contiguous (no gaps/overlaps), covering the whole window
        segs.zipWithNext().forEach { (a, b) -> assertEquals(a.endMs, b.startMs) }
        assertEquals(ms("2026-06-26T22:00:00Z"), segs.first().startMs)
        assertEquals(ms("2026-06-29T01:00:00Z"), segs.last().endMs)
    }

    @Test fun exactMidnightBoundaries_noZeroLengthTrailingSegment() {
        // a window that ENDS exactly at a local midnight must not emit a zero-length next-day segment
        val segs = clock(utc).splitByLocalDate(ms("2026-06-27T00:00:00Z"), ms("2026-06-28T00:00:00Z"))
        assertEquals(listOf("2026-06-27"), segs.map { it.date })
        assertEquals(ms("2026-06-27T00:00:00Z"), segs.single().startMs)
        assertEquals(ms("2026-06-28T00:00:00Z"), segs.single().endMs)
    }

    @Test fun localDateAndToday() {
        val c = clock(utc)
        assertEquals("2026-06-27", c.today())
        assertEquals("2026-06-27", c.localDate(ms("2026-06-27T00:00:00Z")))
    }
}
