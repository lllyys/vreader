package com.vreader.app.diagnostics

import kotlinx.coroutines.CancellationException
import java.time.Instant

/**
 * Purpose: Feature #164 WI-4 — the UI-facing diagnostics store (the iOS `DiagnosticsLogStore`
 * analog). It loads bounded batches through an injected [DiagnosticsLogSource], reports the raw
 * category vocabulary present in a batch, and renders the REDACTED export payload.
 *
 * Key decisions:
 * - **Stateless except for availability.** iOS's store is `@MainActor @Observable` and owns the
 *   entry array; on Android that state belongs to WI-5's `DiagnosticsViewModel` (`StateFlow`, rule
 *   50 §12). [load] therefore RETURNS its batch and the store keeps exactly one piece of state:
 *   [lastLoadDegraded]. `@Volatile` gives the ViewModel a safe read after the suspending load
 *   resumes on another thread.
 * - **`Available(emptyList())` is NOT degraded.** The whole point of [SourceResult] is that a
 *   readable-but-quiet log and a dead capture stack are different facts; conflating them would make
 *   the export accuse the platform every time a session was simply uneventful.
 * - **The clamp floors at zero** — `max(0, min(limit, maxEntries))`. A negative `limit` must not
 *   reach the source (or `takeLast`); this is the iOS Gate-4 finding ported.
 * - **The store enforces its own bound**, `takeLast(cap)`, rather than trusting a source to honour
 *   `limit`. The source is an injectable seam, so "the viewer asked for N" is the store's promise
 *   to keep, and `cap <= maxEntries` makes this subsume the `maxEntries` window trim.
 * - **No exception escapes** except [CancellationException]: a source failure is data (a degraded
 *   load), but cancelling the caller is not a source failure and must not be swallowed — and must
 *   not fabricate an availability verdict either.
 * - **Every message goes through [DiagnosticsRedactor]** on the way out. On Android that is the
 *   ONLY egress barrier (logcat is plaintext), so it is applied per entry with no fast path.
 * - **Continuation lines are indented.** A multi-line message (a stack trace) would otherwise be
 *   indistinguishable from the next entry — including a message whose own text mimics an entry
 *   header. Indentation makes "starts at column 0" the entry-line predicate for any reader.
 *
 * Known limitations (accepted, NOT mitigated — do not read these as guarantees):
 * - **[lastLoadDegraded] is a FLAT signal.** The store sees only the composite [SourceResult],
 *   which carries no per-source provenance, so it cannot distinguish "logcat died but the ring
 *   buffer answered" from "everything answered". The flag means exactly "the last load's source
 *   reported `Unavailable`". [CAPTURE_SOURCE_FULL] / [CAPTURE_SOURCE_DEGRADED] are therefore the
 *   plan's two COARSE labels for that one bit, not observed per-source provenance: a composite
 *   `Available` may in truth have been breadcrumbs-only. Reporting partial degradation needs
 *   provenance on `SourceResult` — a `DiagnosticsLogSource` change, outside this WI's write-set.
 * - **Loads are expected to be SINGLE-FLIGHT.** [lastLoadDegraded] is `@Volatile`, so there is no
 *   torn read, but it is a store-wide latch rather than a property of one returned batch: if two
 *   loads overlap, the later one's verdict wins and the earlier caller would read it. WI-5's
 *   ViewModel serialises loads (one `flatMapLatest`-driven refresh at a time), which is the
 *   precondition this store is written against; the last-writer-wins behaviour is pinned by test
 *   rather than left accidental. Binding the verdict to the batch would mean returning a compound
 *   result, which is not the API the plan specifies for WI-5 to consume.
 *
 * @coordinates-with DiagnosticsLogSource.kt, DiagnosticsRedactor.kt, DiagnosticsLogEntry.kt,
 *   DiagnosticsCategoryBounding.kt
 */
