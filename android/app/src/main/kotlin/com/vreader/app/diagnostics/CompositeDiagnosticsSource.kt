package com.vreader.app.diagnostics

import kotlinx.coroutines.CancellationException

/**
 * Purpose: Feature #164 WI-3 — one source over two: the platform log ([primary], normally
 * `LogcatDiagnosticsSource`) and the in-process floor ([secondary], the ring buffer).
 *
 * Key decisions:
 * - **MERGE, never choose.** Whenever the primary is `Available` — including
 *   `Available(emptyList())` — the ring's entries are merged in. The rejected v1 design inferred
 *   availability from emptiness and served "primary else floor", which failed twice over: a
 *   legitimately empty logcat flip-flopped the source on every load, and a *partially* populated
 *   logcat hid the ring's entries entirely.
 * - **Dedupe on IDENTITY, never on text.** The key is [DiagnosticsLogEntry.sequenceId], the id
 *   VLog stamps on both representations of one event. A `(time, level, tag, message)` key would
 *   collapse two genuinely distinct events that share byte-identical text and timestamp — a
 *   realistic shape for a repeated handled condition — and logd's timestamp rewriting and
 *   4068-byte truncation make the "same" event differ between the sources anyway.
 * - **Fail OPEN on retention.** An entry whose `sequenceId` is null (framework/library line, or a
 *   marker lost to truncation) is always kept: dedupe never drops what it cannot positively
 *   identify. A duplicate visible entry is a cosmetic annoyance; a silently dropped one is a lost
 *   bug report.
 * - **The RING copy wins a collision.** Both carry the same text in the normal case, but logd
 *   truncates the tail — so preferring the ring's copy is what keeps the end of a long stack trace.
 * - **No exception escapes** except [CancellationException]: a source failure is data
 *   (`Unavailable`), but cancelling the caller is not a source failure and must not be swallowed.
 *
 * @coordinates-with LogcatDiagnosticsSource.kt, RingBufferDiagnosticsSource.kt, VLog.kt
 */
class CompositeDiagnosticsSource(
    private val primary: DiagnosticsLogSource,
    private val secondary: DiagnosticsLogSource,
) : DiagnosticsLogSource {

    override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult {
        val primaryResult = read(primary, sinceMillis, limit, "primary")
        val secondaryResult = read(secondary, sinceMillis, limit, "secondary")

        val primaryEntries = (primaryResult as? SourceResult.Available)?.entries
        val secondaryEntries = (secondaryResult as? SourceResult.Available)?.entries

        if (primaryEntries == null && secondaryEntries == null) {
            return SourceResult.Unavailable(
                "${(primaryResult as SourceResult.Unavailable).reason}; " +
                    (secondaryResult as SourceResult.Unavailable).reason,
            )
        }
        if (limit <= 0) return SourceResult.Available(emptyList())

        val merged = mergeDeduped(
            preferred = secondaryEntries.orEmpty(),
            other = primaryEntries.orEmpty(),
        )
        return SourceResult.Available(merged.takeLast(limit.coerceAtMost(merged.size)))
    }

    /**
     * [preferred] is emitted first so that a stable sort keeps its copy ahead of an equal-timestamp
     * twin, and so that its copy is the one that claims a colliding sequence id.
     */
    private fun mergeDeduped(
        preferred: List<DiagnosticsLogEntry>,
        other: List<DiagnosticsLogEntry>,
    ): List<DiagnosticsLogEntry> {
        val claimed = HashSet<Long>(preferred.size + other.size)
        val kept = ArrayList<DiagnosticsLogEntry>(preferred.size + other.size)
        for (entry in preferred) {
            val id = entry.sequenceId
            if (id == null || claimed.add(id)) kept += entry
        }
        for (entry in other) {
            val id = entry.sequenceId
            if (id == null || claimed.add(id)) kept += entry
        }
        return kept.sortedBy { it.timeMillis }
    }

    private suspend fun read(
        source: DiagnosticsLogSource,
        sinceMillis: Long?,
        limit: Int,
        label: String,
    ): SourceResult = try {
        source.recentEntries(sinceMillis, limit)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (t: Throwable) {
        SourceResult.Unavailable("$label threw ${t.javaClass.simpleName}: ${t.message}")
    }
}
