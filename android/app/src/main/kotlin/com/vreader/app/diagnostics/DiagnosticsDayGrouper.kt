package com.vreader.app.diagnostics

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Purpose: Feature #164 WI-5 — buckets the viewer's rows into newest-first LOCAL CALENDAR DAY
 * sections with the design's day headers (`DiagLogList`, `vreader-diagnostics.jsx:303-315`). The
 * iOS `DiagnosticsDayGrouper` analog, ported 1:1 in semantics.
 *
 * Key decisions:
 * - **Every temporal input is INJECTED** — `nowMillis`, `zone`, `locale`. Nothing here reads the
 *   ambient clock or `ZoneId.systemDefault()`, so "Today" is reproducible in a test and the whole
 *   grouping can be exercised in another zone without touching JVM-wide state.
 * - **Day arithmetic is done on `LocalDate`, never on millis.** "Yesterday" is
 *   `today.minusDays(1)`, not `now - 86_400_000`: a DST spring-forward day is 23 hours long, so
 *   millis arithmetic mislabels the day after a transition (verified in
 *   `DiagnosticsDayGrouperTest.yesterdayIsTheLocalCalendarDay_notNowMinus24Hours`).
 * - **The design's header carries a date SUFFIX** — `"Today · 10 June"` / `"Yesterday · 9 June"`
 *   (`:308`). An older day renders the `"D Month"` fragment ALONE, because the design never depicts
 *   one and this is the only composition that invents no token: it reuses the same date fragment the
 *   depicted headers already show, minus a relative word that would be false. This is also exactly
 *   what iOS #96 shipped against the same bundle (`DiagnosticsDaySection.header`).
 * - **"Today"/"Yesterday" are design literals, not localised strings.** The app ships a single
 *   `res/values` with no translations; the LOCALE affects the month name only.
 * - **Ties keep their incoming order.** Two entries stamped the same millisecond stay in the order
 *   the caller assigned ids in, so a stable list does not reshuffle between recompositions.
 *
 * @coordinates-with DiagnosticsUiState.kt, DiagnosticsViewModel.kt, DiagnosticsLogEntry.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsDayGrouper {

    /** The design's relative word for the current local day. */
    const val TODAY: String = "Today"

    /** The design's relative word for the previous local day. */
    const val YESTERDAY: String = "Yesterday"

    /** `"10 June"` — the date fragment every designed header ends with. */
    private const val DATE_LABEL_PATTERN = "d MMMM"

    /**
     * [entries] (any order) grouped into newest-day-first sections, newest entry first within each
     * day. [nowMillis] decides which day is [TODAY]/[YESTERDAY]; [zone] decides where a day starts;
     * [locale] names the month.
     */
    fun sections(
        entries: List<IdentifiedDiagnosticsEntry>,
        nowMillis: Long,
        zone: ZoneId,
        locale: Locale = Locale.getDefault(),
    ): List<DiagnosticsDaySection> {
        if (entries.isEmpty()) return emptyList()

        val dateLabelFormatter = DateTimeFormatter.ofPattern(DATE_LABEL_PATTERN, locale)
        val today = localDate(nowMillis, zone)
        val yesterday = today.minusDays(1)

        val buckets = entries.groupBy { localDate(it.entry.timeMillis, zone) }

        return buckets.keys.sortedDescending().map { day ->
            DiagnosticsDaySection(
                id = day.toString(),
                relativeWord = when (day) {
                    today -> TODAY
                    yesterday -> YESTERDAY
                    else -> null
                },
                dateLabel = dateLabelFormatter.format(day),
                // `sortedByDescending` is stable, so same-millisecond entries keep the caller's order.
                entries = buckets.getValue(day).sortedByDescending { it.entry.timeMillis },
            )
        }
    }

    private fun localDate(epochMillis: Long, zone: ZoneId): LocalDate =
        Instant.ofEpochMilli(epochMillis).atZone(zone).toLocalDate()
}

/**
 * One day-bucket of rows for the viewer's grouped list.
 *
 * [relativeWord] is `null` for any day that is neither today nor yesterday, which is what makes
 * [header] fall back to the bare date fragment.
 */
data class DiagnosticsDaySection(
    /** Stable across recomputes — the ISO local date (`"2026-06-10"`). */
    val id: String,
    val relativeWord: String?,
    /** `"10 June"`, in the injected locale. */
    val dateLabel: String,
    /** Rows on this day, newest first, each carrying its positional identity. */
    val entries: List<IdentifiedDiagnosticsEntry>,
) {
    /** The composed design header — `"Today · 10 June"`, or `"8 June"` for an older day. */
    val header: String
        get() = relativeWord?.let { "$it · $dateLabel" } ?: dateLabel
}
