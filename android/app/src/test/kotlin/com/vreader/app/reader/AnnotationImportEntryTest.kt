package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationImportFailedException
import com.vreader.app.annotations.AnnotationImportSheetState
import com.vreader.app.annotations.ImportFailure
import com.vreader.app.annotations.ImportParseResult
import com.vreader.app.annotations.ImportPreview
import com.vreader.app.annotations.ImportPreviewRow
import com.vreader.app.annotations.KindCounts
import com.vreader.app.annotations.RestoreAnnotationsReport
import com.vreader.app.imports.IncomingBookResolver
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupSchema
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/**
 * Feature #165 WI-7 — the PURE half of the reader hosts' annotation-import entry: the three
 * decisions the SAF launcher callback makes before anything is drawn.
 *
 * These are the parts of the launcher wiring that can be pinned without an Activity, and they are
 * where the wiring can be wrong in a way a render test would not notice:
 *
 *  1. **The picked document's name reaches a pixel only after section 8.4 sanitization.** The
 *     controller sanitizes the provider's `DISPLAY_NAME` for the *readable* case, but a FILE-LEVEL
 *     refusal never gets that far — `ImportParseResult.Failed` carries no name, and the designed
 *     sheet's file header sits OUTSIDE the error branch
 *     (`vreader-annotation-import.jsx:449-475`), so a refused file still names itself. The only
 *     name available then is the picked `Uri`'s own last path segment, which is every bit as
 *     provider-controlled as `DISPLAY_NAME`. Passing it through raw would reopen section 8.4 on a
 *     path section 8.4 never covered. The tests below are the mutation guard: hand the raw segment
 *     through and the traversal / control-character / bidi / length / null cases all go RED.
 *  2. **A readable preview is handed on by IDENTITY.** "The number the user approves is the number
 *     they get" (section 6.4, D-11) is an object-identity property — the sheet must show, and
 *     `onConfirm` must return, the very `ImportPreview` the reader produced, never a
 *     reconstruction.
 *  3. **An apply-time failure re-renders the SAME designed error branch** (section 3.2), with its
 *     typed reason preserved — a mapping that flattened every apply failure to one reason would
 *     still "show an error" and would still pass a render test.
 *
 * Hostile characters are built with `Char` arithmetic rather than written as literals or as
 * `\ uXXXX` escapes: a literal RLO reverses the reading order of the source line for every human
 * reviewer, a literal NUL is invisible, and this lane's own tooling has twice emitted a raw NUL
 * where a space was intended.
 */
class AnnotationImportEntryTest {

    private companion object {
        val NUL = 0.toChar()
        val SOH = 1.toChar()
        val DEL = 0x7F.toChar()
        val RLO = 0x202E.toChar()   // RIGHT-TO-LEFT OVERRIDE
        val RLM = 0x200F.toChar()   // RIGHT-TO-LEFT MARK
    }

    private fun emptyReport() = RestoreAnnotationsReport(
        highlights = KindCounts(0, 0, 0),
        notes = KindCounts(0, 0, 0),
        bookmarks = KindCounts(0, 0, 0),
    )

    private fun preview(
        fileName: String = "annotations.json",
        highlights: Int = 3,
        notes: Int = 1,
        bookmarks: Int = 0,
        skipped: Int = 2,
    ) = ImportPreview(
        fileName = fileName,
        bookKey = "epub:${"a".repeat(64)}:1258291",
        bookTitle = "Pride and Prejudice",
        highlights = highlights,
        notes = notes,
        bookmarks = bookmarks,
        skipped = skipped,
        sample = listOf(ImportPreviewRow(colorKey = "yellow", text = "it is a truth")),
        envelope = BackupAnnotationsEnvelope(
            schemaVersion = BackupSchema.CURRENT_SCHEMA_VERSION,
            highlights = emptyList(),
            bookmarks = emptyList(),
            notes = emptyList(),
        ),
    )

    // ---- 1. the picked Uri's last path segment is provider-controlled text (section 8.4) -------

    @Test
    fun pickerFileName_stripsPathTraversal_toTheLeafOnly() {
        // The exact section 8.4 case: a provider is free to answer with a path. Only the leaf shows.
        assertEquals("passwd", importPickerFileName("../../etc/passwd"))
        // A SAF document id routinely arrives as `<root>:<relative/path>` — the leaf is the file.
        assertEquals("notes.json", importPickerFileName("primary:Download/notes.json"))
    }

