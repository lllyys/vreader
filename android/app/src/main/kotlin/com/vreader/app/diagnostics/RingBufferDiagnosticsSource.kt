package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-3 — the in-process capture floor and [VLog]'s sink.
 *
 * Two jobs, both load-bearing:
 * - **Floor.** If the platform ever refuses an app its own logcat (an SELinux/OEM policy this
 *   project cannot control — plan §2), this buffer is the entire feature. It therefore has no
 *   dependency on any OS boundary and cannot report `Unavailable`.
 * - **Fidelity.** logd truncates a payload at 4068 bytes; this buffer does not. When the composite
 *   sees the same entry from both sources it keeps THIS copy.
 *
 * Key decisions:
 * - **Bounded by construction.** `record` is called from arbitrary app threads for the process's
 *   whole life, so an unbounded collection is a leak with a slow fuse. A non-positive capacity is
 *   REJECTED rather than clamped: a zero-capacity ring would silently drop every entry, which is
 *   the same class of silent degradation the explicit `SourceResult.Unavailable` signal exists to
 *   prevent elsewhere.
 * - **One monitor, snapshot-then-filter.** Readers copy under the lock and do all filtering
 *   outside it, so a read can never observe a partially-applied eviction and a slow reader never
 *   blocks a logging call for longer than the copy.
 * - **`limit` selects the NEWEST entries but the result stays oldest -> newest** — the viewer
 *   renders chronologically while wanting the tail of the log, and reversing at the boundary would
 *   push that subtlety onto every caller.
 *
 * @coordinates-with VLog.kt, CompositeDiagnosticsSource.kt, DiagnosticsLogSource.kt
 */
class RingBufferDiagnosticsSource(private val capacity: Int = DEFAULT_CAPACITY) : DiagnosticsLogSource {

    init {
        require(capacity > 0) { "capacity must be > 0, was $capacity" }
    }

    private val lock = Any()

    /** Guarded by [lock]. Head = oldest. */
    private val entries = ArrayDeque<DiagnosticsLogEntry>()

    /**
     * Append one entry, evicting the oldest when full.
     *
     * [sequenceId] is the identity the composite dedupes on; `null` means the caller is not
     * [VLog] and the entry can only ever be matched by being kept.
     */
    fun record(
        level: DiagnosticsLevel,
        category: String,
        message: String,
        at: Long,
        sequenceId: Long? = null,
    ) {
        val entry = DiagnosticsLogEntry(at, level, category, message, sequenceId)
        synchronized(lock) {
            entries.addLast(entry)
            while (entries.size > capacity) entries.removeFirst()
        }
    }

    /** Drop everything captured so far. */
    fun clear() {
        synchronized(lock) { entries.clear() }
    }

    override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult {
        if (limit <= 0) return SourceResult.Available(emptyList())

        val snapshot = synchronized(lock) { entries.toList() }
        val filtered = if (sinceMillis == null) snapshot else snapshot.filter { it.timeMillis >= sinceMillis }
        // coerce first: `takeLast(Int.MAX_VALUE)` would try to size a list to Int.MAX_VALUE.
        return SourceResult.Available(filtered.takeLast(limit.coerceAtMost(filtered.size)))
    }

    companion object {
        /** Plan §11 limitation 4 — the in-process capture window. */
        const val DEFAULT_CAPACITY: Int = 500
    }
}