class DiagnosticsLogStore(
    private val source: DiagnosticsLogSource,
    maxEntries: Int = DEFAULT_MAX_ENTRIES,
) {

    /** At least one — a zero/negative window would make every load return nothing. */
    private val maxEntries: Int = maxEntries.coerceAtLeast(1)

    @Volatile
    private var degraded: Boolean = false

    /**
     * True when the LAST completed load's source reported [SourceResult.Unavailable] — i.e. capture
     * itself failed, as opposed to a readable log that happened to be empty. Feeds the export
     * header's `capture source:` line (section 6.5 of the plan). `false` before the first load and
     * after any successful one; a cancelled load leaves it untouched.
     */
    val lastLoadDegraded: Boolean get() = degraded

    /**
     * Up to `max(0, min(limit, maxEntries))` entries, oldest -> newest, optionally bounded to
     * entries at or after [sinceMillis]. Returns an empty list — never throws — when the source is
     * unavailable, and records that in [lastLoadDegraded].
     */
    suspend fun load(sinceMillis: Long? = null, limit: Int? = null): List<DiagnosticsLogEntry> {
        val cap = (limit ?: maxEntries).coerceAtMost(maxEntries).coerceAtLeast(0)
        val result = try {
            source.recentEntries(sinceMillis, cap)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            // Defence in depth only: the source CONTRACT already says an operational failure
            // arrives as `Unavailable`. `Exception`, never `Throwable` — an `Error` (OOM,
            // LinkageError) is not a source failure and must not be laundered into "degraded".
            null
        }
        val available = result as? SourceResult.Available
        degraded = available == null
        return available?.entries?.takeLast(cap) ?: emptyList()
    }

    /**
     * The distinct non-empty RAW categories present in [entries], sorted.
     *
     * This is deliberately NOT the chip row. `DiagnosticsCategoryBounding.chips` maps, collapses and
     * caps this set onto the designed seven; keeping the raw set separate is what lets a filter
     * still reach an entry whose framework tag collapsed into the bucket.
     */
    fun categories(entries: List<DiagnosticsLogEntry>): List<String> =
        entries.map { it.category }.filter { it.isNotEmpty() }.distinct().sorted()

    /**
     * The redacted, shareable plain-text payload for [entries], stamped with [generatedAt] (epoch
     * millis). The caller passes its own already-filtered list so a multi-level filter (the design's
     * "Errors" chip is a level SET) exports exactly what is on screen.
     *
     * Shape: [HEADER_LINE_COUNT] header lines, then one line per entry —
     * `<ISO-8601 UTC> [LEVEL] (category) <redacted message>` — with any further message lines
     * indented by [CONTINUATION_INDENT].
     */
    fun exportText(entries: List<DiagnosticsLogEntry>, generatedAt: Long): String {
        val noun = if (entries.size == 1) "entry" else "entries"
        val out = StringBuilder()
        out.append("vreader diagnostics — ${entries.size} $noun ($CAPTURE_SCOPE_LABEL)")
        out.append('\n').append("generated: ").append(isoUtc(generatedAt))
        out.append('\n').append("capture source: ")
            .append(if (lastLoadDegraded) CAPTURE_SOURCE_DEGRADED else CAPTURE_SOURCE_FULL)
        for (entry in entries) {
            val category = if (entry.category.isEmpty()) "" else " (${entry.category})"
            val prefix = "${isoUtc(entry.timeMillis)} [${entry.level.exportTag}]$category"
            val lines = DiagnosticsRedactor.redact(entry.message).split(LINE_BREAK)
            val head = lines.first()
            out.append('\n').append(if (head.isEmpty()) prefix else "$prefix $head")
            for (index in 1 until lines.size) {
                out.append('\n').append(CONTINUATION_INDENT).append(lines[index])
            }
        }
        return out.toString()
    }

    private fun isoUtc(epochMillis: Long): String = Instant.ofEpochMilli(epochMillis).toString()

    companion object {
        /**
         * The single source of truth for the human capture-window label, used by BOTH the export
         * header and (WI-5) the viewer footer so they can never diverge.
         *
         * A deliberate divergence from iOS's `"this session"`: `OSLogStore(scope:
         * .currentProcessIdentifier)` really is one launch, whereas logd retains entries by uid
         * ACROSS process launches until the buffer rotates — so Android can show pre-crash entries
         * from a previous launch. Neither `"this session"` (too narrow) nor the design mock's
         * illustrative `"last 24 h"` (a fixed window we do not control) is accurate.
         */
        const val CAPTURE_SCOPE_LABEL: String = "recent activity"

        /**
         * `capture source:` value when the last load's source answered. A COARSE label: it does
         * not prove logcat specifically was readable — see the class doc's flat-signal limitation.
         */
        const val CAPTURE_SOURCE_FULL: String = "logcat + breadcrumbs"

        /** `capture source:` value when the last load's source reported unavailable (section 6.5). */
        const val CAPTURE_SOURCE_DEGRADED: String = "breadcrumbs only (platform log unavailable)"

        /** What every continuation line of a multi-line message is prefixed with. */
        const val CONTINUATION_INDENT: String = "    "

        /** Header lines an export always carries, even for an empty batch. */
        const val HEADER_LINE_COUNT: Int = 3

        /** The default held window, matching the iOS store. */
        const val DEFAULT_MAX_ENTRIES: Int = 2_000

        /** CRLF, bare CR and LF all split a message into export lines. */
        private val LINE_BREAK = Regex("\r\n|\r|\n")
    }
}