    @Test
    fun pickerFileName_stripsControlCharactersAndBidiOverrides() {
        val hostile = "a" + NUL + "b\nc\td" + RLO + "e" + RLM + "f" + DEL
        val cleaned = importPickerFileName(hostile)
        assertFalse(
            "control characters must not survive (was ${cleaned.map { it.code }})",
            cleaned.any { it.code < 0x20 || it.code == 0x7F },
        )
        assertFalse("RLO must not survive", cleaned.contains(RLO))
        assertFalse("RLM must not survive", cleaned.contains(RLM))
        // Still a usable name — stripping must not degenerate to the fallback for a real name.
        assertTrue("the printable letters survive", cleaned.contains("a") && cleaned.contains("f"))
    }

    @Test
    fun pickerFileName_capsLength() {
        val cleaned = importPickerFileName("x".repeat(50_000))
        assertTrue(
            "a 50 000-char provider name must be capped at MAX_NAME_CHARS (was ${cleaned.length})",
            cleaned.length <= IncomingBookResolver.MAX_NAME_CHARS,
        )
    }

    @Test
    fun pickerFileName_nullOrBlankOrFullyStripped_fallsBack() {
        assertEquals(IncomingBookResolver.FALLBACK_NAME, importPickerFileName(null))
        assertEquals(IncomingBookResolver.FALLBACK_NAME, importPickerFileName(""))
        assertEquals(IncomingBookResolver.FALLBACK_NAME, importPickerFileName("   "))
        assertEquals(IncomingBookResolver.FALLBACK_NAME, importPickerFileName("" + NUL + SOH))
    }

    @Test
    fun pickerFileName_preservesCjkAndTheExtension() {
        assertEquals("黑暗血时代.json", importPickerFileName("黑暗血时代.json"))
    }

    // ---- 2. a readable preview travels by identity, not by reconstruction ----------------------

    @Test
    fun okResult_becomesReady_carryingTheSamePreviewInstance() {
        val produced = preview()
        val state = importSheetStateFor(ImportParseResult.Ok(produced), fallbackName = "picked.json")
        val ready = state as AnnotationImportSheetState.Ready
        assertSame(
            "the sheet must show the reader's own ImportPreview — a copy could disagree with apply",
            produced, ready.preview,
        )
        // The header name comes from the SANITIZED preview, not from the Uri fallback.
        assertEquals("annotations.json", state.fileName)
        assertEquals(4, ready.preview.importable)
    }

    @Test
    fun zeroImportableOk_isStillReady_notAFailure() {
        // C-8: nothing importable is a DISABLED primary on the designed sheet, never the error blob.
        val state = importSheetStateFor(
            ImportParseResult.Ok(preview(highlights = 0, notes = 0, bookmarks = 0, skipped = 9)),
            fallbackName = "picked.json",
        )
        assertTrue(state is AnnotationImportSheetState.Ready)
        assertEquals(0, (state as AnnotationImportSheetState.Ready).preview.importable)
    }

    @Test
    fun failedResult_becomesFailed_withTheReasonAndTheFallbackName() {
        for (reason in ImportFailure.values()) {
            val state = importSheetStateFor(ImportParseResult.Failed(reason), fallbackName = "picked.json")
            val failed = state as AnnotationImportSheetState.Failed
            assertEquals("the typed reason must survive to the designed blob", reason, failed.reason)
            assertEquals("a refused file still names itself", "picked.json", failed.fileName)
        }
    }

    // ---- 3. an apply-time failure re-renders the same designed error branch (section 3.2) ------

    @Test
    fun applyFailure_keepsTheTypedReason() {
        val state = importApplyFailureState(
            AnnotationImportFailedException(ImportFailure.BookMissing),
            fileName = "annotations.json",
        )
        assertEquals(ImportFailure.BookMissing, state.reason)
        assertEquals("annotations.json", state.fileName)
    }

    @Test
    fun applyFailure_ofAnUntypedThrowable_reportsUnreadable_notASilentSuccess() {
        val state = importApplyFailureState(IOException("db went away"), fileName = "annotations.json")
        assertEquals(ImportFailure.Unreadable, state.reason)
    }

    // ---- 4. the merge runs on the scope it was handed, not on the caller's ---------------------

    @Test
    fun applyRunsToCompletion_onTheHandedScope_afterTheCallersScopeIsCancelled() = runBlocking {
        // The Gate-4 round-1 High, as a seam test: once the user has tapped `Import N items` the
        // merge must not be killed by the composition going away. `AnnotationsImportApplier`
        // rethrows `CancellationException`, so a cancelled apply rolls its transaction back and
        // NOTHING lands — with no surface to say so.
        val durable = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val composition = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val settled = CompletableDeferred<AnnotationImportSheetState?>()
        try {
            launchAnnotationImportApply(
                scope = durable,
                preview = preview(),
                apply = {
                    started.complete(Unit)
                    release.await()
                    Result.success(emptyReport())
                },
                onSettled = { settled.complete(it) },
            )
            withTimeout(5_000) { started.await() }
            // The composition dies mid-merge — a rotation, a back press, a finish().
            composition.cancel()
            release.complete(Unit)
            val next = withTimeout(5_000) { settled.await() }
            assertNull("a successful merge dismisses the sheet", next)
        } finally {
            durable.cancel()
            composition.cancel()
        }
    }

