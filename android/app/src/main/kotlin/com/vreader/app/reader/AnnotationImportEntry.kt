// Purpose: feature #165 WI-7 — the ONE annotation-import entry the four reader hosts share: the
// production SAF `ACTION_OPEN_DOCUMENT` launcher, the designed preview sheet's state, and the
// apply call. This is what makes annotation import reachable by a real user (criterion A-10a);
// before it, WI-6's Import row existed but no production call site passed a callback.
//
// Pipeline: the Details sheet's `Import annotations…` row -> [AnnotationImportEntry.launch] ->
// the system document picker -> the picked `Uri` -> `AnnotationsIoController.preview` (bounded,
// section 8.1) -> the designed `AnnotationImportPreviewSheet` -> the user's `Import N items` ->
// `AnnotationsIoController.apply` -> the merged rows appear in the already-designed Notes sheet.
//
// Key decisions:
//  - FOUR HOSTS, ONE COPY. Four activities registering their own launcher and their own state
//    machine is four chances to drift (plan R-4). The hosts hold a `rememberAnnotationImportEntry`
//    call and pass its three members on; every decision lives here, and every bounded provider
//    call lives one layer further down in `AnnotationsIoController`.
//  - NOTHING HERE TOUCHES A `ContentResolver`. The picked `Uri` is handed straight to the
//    controller, whose every provider call runs through the shipped `BoundedCallGate` (section
//    8.5 forbids a bare resolver call anywhere in this feature). This file must stay that way.
//  - THE DETAILS SHEET IS DISMISSED BEFORE THE PICKER OPENS. The system picker covers the screen
//    and returns to a reader, not to a stale modal; and stacking the preview `ModalBottomSheet`
//    on top of the Details `ModalBottomSheet` would put two dialog windows up at once for no
//    designed reason. Section 3.2's claim that the parse window needs NO new pixels still holds —
//    it names the absence of a progress surface, and there is none either way.
//  - A CANCELLED PICK IS SILENT. `OpenDocument` yields a null `Uri` when the user backs out; that
//    is not a failure and the designed error blob would be a lie. No surface, no state change
//    (rule 51 — the design draws no "you cancelled" state, so none is invented).
//  - THE REFUSAL PATH STILL NAMES THE FILE, AND THE NAME IS SANITIZED HERE. The designed file
//    header sits OUTSIDE the error branch, but `ImportParseResult.Failed` carries no name, so the
//    only name left is the picked `Uri`'s last path segment — as provider-controlled as
//    `DISPLAY_NAME`, and therefore run through the same
//    `IncomingBookResolver.sanitizeDisplayName` the controller uses (section 8.4). A readable file
//    uses the controller's sanitized `DISPLAY_NAME` instead; the fallback is only ever the
//    second-best name, never the preferred one.
//  - THE PREVIEW TRAVELS BY IDENTITY. `onConfirm` hands back the very `ImportPreview` object the
//    reader produced, so "the number the user approves is the number they get" (section 6.4) is an
//    object-identity property rather than a re-derivation that could disagree.
//  - THE MERGE RUNS ON A SCOPE THAT OUTLIVES THE COMPOSITION, THE PREVIEW DOES NOT. Once the user
//    has tapped `Import N items` the work is committed as far as they are concerned, and
//    `AnnotationsImportApplier` rethrows `CancellationException` — so an apply started on a
//    `rememberCoroutineScope()` is cancelled by a rotation, a back press, or a `finish()`, the
//    transaction rolls back, and NOTHING lands with no surface to say so. The hosts therefore pass
//    the process-lifetime `container.appScope` for the apply (Gate-4 round 1, High). The PREVIEW
//    stays on the composition scope deliberately: it writes nothing, and a user who leaves before
//    the sheet appears wants it abandoned.
//  - APPLY FAILURE RE-RENDERS THE SAME DESIGNED ERROR BRANCH (section 3.2 / D-10b), keeping the
//    typed reason. The transaction is atomic, so the honest choice really is "all, or the blob".
//
// @coordinates-with AnnotationsIoController (the bounded I/O boundary this drives),
//   AnnotationImportPreviewSheet (the designed surface it feeds), BookDetailsRows (the designed
//   Import row that calls `launch`), ReaderChromeScaffold + EpubReaderSheets (the two chrome hosts
//   that render the sheet), VReaderApp (which builds the controller from the ONE app-wide gate).
package com.vreader.app.reader

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import com.vreader.app.annotations.AnnotationImportPreviewSheet
import com.vreader.app.annotations.AnnotationImportSheetState
import com.vreader.app.annotations.AnnotationsIoController
import com.vreader.app.annotations.ImportPreview
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * What a reader host needs to offer annotation import: the designed sheet's current state (null =
 * no sheet), and the three things the user can do.
 *
 * [launch] is what the designed `Import annotations…` row calls. [dismiss] is Cancel / swipe /
 * scrim. [confirm] is `Import N items`, and it receives the very preview on screen.
 */
