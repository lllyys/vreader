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
//  - EVERY count rendered here comes from the [ImportPreview] the reader produced — the collapsed,
//    validated, already-present-filtered envelope (§6.4). Nothing is re-derived from anything on
//    screen, and `onConfirm` hands the SAME `ImportPreview` object back, so the caller applies the
//    object whose numbers the user approved. "The number the user approves must be the number they
//    get" is an object-identity property here, not an arithmetic coincidence.
//  - The primary is a real disabled `Button` when `importable == 0` (C-8) — disabled semantics, not
//    a grey-looking control that still fires.
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
import androidx.compose.foundation.shape.RoundedCornerShape
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

        when (state) {
            is AnnotationImportSheetState.Failed -> ImportErrorBlob(theme, state.reason)
            is AnnotationImportSheetState.Ready -> ImportPreviewBody(theme, state.preview)
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
