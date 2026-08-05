package com.vreader.app.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale

/**
 * Feature #164 WI-5 — [DiagnosticsDayGrouper]: local-calendar-day sectioning for the viewer list.
 *
 * The load-bearing property under test is that EVERY temporal decision is taken against an INJECTED
 * `now` + `zone` + `locale`. A grouper that reaches for the ambient clock or `ZoneId.systemDefault()`
 * passes on the author's machine at the author's hour and fails elsewhere, so no test here uses the
 * wall clock — every instant is built from a named local time in a named zone.
 */
class DiagnosticsDayGrouperTest {

    // ── fixtures ────────────────────────────────────────────────────────────────────────────────

    private val newYork: ZoneId = ZoneId.of("America/New_York")
    private val shanghai: ZoneId = ZoneId.of("Asia/Shanghai")

    /** `"2026-06-10T14:32:07"` in [zone] -> epoch millis. */
    private fun at(local: String, zone: ZoneId): Long =
        LocalDateTime.parse(local).atZone(zone).toInstant().toEpochMilli()

    private fun identified(id: Int, millis: Long, message: String = "m$id"): IdentifiedDiagnosticsEntry =
        IdentifiedDiagnosticsEntry(
            id = id,
            entry = DiagnosticsLogEntry(
                timeMillis = millis,
                level = DiagnosticsLevel.INFO,
                category = "Library",
                message = message,
            ),
        )

    // ── ordering + identity ─────────────────────────────────────────────────────────────────────

    @Test
    fun emptyEntries_produceNoSections() {
        val sections = DiagnosticsDayGrouper.sections(
            entries = emptyList(),
            nowMillis = at("2026-06-10T09:00:00", newYork),
            zone = newYork,
            locale = Locale.ENGLISH,
        )
        assertEquals(emptyList<DiagnosticsDaySection>(), sections)
    }

    @Test
    fun sectionsAreNewestDayFirst_andNewestEntryFirstWithinADay() {
        val entries = listOf(
            identified(0, at("2026-06-08T08:00:00", newYork)),
            identified(1, at("2026-06-10T09:00:00", newYork)),
            identified(2, at("2026-06-10T17:45:00", newYork)),
            identified(3, at("2026-06-09T23:59:00", newYork)),
        )

        val sections = DiagnosticsDayGrouper.sections(
            entries = entries,
            nowMillis = at("2026-06-10T20:00:00", newYork),
            zone = newYork,
            locale = Locale.ENGLISH,
        )

        assertEquals(listOf("Today · 10 June", "Yesterday · 9 June", "8 June"), sections.map { it.header })
        // Newest-first WITHIN the day: 17:45 (id 2) precedes 09:00 (id 1).
        assertEquals(listOf(2, 1), sections[0].entries.map { it.id })
        assertEquals(listOf(3), sections[1].entries.map { it.id })
        assertEquals(listOf(0), sections[2].entries.map { it.id })
    }

    @Test
    fun callerAssignedIdentityIsCarriedThroughUnchanged() {
        val entries = listOf(
            identified(7, at("2026-06-10T09:00:00", newYork)),
            identified(9, at("2026-06-10T10:00:00", newYork)),
        )

        val sections = DiagnosticsDayGrouper.sections(
            entries, at("2026-06-10T20:00:00", newYork), newYork, Locale.ENGLISH,
        )

        assertEquals(listOf(9, 7), sections.single().entries.map { it.id })
    }

    @Test
    fun entriesWithIdenticalTimestampsKeepTheirIncomingOrder() {
        val same = at("2026-06-10T09:00:00", newYork)
        val sections = DiagnosticsDayGrouper.sections(
            listOf(identified(0, same), identified(1, same), identified(2, same)),
            at("2026-06-10T20:00:00", newYork), newYork, Locale.ENGLISH,
        )
        assertEquals(listOf(0, 1, 2), sections.single().entries.map { it.id })
    }

    // ── day-header format (design `vreader-diagnostics.jsx:308`) ────────────────────────────────

