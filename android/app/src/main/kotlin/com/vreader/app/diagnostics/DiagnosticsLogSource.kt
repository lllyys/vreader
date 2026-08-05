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
    /**
     * The source was readable. [entries] may legitimately be empty.
     *
     * [degradedReason] carries PROVENANCE for a result that answered but is less complete than it
     * should be: non-null means *"these entries are everything I could get, but the PLATFORM LOG —
     * the primary capture leg — did not answer; here is why"*. It defaults to `null` and a LEAF
     * source always leaves it there: a single source that could be read produced a complete result
     * by definition, and only a compositor knows that something is missing.
     *
     * The contract is deliberately narrowed to the primary leg rather than to "any contributing
     * source", because the only consumer — the export header's two-valued `capture source:` line —
     * has no vocabulary for anything else (plan §6.5; rule 51 fixes the wording). Only
     * [CompositeDiagnosticsSource] sets it, and that class documents the asymmetry and its cost.
     * A `null` reason therefore means "the platform log answered", NOT "every source answered".
     *
     * This is deliberately a nullable reason and not a `primaryUnavailable` flag: "primary" is a
     * compositing concept that a leaf source cannot meaningfully answer, whereas a reason string
     * reuses [Unavailable]'s existing vocabulary, so the codebase carries one concept rather than
     * two. The distinction `Available(emptyList())` vs [Unavailable] is untouched — a healthy,
     * quiet log is still `Available` with a `null` reason.
     */
    data class Available(
        val entries: List<DiagnosticsLogEntry>,
        val degradedReason: String? = null,
    ) : SourceResult

    /** The source could not be read at all. [reason] is diagnostic text, never user copy. */
    data class Unavailable(val reason: String) : SourceResult
}
