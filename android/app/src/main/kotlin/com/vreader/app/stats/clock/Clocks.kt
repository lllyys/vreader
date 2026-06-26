// Purpose: feature #122 WI-1 (#110 Phase 3) — the reading-stats clock seam. TWO clocks, deliberately
// separate: ElapsedClock is MONOTONIC (durations — immune to wall-clock jumps); DateClock is the
// wall/calendar clock (local-date buckets + the wall stamp for the accounted window). Injected so the
// tracker's midnight-split / idle / jitter logic is deterministically testable.
package com.vreader.app.stats.clock

import android.os.SystemClock
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Monotonic interval time (ms) — used ONLY for durations. */
fun interface ElapsedClock {
    fun nowMillis(): Long
}

/** A half-open `[startMs, endMs)` window that lies entirely within one local date. */
data class DateSegment(val date: String, val startMs: Long, val endMs: Long)

/** Wall/calendar clock: the current local date, the wall epoch-ms stamp, and a precise split of a
 *  wall window into per-local-date segments (so a midnight crossing allocates correctly, DST included). */
interface DateClock {
    fun today(): String
    fun nowEpochMillis(): Long
    fun localDate(epochMillis: Long): String

    /**
     * Split `[startInclusiveMs, endExclusiveMs)` into half-open per-local-date [DateSegment]s at the
     * zone's local start-of-day boundaries. An empty/inverted window yields no segments.
     */
    fun splitByLocalDate(startInclusiveMs: Long, endExclusiveMs: Long): List<DateSegment>
}

/** Production ElapsedClock — `SystemClock.elapsedRealtime` (monotonic, includes deep sleep). */
class SystemElapsedClock : ElapsedClock {
    override fun nowMillis(): Long = SystemClock.elapsedRealtime()
}

/** Production DateClock over a [java.time.Clock]/[ZoneId] (defaults to the system zone). */
class SystemDateClock(
    private val clock: Clock = Clock.systemDefaultZone(),
    private val zone: ZoneId = ZoneId.systemDefault(),
) : DateClock {
    private val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    override fun today(): String = localDate(clock.millis())
    override fun nowEpochMillis(): Long = clock.millis()
    override fun localDate(epochMillis: Long): String =
        Instant.ofEpochMilli(epochMillis).atZone(zone).toLocalDate().format(fmt)

    override fun splitByLocalDate(startInclusiveMs: Long, endExclusiveMs: Long): List<DateSegment> {
        if (endExclusiveMs <= startInclusiveMs) return emptyList()
        val out = ArrayList<DateSegment>()
        var cursor = startInclusiveMs
        while (cursor < endExclusiveMs) {
            val zdt = Instant.ofEpochMilli(cursor).atZone(zone)
            val date = zdt.toLocalDate()
            // start of the NEXT local day (handles DST-sized days correctly via ZonedDateTime).
            val nextDayStartMs = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            val segEnd = minOf(nextDayStartMs, endExclusiveMs)
            out.add(DateSegment(date.format(fmt), cursor, segEnd))
            cursor = segEnd
        }
        return out
    }
}