    @Test
    fun todayAndYesterdayCarryTheDateSuffix_olderDaysCarryTheDateAlone() {
        val sections = DiagnosticsDayGrouper.sections(
            listOf(
                identified(0, at("2026-06-10T09:00:00", newYork)),
                identified(1, at("2026-06-09T09:00:00", newYork)),
                identified(2, at("2026-06-08T09:00:00", newYork)),
            ),
            nowMillis = at("2026-06-10T23:30:00", newYork),
            zone = newYork,
            locale = Locale.ENGLISH,
        )

        assertEquals("Today", sections[0].relativeWord)
        assertEquals("10 June", sections[0].dateLabel)
        assertEquals("Today · 10 June", sections[0].header)

        assertEquals("Yesterday", sections[1].relativeWord)
        assertEquals("Yesterday · 9 June", sections[1].header)

        // The design never depicts an older day, so it renders the date fragment ALONE — no invented
        // relative word, no bare-date-for-today inconsistency.
        assertNull(sections[2].relativeWord)
        assertEquals("8 June", sections[2].dateLabel)
        assertEquals("8 June", sections[2].header)
    }

    @Test
    fun relativeWordsResolveAgainstTheInjectedNow_notTheWallClock() {
        // `now` is deliberately years away from any plausible wall clock: a grouper reading
        // System.currentTimeMillis() would label NOTHING here Today/Yesterday.
        val sections = DiagnosticsDayGrouper.sections(
            listOf(
                identified(0, at("2001-02-03T09:00:00", newYork)),
                identified(1, at("2001-02-02T09:00:00", newYork)),
            ),
            nowMillis = at("2001-02-03T18:00:00", newYork),
            zone = newYork,
            locale = Locale.ENGLISH,
        )
        assertEquals(listOf("Today · 3 February", "Yesterday · 2 February"), sections.map { it.header })
    }

    @Test
    fun anEntryAheadOfNowSortsFirstAndGetsNoRelativeWord() {
        // Clock skew between logd's stamp and `now` is real; a future day must not be mislabelled.
        val sections = DiagnosticsDayGrouper.sections(
            listOf(
                identified(0, at("2026-06-10T09:00:00", newYork)),
                identified(1, at("2026-06-11T09:00:00", newYork)),
            ),
            nowMillis = at("2026-06-10T20:00:00", newYork),
            zone = newYork,
            locale = Locale.ENGLISH,
        )
        assertEquals(listOf("11 June", "Today · 10 June"), sections.map { it.header })
        assertNull(sections[0].relativeWord)
    }

    // ── boundaries: midnight, DST, zone ─────────────────────────────────────────────────────────

    @Test
    fun oneMillisecondAcrossLocalMidnightSplitsIntoTwoSections() {
        val lastMillisOfTheNinth = at("2026-06-09T23:59:59", newYork) + 999
        val firstMillisOfTheTenth = at("2026-06-10T00:00:00", newYork)
        assertEquals(1L, firstMillisOfTheTenth - lastMillisOfTheNinth)

        val sections = DiagnosticsDayGrouper.sections(
            listOf(identified(0, lastMillisOfTheNinth), identified(1, firstMillisOfTheTenth)),
            nowMillis = at("2026-06-10T12:00:00", newYork),
            zone = newYork,
            locale = Locale.ENGLISH,
        )

        assertEquals(listOf("Today · 10 June", "Yesterday · 9 June"), sections.map { it.header })
        assertEquals(listOf(1), sections[0].entries.map { it.id })
        assertEquals(listOf(0), sections[1].entries.map { it.id })
    }

    @Test
    fun yesterdayIsTheLocalCalendarDay_notNowMinus24Hours() {
        // US DST springs forward 2026-03-08 02:00 EST -> 03:00 EDT, so 2026-03-08 is a 23-HOUR day.
        // With `now` at 00:30 on the 9th, "now - 86_400_000 ms" lands at 23:30 on the SEVENTH
        // (EST), which would label the 8th as an older day and the 7th as "Yesterday" — both wrong.
        val now = at("2026-03-09T00:30:00", newYork)
        val sections = DiagnosticsDayGrouper.sections(
            listOf(
                identified(0, at("2026-03-09T00:10:00", newYork)),
                identified(1, at("2026-03-08T12:00:00", newYork)),
                identified(2, at("2026-03-07T23:00:00", newYork)),
            ),
            nowMillis = now,
            zone = newYork,
            locale = Locale.ENGLISH,
        )

        assertEquals(listOf("Today · 9 March", "Yesterday · 8 March", "7 March"), sections.map { it.header })
    }