@Immutable
class AnnotationImportEntry internal constructor(
    val sheet: AnnotationImportSheetState?,
    val launch: () -> Unit,
    val dismiss: () -> Unit,
    val confirm: (ImportPreview) -> Unit,
)

/**
 * Registers the production SAF launcher for [bookKey] and drives the designed preview sheet.
 *
 * [applyScope] MUST outlive this composition — production passes `container.appScope`. It carries
 * only the MERGE; see this file's header for why the two phases get different scopes.
 *
 * [onLaunching] runs immediately before the picker opens — the hosts use it to close the Details
 * sheet the row was tapped in. [onApplied] runs on the main thread after a successful merge; hosts
 * that keep a one-shot annotations snapshot use it to refresh, and hosts whose snapshot is a live
 * Flow need nothing.
 *
 * Must be called from a composition hosted by a `ComponentActivity`
 * (`rememberLauncherForActivityResult`'s requirement) — every reader host is one.
 */
@Composable
internal fun rememberAnnotationImportEntry(
    controller: AnnotationsIoController,
    bookKey: String,
    bookTitle: String,
    applyScope: CoroutineScope,
    onLaunching: () -> Unit = {},
    onApplied: () -> Unit = {},
): AnnotationImportEntry {
    val previewScope = rememberCoroutineScope()
    var sheet by remember(bookKey) { mutableStateOf<AnnotationImportSheetState?>(null) }
    val session = remember(bookKey) { AnnotationImportSession() }
    // The host callback is read at CALL time, not at registration time: the merge can settle after
    // a recomposition handed us a newer one.
    val latestOnApplied by rememberUpdatedState(onApplied)

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        // A cancelled pick is silent — no state, no surface (see this file's header). The token was
        // already taken by `launch`, so an in-flight preview from a PREVIOUS pick stays abandoned.
        if (uri == null) return@rememberLauncherForActivityResult
        val token = session.current
        val fallbackName = importPickerFileName(uri.lastPathSegment)
        previewScope.launch {
            val next = importSheetStateFor(controller.preview(uri, bookKey, bookTitle), fallbackName)
            if (session.isCurrent(token)) sheet = next
        }
    }

    return AnnotationImportEntry(
        sheet = sheet,
        launch = {
            session.begin()
            onLaunching()
            picker.launch(ANNOTATION_IMPORT_MIME_TYPES)
        },
        // Dismissal takes a token too: a sheet the user closed must not be resurrected by a parse
        // that returns afterwards.
        dismiss = { session.begin(); sheet = null },
        confirm = confirm@{ preview ->
            // A second tap while the first merge is still running is a NO-OP, not a second apply.
            val token = session.tryBeginApply() ?: return@confirm
            launchAnnotationImportApply(applyScope, preview, controller::apply) { next ->
                // Back onto the main thread for the state write + the host's refresh. If this
                // composition is already gone the write lands on an orphaned state (harmless) and
                // the host's refresh is a no-op on its cancelled lifecycle scope — but the MERGE
                // itself has already committed, which is the point.
                withContext(Dispatchers.Main) {
                    session.endApply(token)
                    if (!session.isCurrent(token)) return@withContext
                    sheet = next
                    // On success the observable result is the designed annotations list itself
                    // (section 3.2) — no "42 imported!" banner is invented here.
                    if (next == null) latestOnApplied()
                }
            }
        },
    )
}

/**
 * This entry's designed sheet as a chrome-host `importSheet` slot, or null when nothing is picked.
 *
 * Deliberately NOT a `@Composable` — it is a plain mapping from state to a slot, so a host can
 * compute it wherever it already has the theme, and so "no pick, no slot" is a null the host can
 * see rather than a composable that renders nothing.
 */
internal fun AnnotationImportEntry.sheetSlot(theme: ReaderTheme): (@Composable () -> Unit)? {
    val state = sheet ?: return null
    return {
        AnnotationImportPreviewSheet(
            theme = theme,
            state = state,
            onCancel = dismiss,
            onConfirm = confirm,
            onDismiss = dismiss,
        )
    }
}

// The MIME hint, the session token, the merge launcher and the boundary-answer -> sheet-state
// mappings live in AnnotationImportEntryState.kt — everything here needs a composition, everything
// there is reachable from a JVM test.