    @Test
    fun applyOnTheHandedScope_mapsAFailureToTheDesignedErrorBranch() = runBlocking {
        val durable = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val settled = CompletableDeferred<AnnotationImportSheetState?>()
        try {
            launchAnnotationImportApply(
                scope = durable,
                preview = preview(fileName = "picked.json"),
                apply = { Result.failure(AnnotationImportFailedException(ImportFailure.BookMissing)) },
                onSettled = { settled.complete(it) },
            )
            val next = withTimeout(5_000) { settled.await() }
            val failed = next as AnnotationImportSheetState.Failed
            assertEquals(ImportFailure.BookMissing, failed.reason)
            assertEquals("picked.json", failed.fileName)
        } finally {
            durable.cancel()
        }
    }

    @Test
    fun applyNeverStartsOnACancelledScope_soAStaleEntryCannotWriteHalfAMerge() = runBlocking {
        // The other half of the contract: handing a DEAD scope must not run the merge at all
        // (rather than run it and drop the result), so a caller that wires the wrong scope fails
        // loudly in this test instead of silently in production.
        val dead = CoroutineScope(SupervisorJob() + Dispatchers.Default).also { it.cancel() }
        var applied = false
        val job = launchAnnotationImportApply(
            scope = dead,
            preview = preview(),
            apply = { applied = true; Result.success(emptyReport()) },
            onSettled = {},
        )
        job.join()
        assertFalse("a cancelled scope must not run the merge", applied)
    }

    // ---- 5. one pick at a time: a late answer may not write over a newer one -------------------

    @Test
    fun session_aLateAnswerFromAnAbandonedPick_isNotCurrent() {
        // Pick A, its preview parks, the user picks B. Whichever parse returns LAST would otherwise
        // win, and the sheet would show A's counts for B's file.
        val session = AnnotationImportSession()
        val a = session.begin()
        val b = session.begin()
        assertFalse("A's late parse must not write the sheet", session.isCurrent(a))
        assertTrue("B owns the sheet", session.isCurrent(b))
    }

    @Test
    fun session_dismissAlsoTakesAToken_soAClosedSheetIsNotResurrected() {
        val session = AnnotationImportSession()
        val pick = session.begin()
        session.begin()   // the Cancel / swipe / scrim path
        assertFalse("a dismissed sheet must not be reopened by a parse that returns later", session.isCurrent(pick))
    }

    @Test
    fun session_secondConfirmWhileTheFirstMergeRuns_isRefused() {
        val session = AnnotationImportSession()
        session.begin()
        val first = session.tryBeginApply()
        assertEquals(session.current, first)
        assertNull("a double tap on `Import N items` must not queue a second apply", session.tryBeginApply())
    }

    @Test
    fun session_afterAMergeSettles_thePickCanBeConfirmedAgain() {
        val session = AnnotationImportSession()
        session.begin()
        val token = requireNotNull(session.tryBeginApply())
        session.endApply(token)
        assertEquals(
            "once the merge settled the claim is released",
            session.current, session.tryBeginApply(),
        )
    }

    @Test
    fun session_aNewPickReleasesAStuckClaim_andTheOldMergeCannotSettleOverIt() {
        // The user confirms, then dismisses and picks a new file while the first merge is still in
        // flight. The new pick must be confirmable, and the OLD merge's settle must not touch it.
        val session = AnnotationImportSession()
        session.begin()
        val stale = requireNotNull(session.tryBeginApply())
        val fresh = session.begin()
        assertEquals("the new pick can be confirmed", fresh, session.tryBeginApply())
        session.endApply(stale)
        assertTrue("…and the stale settle must not release the new pick's claim", session.isCurrent(fresh))
        assertNull("the new pick's merge is still claimed", session.tryBeginApply())
    }

    @Test
    fun applyFailure_neverEchoesTheThrowableText() {
        // rule 50 section 6 — the user-facing string is fixed; a message that leaked a path or a
        // stack detail would be this feature's first such leak.
        val secret = "/data/user/0/com.vreader.app/databases/vreader.db"
        val state = importApplyFailureState(IOException(secret), fileName = "annotations.json")
        assertFalse(state.reason.userMessage.contains(secret))
        assertFalse(state.reason.userMessage.contains("/data"))
    }
}
