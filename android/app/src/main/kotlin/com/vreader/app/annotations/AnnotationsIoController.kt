// Purpose: feature #165 WI-4b — the BOUNDED SAF I/O boundary of annotation import and export, in
// both directions. Every provider call this feature makes runs through the shipped
// `BoundedCallGate`; nothing else in `annotations/` touches a `ContentResolver`.
//
// Pipeline (import): admission -> bounded metadata query -> size preflight -> bounded open (with a
// mandatory `dispose`) -> bounded read+parse through `CountingGuardStream` -> bounded close.
// Pipeline (export): admission -> bounded open (mandatory `dispose`) -> bounded write -> bounded
// close.
//
// Key decisions:
//  - THE HAZARD IS THE CALL, NOT THE BYTES. `ContentResolver.query` / `openInputStream` /
//    `openOutputStream` and a blocking `read` / `write` / `close` are synchronous and
//    uninterruptible, and they execute inside a provider process an attacker may control. A
//    provider that never returns parks the calling thread forever; `withContext(Dispatchers.IO)`
//    relocates that block without bounding it, and coroutine cancellation cannot interrupt it (the
//    caller unwinds while the thread stays parked). A byte cap on the READ is therefore irrelevant
//    — the code never reaches it. This is the defect #155 spent six Gate-4 rounds closing.
//  - THE GATE IS INJECTED, NEVER CONSTRUCTED. `BoundedCallGate` is a ledger, not a utility: a
//    second instance would carry a second `MAX_ABANDONED_CALLS` budget, i.e. DOUBLE the ceiling on
//    simultaneously parked provider threads — the opposite of the guarantee. Production passes
//    `container.incomingImportCoordinator.boundedCalls`, and the admission check consults
//    `IncomingImportCoordinator.MAX_ABANDONED_CALLS`, so there is exactly one ledger and one
//    ceiling app-wide.
//  - GUARANTEED vs BEST-EFFORT, STATED SEPARATELY (#155's round-3 lesson; conflating them is how
//    the weaker claim gets sold as the stronger one):
//      * GUARANTEED — the caller always proceeds. Every step returns a typed failure at its
//        deadline whether or not the provider call ever finishes, so the UI never wedges.
//      * BEST-EFFORT — releasing the parked thread sooner. NO behaviour depends on it; the
//        ownership rules that make that safe live in `SafCleanup`.
//  - `dispose` IS MANDATORY WHEREVER A LATE RESULT CAN BE A `Closeable` — a stream produced after
//    the deadline has NO other owner, and not closing it is an fd leak on an attacker-triggerable
//    path. Both opens and both transfers carry one.
//  - CLOSE IS BOUNDED TOO — beyond §8.1's five named call sites, deliberately. Closing a SAF
//    descriptor flushes through the same provider; an unbounded `close()` inside the one file
//    whose job is "no unbounded provider call" would be the same defect under a different name.
//    On EXPORT a timed-out or throwing close is a FAILURE, because a save we cannot confirm must
//    not be announced as done; on IMPORT it is ignored, because the bytes were already read and
//    parsed and the close cannot invalidate them.
//  - KNOWN RESIDUAL, INHERITED AND DELIBERATELY NOT PAPERED OVER: admission is a CHECK, not a
//    RESERVATION. `BoundedCallGate` charges the ledger only when a caller gives up, so two
//    concurrent readers can both pass the same check and both start a parkable call — the ceiling
//    is a threshold, not a hard cap. That is a property of the shipped gate (whose own KDoc already
//    records it as a filed follow-up against `IncomingImportCoordinator`), and `imports/` is
//    read-only for this feature. The tempting in-scope "fix" — a controller-side reservation
//    counter — is exactly the SECOND LEDGER §8.5 forbids: two admission budgets would each admit
//    their own quota and double the ceiling they exist to lower. So this stays a named residual for
//    the gate, not a local workaround here.
//  - THE POST-OPEN GUARD IS A BACKSTOP, NOT THE CAP. `CountingGuardStream` is given the reader's
//    cap plus [GUARD_SLACK_BYTES] so the reader's own measured cap always fires first and reports
//    the typed `TooLarge`. At an equal limit the guard would throw inside the reader's read loop,
//    the reader's blanket catch would relabel it `Unreadable`, and the user would be told the
//    wrong thing.
//
// @coordinates-with SafDocumentPort (the unbounded provider seam this bounds), BoundedCallGate +
//   CountingGuardStream + IncomingBookResolver.sanitizeDisplayName (shipped, reused not
//   re-derived), AnnotationsImportReader (the untrusted-bytes boundary), AnnotationsImportApplier,
//   AnnotationsExportWriter.
package com.vreader.app.annotations

