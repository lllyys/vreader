// Purpose: feature #165 WI-5 — the designed post-pick annotations-import preview/confirm sheet
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-annotation-import.jsx:425-558`,
// `ImportPreviewSheet`) as a `ModalBottomSheet`: the sheet's STATE, the modal wrapper, the content
// spine and the designed action pair. The presentational sections it composes (file header, error
// blob, count chips, sample list, merge line) live in `AnnotationImportPreviewSections.kt`, which
// also carries this surface's rule-51 fidelity ledger.
//
// Split into the wrapper and [AnnotationImportPreviewSheetContent] so instrumented clicks reach the
// content directly (the `AnnotationsReviewSheetContent` / `TocContentsSheetContent` precedent).
// Pure function of state (rule 50 §4); [ReaderTheme] tokens, same map as the reader chrome.
//
// Key decisions:
//  - EVERY count rendered here is read off the [ImportPreview] the reader produced — the collapsed,
//    validated, already-present-filtered envelope (§6.4). The chips render its three stored kind
//    counts and the primary renders its own `importable` total; this file computes NO count of its
//    own and has no access to the raw file, so there is nothing here that could disagree with what
//    apply will insert. (`importable` is a sum of the three stored fields inside `ImportPreview` —
//    WI-3's contract, asserted equal to the real apply's report by WI-4's A-11 test. The precision
//    matters: the guarantee is "the sheet adds nothing", not "no addition happens anywhere".)
//  - `onConfirm` hands the SAME `ImportPreview` object back, so the caller applies the object whose
//    numbers the user approved rather than rebuilding one from the displayed counts. "The number
//    the user approves must be the number they get" is an object-identity property here.
//  - The primary is a real disabled `Button` when `importable == 0` (C-8) — disabled semantics, not
//    a grey-looking control that still fires.
//  - The body SCROLLS and the action pair is PINNED (the artboard's `maxHeight: '88%'`, `:440`).
//    An unbounded `bookTitle` in the merge line must not be able to push Cancel / Import off the
//    bottom of the sheet — Gate-4 round 1 found that shape.
//  - No export affordance exists on this surface: that one is `BLOCKED: needs-design (#2085)`.
//
// @coordinates-with AnnotationImportPreviewSections (the designed sections it renders),
// AnnotationImportModels (ImportPreview / ImportFailure), AnnotationsImportReader (the only
// producer of a preview), AnnotationsImportApplier (WI-4, what `onConfirm` feeds).
package com.vreader.app.annotations

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * What the import sheet is showing. Both arms carry a [fileName] because the designed file header
 * (`:449-475`) sits OUTSIDE the artboard's error branch — a refused file still names itself.
 */
sealed interface AnnotationImportSheetState {
    val fileName: String

    /** A readable file. [ImportPreview.importable] may be 0 (C-8) — that is a disabled primary,
     *  not a failure. */
    data class Ready(val preview: ImportPreview) : AnnotationImportSheetState {
        override val fileName: String get() = preview.fileName
    }

    /** A file-level refusal: nothing is applied, the designed error blob is what the user sees. */
    data class Failed(override val fileName: String, val reason: ImportFailure) :
        AnnotationImportSheetState
}

/**
 * The designed import preview/confirm sheet as a [ModalBottomSheet]. [onConfirm] receives the very
 * [ImportPreview] on screen; [onCancel] is the designed Cancel button; [onDismiss] is the swipe /
 * scrim dismissal.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnnotationImportPreviewSheet(
    theme: ReaderTheme,
    state: AnnotationImportSheetState,
    onCancel: () -> Unit,
    onConfirm: (ImportPreview) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = theme.background,
        modifier = modifier.testTag("annot-import-sheet"),
    ) {
        AnnotationImportPreviewSheetContent(
            theme = theme,
            state = state,
            onCancel = onCancel,
            onConfirm = onConfirm,
        )
    }
}

/**
 * The sheet's content, extracted from the modal wrapper so it is directly UI-testable. Renders the
 * file header, then either the error blob or the counts + sample + merge line, then the action
 * pair. The primary is enabled only when a [AnnotationImportSheetState.Ready] preview has at least
 * one importable row.
 */
@Composable
fun AnnotationImportPreviewSheetContent(
    theme: ReaderTheme,
    state: AnnotationImportSheetState,
    onCancel: () -> Unit,
    onConfirm: (ImportPreview) -> Unit,
) {
    val ready = state as? AnnotationImportSheetState.Ready
    // The ONLY source of the primary's number: the preview's own collapsed envelope.
    val importable = ready?.preview?.importable ?: 0

    Column(
        Modifier
            .fillMaxWidth()
            .background(theme.background)
            .padding(bottom = 28.dp)
            .testTag("annot-import-sheet-content"),
    ) {
        ImportFileHeader(theme, state.fileName)

        // The scrolling region. The action pair below it is pinned, so no amount of body content —
        // a 10 000-character book title in the merge line, a three-row sample of long CJK quotes —
        // can push Cancel / Import out of reach.
        //
        // `weight(1f, fill = false)` and NOT a fixed `heightIn(max = …)`: the body must take the
        // space that is LEFT after the header and the actions, which is a different number on a
        // compact screen at a large font scale than on a tall one. A constant cap looks correct on
        // a roomy host and silently pushes both actions off a 320x480 viewport at fontScale 2 —
        // Gate-4 round 2 predicted that and `actionsStayReachableOnACompactViewportAtDoubleFontScale`
        // reproduced it. `fill = false` keeps the sheet wrap-height when the content is short.
        Column(
            Modifier
                .fillMaxWidth()
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState()),
        ) {
            when (state) {
                is AnnotationImportSheetState.Failed -> ImportErrorBlob(theme, state.reason)
                is AnnotationImportSheetState.Ready -> ImportPreviewBody(theme, state.preview)
            }
        }

        Row(
            Modifier
                .fillMaxWidth()
                .padding(start = 22.dp, end = 22.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SheetButton(
                label = "Cancel",
                container = theme.neutralButton(),
                content = theme.ink,
                tag = "annot-import-cancel",
                modifier = Modifier.weight(1f),
                onClick = onCancel,
            )
            Spacer(Modifier.width(10.dp))
            SheetButton(
                label = "Import $importable items",
                container = theme.accent,
                content = Color.White,
                tag = "annot-import-confirm",
                modifier = Modifier.weight(1.2f),
                enabled = importable > 0,
                disabledContainer = theme.neutralButton(),
                disabledContent = theme.sub(),
                onClick = { ready?.preview?.let(onConfirm) },
            )
        }
    }
}

/** The designed action button (`:542-555`) — a real [Button], so "disabled" is disabled semantics. */
@Composable
private fun SheetButton(
    label: String,
    container: Color,
    content: Color,
    tag: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    disabledContainer: Color = container,
    disabledContent: Color = content,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier.testTag(tag),
        enabled = enabled,
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = container,
            contentColor = content,
            disabledContainerColor = disabledContainer,
            disabledContentColor = disabledContent,
        ),
        contentPadding = PaddingValues(vertical = 12.dp),
    ) {
        Text(
            label,
            fontFamily = VReaderFonts.Sans,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
