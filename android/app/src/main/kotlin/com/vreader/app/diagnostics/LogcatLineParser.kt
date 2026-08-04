package com.vreader.app.diagnostics

import java.time.OffsetDateTime

/**
 * Purpose: Feature #164 WI-1 — the PURE, JVM-testable half of the logcat source. Turns
 * `logcat -d -v uid -v threadtime -v year -v UTC` output into [DiagnosticsLogEntry]s.
 *
 * Line shape (sampled verbatim from emulator-5554, API 35):
 *
 *     2026-08-04 19:26:12.114 +0000  1000   572   718 W BestClock: java.time.DateTimeException: …
 *     date       time         zone   uid    pid   tid L tag        message
 *
 * Key decisions:
 * - **The uid column is NOT always numeric.** logcat prints `1000`, `wifi`, `root`, or the
 *   per-user app form `u0_a209` depending on the uid. A parser that integer-compares would
 *   drop 100% of rows on a device that renders symbolically and would degrade the whole
 *   feature to the ring buffer with NO error — a silent failure, which is the worst kind.
 *   Both renderings are therefore accepted (`u<user>_a<appId>` resolves to
 *   `user * 100000 + 10000 + appId`, Android's own uid arithmetic).
 * - **The FIRST `": "` after the level column terminates the tag.** Under `threadtime` the
 *   separator is `": "`, so a tag containing `:` is genuinely ambiguous; the rule is stated
 *   rather than left to chance, because "tolerates" would specify no expected output and any
 *   behavior would pass. A trailing bare `":"` (whitespace-stripped by some pipeline) means
 *   an empty message, not a missing tag.
 * - **Unparseable lines are continuations, not garbage.** A stack trace arrives as the entry
 *   line plus N indented lines; they belong to the previous entry's message. A continuation
 *   is only appended when the previous entry was OURS — otherwise another app's stack trace
 *   would be grafted onto our export.
 * - **A dropped row ends the continuation run.** Foreign uid, unknown level, impossible
 *   timestamp, buffer divider: all reset the "current entry" so nothing is mis-attributed.
 *
 * @coordinates-with LogcatDiagnosticsSource.kt, DiagnosticsLogEntry.kt, DiagnosticsLevel.kt
 */
object LogcatLineParser {

    /**
     * Entries oldest -> newest, keeping only rows whose uid column resolves to [ownUid].
     * Never throws: a line it cannot make sense of is either folded into the previous entry
     * or discarded.
     */
    fun parse(lines: Sequence<String>, ownUid: Int): List<DiagnosticsLogEntry> {
        val collected = ArrayList<Partial>()
        var current: Partial? = null

        for (raw in lines) {
            val line = raw.removeSuffix("\r")
            if (line.isBlank()) continue
            if (DIVIDER.matches(line)) {
                current = null
                continue
            }

            val match = ENTRY.matchEntire(line)
            if (match == null) {
                current?.message?.append('\n')?.append(line)
                continue
            }

            val groups = match.groupValues
            if (!uidMatches(groups[UID], ownUid)) {
                current = null
                continue
            }
            val level = DiagnosticsLevel.fromPriorityChar(groups[LEVEL].first())
            if (level == null) {
                current = null
                continue
            }
            val timeMillis = epochMillis(groups[DATE], groups[TIME], groups[ZONE])
            if (timeMillis == null) {
                current = null
                continue
            }

            val (category, body) = splitTagAndMessage(groups[REST])
            val (sequenceId, message) = stripMarker(body)
            val partial = Partial(timeMillis, level, category, StringBuilder(message), sequenceId)
            collected.add(partial)
            current = partial
        }

        return collected.map {
            DiagnosticsLogEntry(it.timeMillis, it.level, it.category, it.message.toString(), it.sequenceId)
        }
    }

    // ------------------------------------------------------------------ internals

    private class Partial(
        val timeMillis: Long,
        val level: DiagnosticsLevel,
        val category: String,
        val message: StringBuilder,
        val sequenceId: Long?,
    )

    private const val DATE = 1
    private const val TIME = 2
    private const val ZONE = 3
    private const val UID = 4
    private const val LEVEL = 7
    private const val REST = 8

    /**
     * The zone group is optional so a pipeline that drops it cannot make timestamps fall back
     * to the ambient zone (we default to UTC, which is what `-v UTC` requested). The level is
     * restricted to the six emittable priorities: a line with any other level char is not a
     * well-formed entry and is treated as a continuation.
     */
    private val ENTRY = Regex(
        """^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}\.\d{3})(?:\s+([+-]\d{4}))?""" +
            """\s+(\S+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s(.*)$"""
    )

    private val DIVIDER = Regex("""^-{3,}\s+(beginning of|switch to)\s+\S+\s*$""")

    private val SYMBOLIC_UID = Regex("""^u(\d+)_a(\d+)$""")

    /** Android's own uid arithmetic (`UserHandle`): uid = userId * 100000 + 10000 + appId. */
    private const val PER_USER_RANGE = 100_000L
    private const val FIRST_APPLICATION_UID = 10_000L

    private val MARKER = Regex("""^«v(\d+)»""")

    /**
     * Checked arithmetic on purpose: an absurd but well-formed token (`u99999999999_a1`) must
     * not WRAP into a value that happens to equal our uid, which would admit another uid's
     * rows into the export. Anything that overflows, or resolves outside the valid uid range,
     * simply does not match.
     */
    private fun uidMatches(token: String, ownUid: Int): Boolean {
        token.toIntOrNull()?.let { return it == ownUid }
        val match = SYMBOLIC_UID.matchEntire(token) ?: return false
        val user = match.groupValues[1].toLongOrNull() ?: return false
        val appId = match.groupValues[2].toLongOrNull() ?: return false
        val resolved = try {
            Math.addExact(Math.multiplyExact(user, PER_USER_RANGE), Math.addExact(FIRST_APPLICATION_UID, appId))
        } catch (t: ArithmeticException) {
            return false
        }
        if (resolved < 0L || resolved > Int.MAX_VALUE.toLong()) return false
        return resolved == ownUid.toLong()
    }

    private fun epochMillis(date: String, time: String, zone: String): Long? {
        val offset = when {
            zone.isEmpty() -> "Z"
            zone.length == 5 -> "${zone.substring(0, 3)}:${zone.substring(3)}"
            else -> return null
        }
        return try {
            OffsetDateTime.parse("${date}T$time$offset").toInstant().toEpochMilli()
        } catch (t: Exception) {
            null
        }
    }

    private fun splitTagAndMessage(rest: String): Pair<String, String> {
        val separator = rest.indexOf(": ")
        if (separator >= 0) return rest.substring(0, separator).trim() to rest.substring(separator + 2)
        if (rest.endsWith(":")) return rest.dropLast(1).trim() to ""
        return "" to rest
    }

    /** `«v42»body` -> `(42, "body")`. A malformed or overflowing marker stays ordinary text. */
    private fun stripMarker(message: String): Pair<Long?, String> {
        val match = MARKER.find(message) ?: return null to message
        val sequenceId = match.groupValues[1].toLongOrNull() ?: return null to message
        return sequenceId to message.substring(match.value.length)
    }
}
