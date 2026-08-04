package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-1 — the testable seam for diagnostics capture (the iOS
 * `DiagnosticsLogSource` protocol analog). The store depends on this interface;
 * production wires the logcat source plus (WI-3) the in-process ring buffer.
 *
 * Key decision — availability is an EXPLICIT signal, never inferred from emptiness.
 * A source that returns a bare list forces every caller to guess whether `[]` means
 * "nothing was logged" or "this source is dead", and those two need opposite handling:
 * the composite must fall back for the second and must NOT for the first. Hence
 * [SourceResult].
 *
 * @coordinates-with LogcatDiagnosticsSource.kt, DiagnosticsLogEntry.kt
 */
interface DiagnosticsLogSource {
    /**
     * Up to [limit] entries, oldest -> newest, optionally bounded to entries at or after
     * [sinceMillis].
     *
     * NEVER throws to signal a source failure — the reader could not be opened, the platform
     * denied it, it timed out — all of those are reported as [SourceResult.Unavailable].
     * `CancellationException` is the one exception that still propagates, as it must:
     * cancelling the caller is not a source failure and must not be swallowed.
     */
    suspend fun recentEntries(sinceMillis: Long? = null, limit: Int): SourceResult
}

/** The outcome of one read. `Available(emptyList())` and `Unavailable` are DIFFERENT. */
sealed interface SourceResult {
    /** The source was readable. [entries] may legitimately be empty. */
    data class Available(val entries: List<DiagnosticsLogEntry>) : SourceResult

    /** The source could not be read at all. [reason] is diagnostic text, never user copy. */
    data class Unavailable(val reason: String) : SourceResult
}
