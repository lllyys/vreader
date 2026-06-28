// Purpose: feature #122 WI-2 (#110 Phase 3) — UI state for the stats dashboard + the in-reader
// time-detail card. Stateless composables (WI-3) render a pure function of these.
package com.vreader.app.stats

/** The dashboard's state for the selected window. */
data class DashboardUiState(
    val window: StatsWindow = StatsWindow.d30,
    val data: DashboardData = DashboardData(),
    val loading: Boolean = true,
)

/** The in-reader time-detail card numbers (session pill uses [sessionSeconds] alone). */
data class InReaderStats(
    val sessionSeconds: Long = 0,
    val bookTotalMinutes: Int = 0,
    val timeLeftMinutes: Int = 0,
    val pace: Int? = null,        // words per minute estimate, or null when unknown
)
