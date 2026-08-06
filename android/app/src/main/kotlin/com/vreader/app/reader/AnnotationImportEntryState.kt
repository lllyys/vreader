// Purpose: feature #165 WI-7 — the PURE half of the reader hosts' annotation-import entry: the MIME
// hint, the one-pick-at-a-time session token, the boundary-answer -> sheet-state mappings, and the
// merge launcher. Split out of `AnnotationImportEntry.kt` so the composable file stays about
// COMPOSITION and every decision here is reachable from a JVM test with no Activity
// (`AnnotationImportEntryTest`).
//
// Key decisions:
//  - NOTHING HERE TOUCHES ANDROID. Everything is a value or a `CoroutineScope`, which is what makes
//    the section-8.4 sanitization, the failure taxonomy and the session rules testable at all.
//  - THE SESSION TOKEN IS A UI-CORRECTNESS DEVICE, NOT A DATA ONE. Room's `IGNORE` keeps the store
//    consistent through every interleaving; what the token protects is "the sheet is showing the
//    pick the user made" (Gate-4 round 2, Medium).
//  - THE MERGE LAUNCHER TAKES ITS SCOPE AS A PARAMETER. The whole point of the seam is that the work
//    continues on the scope it was HANDED, whatever happens to the caller's own — which is exactly
//    the property a test has to be able to supply a scope to check (Gate-4 round 1, High).
//
// @coordinates-with AnnotationImportEntry (the composable that uses all of this),
//   AnnotationImportModels (ImportPreview / ImportFailure / ImportParseResult),
//   AnnotationImportPreviewSheet (AnnotationImportSheetState), IncomingBookResolver (the shipped
//   display-name sanitizer this reuses rather than re-derives).
package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationImportFailedException
import com.vreader.app.annotations.AnnotationImportSheetState
import com.vreader.app.annotations.ImportFailure
import com.vreader.app.annotations.ImportParseResult
import com.vreader.app.annotations.ImportPreview
import com.vreader.app.annotations.RestoreAnnotationsReport
import com.vreader.app.imports.IncomingBookResolver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * The MIME hint handed to the system picker.
 *
 * `application/json` first so a well-behaved provider pre-filters, `* / *` alongside it because
 * providers routinely mislabel a `.json` document as `text/plain` or `application/octet-stream` and
 * a strict filter would make a legitimate file unpickable (plan R-7). The declared type is a HINT
 * and never a gate — validation is by content, always (D-4).
 */
internal val ANNOTATION_IMPORT_MIME_TYPES = arrayOf("application/json", "*/*")

/**
 * Which pick the sheet currently belongs to, so a LATE answer from an abandoned one cannot write
 * over it (Gate-4 round 2, Medium).
 *
 * The reachable interleavings this exists for, none of them exotic once a provider is slow:
 *  - pick file A, its preview parks, reopen Details, pick file B — whichever parse returns LAST
 *    would otherwise win, and the user would be shown A's counts for B's file (or the reverse);
 *  - tap `Import N items` twice before the merge settles — a second apply would queue behind the
 *    first;
 *  - dismiss during a merge and pick again — the first merge's late settle would clear or overwrite
 *    the second pick's sheet.
 *
 * Room's `IGNORE` keeps the DATABASE consistent through all of these, so this is not a data hazard —
 * it is a "the sheet is showing the wrong pick" hazard, which is the one the user can act on. One
 * monotonic counter answers all three: every user-initiated transition takes a new token, and an
 * answer may only write if its token is still the current one. Deliberately NOT thread-safe — every
 * call site is the main thread.
 */
internal class AnnotationImportSession {
    var current: Int = 0
        private set

    private var applying: Int = NONE

    /** A new pick (or a dismissal): everything in flight for the previous token is now stale. */
    fun begin(): Int {
        current += 1
        applying = NONE
        return current
    }

    /** True while [token] is still the pick the sheet belongs to. */
    fun isCurrent(token: Int): Boolean = token == current

    /**
     * Claim the merge for the current pick, or refuse because one is already running for it — this
     * is what makes a double tap on `Import N items` a no-op rather than a second apply.
     */
    fun tryBeginApply(): Int? {
        if (applying == current) return null
        applying = current
        return current
    }

    /** Release the claim once [token]'s merge has settled (ignored if a newer pick took over). */
    fun endApply(token: Int) {
        if (token == current) applying = NONE
    }

    private companion object {
        const val NONE = -1
    }
}

/**
 * Run the approved merge on [scope] and hand the sheet's next state to [onSettled] (null = the sheet
 * dismisses; a [AnnotationImportSheetState.Failed] re-renders the designed error blob).
 *
 * [scope] MUST outlive the composition — see `AnnotationImportEntry.kt`'s header for why.
 */
internal fun launchAnnotationImportApply(
    scope: CoroutineScope,
    preview: ImportPreview,
    apply: suspend (ImportPreview) -> Result<RestoreAnnotationsReport>,
    onSettled: suspend (AnnotationImportSheetState?) -> Unit,
): Job = scope.launch {
    val next = apply(preview).fold(
        onSuccess = { null },
        onFailure = { error -> importApplyFailureState(error, preview.fileName) },
    )
    onSettled(next)
}

/**
 * The file name the designed header shows when the boundary refused the document, derived from the
 * picked `Uri`'s last path segment.
 *
 * That segment is provider-controlled text and gets the SAME treatment `DISPLAY_NAME` gets (section
 * 8.4): leaf-only extraction, a pre-normalization bound, NFC, control-character and Bidi_Control
 * removal, unpaired-surrogate removal, and a 200-char cap that never splits a surrogate pair.
 * Null / blank / fully-stripped becomes `Untitled`.
 */
internal fun importPickerFileName(rawLastPathSegment: String?): String =
    IncomingBookResolver.sanitizeDisplayName(rawLastPathSegment)

/**
 * The boundary's answer as the designed sheet's state.
 *
 * A readable file keeps the controller's own sanitized `DISPLAY_NAME` (carried on the preview); only
 * a refusal falls back to [fallbackName]. `importable == 0` is `Ready`, not `Failed` — C-8 is a
 * disabled primary, not the error blob.
 */
internal fun importSheetStateFor(
    result: ImportParseResult,
    fallbackName: String,
): AnnotationImportSheetState = when (result) {
    is ImportParseResult.Ok -> AnnotationImportSheetState.Ready(result.preview)
    is ImportParseResult.Failed -> AnnotationImportSheetState.Failed(fallbackName, result.reason)
}

/**
 * An apply-time failure as the SAME designed error branch (section 3.2), keeping its typed reason.
 *
 * Anything that is not an [AnnotationImportFailedException] never passed through the feature's own
 * taxonomy, so it reports `Unreadable` rather than a guess; the throwable's text is never shown —
 * `ImportFailure.userMessage` is a fixed string (rule 50 section 6).
 */
internal fun importApplyFailureState(
    error: Throwable,
    fileName: String,
): AnnotationImportSheetState.Failed = AnnotationImportSheetState.Failed(
    fileName = fileName,
    reason = (error as? AnnotationImportFailedException)?.reason ?: ImportFailure.Unreadable,
)