    @Test
    fun theSkippedHourDoesNotCollapseTheTransitionDayIntoItsNeighbour() {
        // Instants either side of the 02:00->03:00 gap are the SAME local calendar day.
        val beforeGap = at("2026-03-08T01:59:00", newYork)
        val afterGap = at("2026-03-08T03:01:00", newYork)
        val sections = DiagnosticsDayGrouper.sections(
            listOf(identified(0, beforeGap), identified(1, afterGap)),
            nowMillis = at("2026-03-08T20:00:00", newYork),
            zone = newYork,
            locale = Locale.ENGLISH,
        )
        assertEquals(listOf("Today · 8 March"), sections.map { it.header })
        assertEquals(listOf(1, 0), sections.single().entries.map { it.id })
    }

    @Test
    fun theSameInstantsRegroupWhenTheZoneChanges() {
        // 2026-06-10T22:00 New York == 2026-06-11T10:00 Shanghai: one local day apart.
        val evening = at("2026-06-10T22:00:00", newYork)
        val nextMorning = at("2026-06-11T09:00:00", newYork)

        val now = at("2026-06-11T13:00:00", newYork)

        val ny = DiagnosticsDayGrouper.sections(
            listOf(identified(0, evening), identified(1, nextMorning)),
            nowMillis = now, zone = newYork, locale = Locale.ENGLISH,
        )
        assertEquals(listOf("Today · 11 June", "Yesterday · 10 June"), ny.map { it.header })

        val sh = DiagnosticsDayGrouper.sections(
            listOf(identified(0, evening), identified(1, nextMorning)),
            nowMillis = now, zone = shanghai, locale = Locale.ENGLISH,
        )
        // Both instants fall on 11 June in Shanghai (22:00 New York == 10:00 next-day Shanghai) and
        // `now` is already 12 June there — ONE section, and it is "Yesterday", not "Today".
        assertEquals(listOf("Yesterday · 11 June"), sh.map { it.header })
        assertEquals(listOf(1, 0), sh.single().entries.map { it.id })
    }

    // ── locale ──────────────────────────────────────────────────────────────────────────────────

    @Test
    fun aNonGregorianLocaleLocalisesTheMonth_andLeavesGroupingAndRelativeWordsIntact() {
        val thaiBuddhist = Locale.forLanguageTag("th-TH-u-ca-buddhist")
        val sections = DiagnosticsDayGrouper.sections(
            listOf(
                identified(0, at("2026-06-10T09:00:00", newYork)),
                identified(1, at("2026-06-09T09:00:00", newYork)),
                identified(2, at("2026-06-08T09:00:00", newYork)),
            ),
            nowMillis = at("2026-06-10T20:00:00", newYork),
            zone = newYork,
            locale = thaiBuddhist,
        )

        // Grouping and ordering are calendar-day facts, unaffected by the locale.
        assertEquals(3, sections.size)
        assertEquals(listOf(listOf(0), listOf(1), listOf(2)), sections.map { s -> s.entries.map { it.id } })
        // "Today"/"Yesterday" are design literals (`vreader-diagnostics.jsx:308`), not localised —
        // this app ships a single `res/values` and no translations.
        assertEquals(listOf("Today", "Yesterday", null), sections.map { it.relativeWord })
        // The MONTH is localised, which is the whole point of threading the locale through.
        assertEquals("10 มิถุนายน", sections[0].dateLabel)
        assertEquals("Today · 10 มิถุนายน", sections[0].header)
        assertEquals("8 มิถุนายน", sections[2].header)
    }

    @Test
    fun sectionIdsAreDistinctPerDayAndStableAcrossCalls() {
        val entries = listOf(
            identified(0, at("2026-06-10T09:00:00", newYork)),
            identified(1, at("2026-06-09T09:00:00", newYork)),
        )
        val now = at("2026-06-10T20:00:00", newYork)

        val first = DiagnosticsDayGrouper.sections(entries, now, newYork, Locale.ENGLISH)
        val second = DiagnosticsDayGrouper.sections(entries, now, newYork, Locale.ENGLISH)

        assertEquals(first.map { it.id }, second.map { it.id })
        assertEquals(2, first.map { it.id }.toSet().size)
        assertTrue(first.all { it.id.isNotEmpty() })
    }
}