import android.content.ContentResolver
import android.net.Uri
import com.vreader.app.imports.BoundedCall
import com.vreader.app.imports.BoundedCallGate
import com.vreader.app.imports.CountingGuardStream
import com.vreader.app.imports.IncomingBookResolver
import com.vreader.app.annotations.SafCleanup.Companion.rethrowIfFatal
import com.vreader.app.annotations.SafCleanup.Companion.swallowingClose
import com.vreader.app.imports.IncomingImportCoordinator
import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import kotlin.coroutines.cancellation.CancellationException

/**
 * Runs annotation import and export against a document provider without ever letting that provider
 * decide how long the app waits.
 *
 * [gate] is the SHIPPED, app-wide `BoundedCallGate` — injected, never constructed here.
 */
class AnnotationsIoController internal constructor(
    private val saf: SafDocumentPort,
    private val writer: AnnotationsExportWriter,
    private val applier: AnnotationsImportApplier,
    private val gate: BoundedCallGate,
    private val timeoutMillis: Long = DEFAULT_IO_TIMEOUT_MILLIS,
    private val parser: AnnotationsParser = AnnotationsParser(AnnotationsImportReader::parse),
    private val cleanup: SafCleanup = SafCleanup.SHARED,
) {

    /** The production wiring: the app's `ContentResolver` behind the default adapter. */
    constructor(
        resolver: ContentResolver,
        writer: AnnotationsExportWriter,
        applier: AnnotationsImportApplier,
        gate: BoundedCallGate,
        timeoutMillis: Long = DEFAULT_IO_TIMEOUT_MILLIS,
    ) : this(ContentResolverSafPort(resolver), writer, applier, gate, timeoutMillis)

    /**
     * Writes [bookKey]'s annotations to the picked destination and returns the row count.
     *
     * Both blocking calls are bounded INDEPENDENTLY: a destination can accept the open promptly and
     * then park mid-`write`. That is the easier attack of the two directions, because the user
     * initiated it — they chose "Export" and are waiting.
     *
     * Failures are typed inside [AnnotationImportFailedException] so a caller can render the
     * designed error blob without string matching.
     */
    suspend fun export(uri: Uri, bookKey: String): Result<Int> {
        // Admission. Unlike the import path there is no second provider step before the fd, so
        // there is nothing to re-check between: this one check covers the whole open.
        if (budgetExhausted()) return refusal(ImportFailure.Busy)

        val sink = when (
            val opened = bounded<OutputStream?>(OPEN_OUTPUT, dispose = { it?.let(::swallowingClose) }) {
                saf.openOutput(uri)
            }
        ) {
            is BoundedCall.Completed -> opened.value ?: return refusal(ImportFailure.Unreadable)
            is BoundedCall.Failed -> {
                rethrowIfFatal(opened.error)
                return refusal(ImportFailure.Unreadable)
            }
            BoundedCall.TimedOut -> return refusal(ImportFailure.Timeout)
        }

        // Re-checked with the descriptor already in hand: a concurrent activity may have spent the
        // shared budget while this one was inside `openOutput`, and the write is the longest
        // parkable step of the two. The sink is closed on the way out — refusing cleanup would
        // trade a bounded wait for a certain fd leak, which is why the CLOSE below is never
        // admission-gated.
        if (budgetExhausted()) {
            closeQuietly(sink)
            return refusal(ImportFailure.Busy)
        }

        val owned = CloseOnce(sink)
        val written = when (
            val call = bounded(
                WRITE,
                // GUARANTEED ownership of a sink whose write is still parked: `dispose` runs on
                // the abandoned job's own thread the moment the write finally returns, so it is
                // the only cleanup that cannot be dropped. `onExpiry` below is the earlier,
                // best-effort attempt and MAY be discarded when the rescue lane is saturated —
                // which is exactly why this exists (Gate-4 round 3, High).
                dispose = { owned.close() },
                onExpiry = { cleanup.releaseAfterExpiry(owned) },
            ) {
                writer.writeTo(sink, bookKey)
            }
        ) {
            is BoundedCall.Completed -> call.value
            // The write threw, so the parked thread is back and the sink is ours to close.
            is BoundedCall.Failed -> {
                rethrowIfFatal(call.error)
                closeQuietly(owned)
                return refusal(ImportFailure.Unreadable)
            }
            // The write is still parked and still owns the sink; the dispose above will close it
            // the moment it returns. Closing from here would be a second close on a stream that
            // need not tolerate one.
            BoundedCall.TimedOut -> return refusal(ImportFailure.Timeout)
        }

        // STRICT, unlike the import side: for a SAF descriptor `close()` is where the write is
        // finalized, so a close that throws means the file was NOT saved and reporting success
        // would tell the user a file exists that does not. Still through [owned], so this and the
        // cleanup paths above can never both reach the underlying stream.
        return when (val closed = bounded(CLOSE) { owned.close() }) {
            is BoundedCall.Completed -> Result.success(written)
            is BoundedCall.Failed -> {
                rethrowIfFatal(closed.error)
                refusal(ImportFailure.Unreadable)
            }
            BoundedCall.TimedOut -> refusal(ImportFailure.Timeout)
        }
    }

    /**
     * Reads the picked document into the preview the user approves (§8.1's five steps).
     *
     * [ImportPreview.fileName] is sanitized HERE, at the boundary, so no later path can reach the
     * provider's raw display name (§8.4).
     */
    suspend fun preview(uri: Uri, bookKey: String, bookTitle: String): ImportParseResult {
        if (budgetExhausted()) return ImportParseResult.Failed(ImportFailure.Busy)

        val metadata = when (val queried = bounded(QUERY) { saf.queryMetadata(uri) }) {
            is BoundedCall.Completed -> queried.value
            is BoundedCall.Failed -> {
                rethrowIfFatal(queried.error)
                return ImportParseResult.Failed(ImportFailure.Unreadable)
            }
            BoundedCall.TimedOut -> return ImportParseResult.Failed(ImportFailure.Timeout)
        }

        // Pre-open preflight: "refuse before opening" only means anything here, where no descriptor
        // exists yet. A declared size is a claim, so this refuses the honest oversize file cheaply;
        // an absent or lying size is caught later by the MEASURED read.
        val declared = metadata.declaredSize
        if (declared != null && declared > AnnotationsImportReader.MAX_IMPORT_JSON_BYTES) {
            return ImportParseResult.Failed(ImportFailure.TooLarge)
        }

        // Re-checked, not just before the query: a concurrent activity may have exhausted the
        // shared budget while this one was inside its cursor call.
        if (budgetExhausted()) return ImportParseResult.Failed(ImportFailure.Busy)

        val fileName = IncomingBookResolver.sanitizeDisplayName(metadata.displayName)

        // Before the open, deliberately: this reads the library's own tables and can take a while,
        // and holding an attacker's fd open across it buys nothing.
        val existing = try {
            applier.existingState(bookKey)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return ImportParseResult.Failed(ImportFailure.Unreadable)
        }

        val stream = when (
            val opened = bounded<InputStream?>(OPEN_INPUT, dispose = { it?.let(::swallowingClose) }) {
                saf.openInput(uri)
            }
        ) {
            is BoundedCall.Completed ->
                opened.value ?: return ImportParseResult.Failed(ImportFailure.Unreadable)
            is BoundedCall.Failed -> {
                rethrowIfFatal(opened.error)
                return ImportParseResult.Failed(ImportFailure.Unreadable)
            }
            BoundedCall.TimedOut -> return ImportParseResult.Failed(ImportFailure.Timeout)
        }

        val guard = CountingGuardStream(
            stream,
            AnnotationsImportReader.MAX_IMPORT_JSON_BYTES + GUARD_SLACK_BYTES,
        )

        // Same re-check as the export path, and for the same reason: the read is the longest
        // parkable step and the budget may have gone while we were inside `openInput`.
        if (budgetExhausted()) {
            closeQuietly(guard)
            return ImportParseResult.Failed(ImportFailure.Busy)
        }

        val parsed = when (
            val read = bounded(
                READ,
                // The import twin of the export write's dispose: guaranteed ownership of a stream
                // whose read is still parked, closed on the abandoned job's own thread when it
                // finally returns. `CountingGuardStream` is itself close-once, so this and the
                // best-effort `onExpiry` cannot double-close the provider's stream.
                dispose = { swallowingClose(guard) },
                onExpiry = { cleanup.releaseAfterExpiry(guard) },
            ) {
                parser.parse(guard, fileName, bookKey, bookTitle, existing)
            }
        ) {
            is BoundedCall.Completed -> read.value
            is BoundedCall.Failed -> {
                rethrowIfFatal(read.error)
                closeQuietly(guard)
                return ImportParseResult.Failed(ImportFailure.Unreadable)
            }
            // Still parked on the read; `onExpiry` already dispatched the best-effort abort.
            BoundedCall.TimedOut -> return ImportParseResult.Failed(ImportFailure.Timeout)
        }

        // QUIET and ignored, unlike the export close: the bytes are already read and parsed, so
        // neither a slow close nor a failing one can change the answer. It is still bounded,
        // because it is still a provider call.
        closeQuietly(guard)
        return parsed
    }

    /** Applies an approved preview. No provider call is involved — this is the library's own store. */
    suspend fun apply(preview: ImportPreview): Result<RestoreAnnotationsReport> = applier.apply(preview)

    // ---- the bounded-call plumbing ---------------------------------------------------------------

    /**
     * The ONE ledger check. Reading the ceiling from `IncomingImportCoordinator` rather than
     * redeclaring it keeps "one budget" true by construction rather than by coincidence.
     */
    private fun budgetExhausted(): Boolean =
        gate.abandonedCalls >= IncomingImportCoordinator.MAX_ABANDONED_CALLS

    private fun <T> refusal(reason: ImportFailure): Result<T> =
        Result.failure(AnnotationImportFailedException(reason))

    private suspend fun <T> bounded(
        name: String,
        dispose: (T) -> Unit = {},
        onExpiry: () -> Unit = {},
        block: suspend () -> T,
    ): BoundedCall<T> = gate.call(timeoutMillis, name, dispose, onExpiry, block)

    /**
     * Close-once, failure-tolerant: an attacker-supplied stream need not tolerate a second `close()`
     * and need not close cleanly.
     *
     * Always goes through the gate: `close()` on a SAF descriptor is a provider call like any
     * other and can park forever, and every caller of this is still waiting for an answer.
     */
    private suspend fun closeQuietly(closeable: Closeable) {
        // The RESULT is inspected even though the outcome is ignored: `swallowingClose` rethrows a
        // process-fatal error, but the gate wraps every Throwable into `Failed`, so dropping the
        // result on the floor would lose exactly the errors that must never be lost (Gate-4
        // round 2, Low).
        val closed = bounded(CLOSE) { swallowingClose(closeable) }
        if (closed is BoundedCall.Failed) rethrowIfFatal(closed.error)
    }

    companion object {
        /** Per bounded call, not per operation (§8.2). */
        const val DEFAULT_IO_TIMEOUT_MILLIS = 10_000L

        /**
         * Headroom so `AnnotationsImportReader`'s own measured cap — which reports the typed
         * `TooLarge` — always fires before the post-open guard, whose exception the reader would
         * relabel `Unreadable`. Larger than the reader's read chunk, and irrelevant to memory: the
         * reader stops accumulating at its own cap.
         */
        internal const val GUARD_SLACK_BYTES = 64L * 1024

        private const val QUERY = "annot-query"
        private const val OPEN_INPUT = "annot-open-input"
        private const val READ = "annot-read"
        private const val OPEN_OUTPUT = "annot-open-output"
        private const val WRITE = "annot-write"
        private const val CLOSE = "annot-close"
    }
}
