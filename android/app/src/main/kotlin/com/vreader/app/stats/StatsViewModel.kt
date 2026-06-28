// Purpose: feature #122 WI-2 (#110 Phase 3) — drives the stats dashboard (window-switchable) + exposes
// the in-reader session-time + a suspend helper for the time-detail card. Over the repository + tracker.
package com.vreader.app.stats

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

@OptIn(ExperimentalCoroutinesApi::class)
class StatsViewModel(
    private val repo: ReadingStatsRepository,
    private val tracker: ReadingTimeTracker,
) : ViewModel() {

    private val _window = MutableStateFlow(StatsWindow.d30)

    val dashboard: StateFlow<DashboardUiState> =
        _window.flatMapLatest { w -> repo.dashboard(w).map { DashboardUiState(w, it, loading = false) } }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DashboardUiState())

    /** The live in-reader session-time (seconds), from the tracker. */
    val sessionSeconds: StateFlow<Long> = tracker.sessionSeconds

    fun selectWindow(window: StatsWindow) { _window.value = window }

    /**
     * The time-detail card numbers for [bookKey] at reading [fraction] (0..1). The total reading-time
     * estimate is the book's word count ÷ a fixed pace; "time left" scales by the remaining fraction.
     */
    suspend fun inReaderStats(bookKey: String, fraction: Float, wordCount: Int): InReaderStats {
        val total = bookTotalMinutesSafe(bookKey)
        val estTotalMin = if (wordCount > 0) (wordCount.toFloat() / WORDS_PER_MINUTE).toInt() else 0
        val left = (estTotalMin * (1f - fraction).coerceIn(0f, 1f)).toInt()
        return InReaderStats(
            sessionSeconds = sessionSeconds.value,
            bookTotalMinutes = total,
            timeLeftMinutes = left,
            pace = if (wordCount > 0) WORDS_PER_MINUTE else null,
        )
    }

    private suspend fun bookTotalMinutesSafe(bookKey: String): Int =
        runCatching { repo.bookTotalMinutes(bookKey) }.getOrDefault(0)

    private companion object { const val WORDS_PER_MINUTE = 230 }
}
