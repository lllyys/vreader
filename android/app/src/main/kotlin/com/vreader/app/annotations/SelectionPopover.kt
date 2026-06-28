// Purpose: feature #123 WI-3 — the in-reader selection popover (design vreader-android-annotations.jsx
// `SelectionPopover`): a white rounded card with a 5-color dot row (+ "+"), a two-mode action row
// (SELECT: Highlight/Note/Copy/Translate/Share · EDIT: Note/Copy/Share/Remove), an inline NOTE compose
// row, and a downward notch. Pure function of [SelectionPopoverState] + callbacks; the host anchors it.
package com.vreader.app.annotations

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts

private val CARD = Color.White
private val DIVIDER = Color(0x1A1D1A14)
private val DANGER = Color(0xFFB5503F)

private fun colorOf(hex: String): Color = Color(android.graphics.Color.parseColor(hex))

/** Callbacks the host wires to side effects (persist / decorate / copy / share). */
data class SelectionPopoverActions(
    val onColor: (AnnotationColor) -> Unit = {},
    val onHighlight: () -> Unit = {},
    val onNote: () -> Unit = {},
    val onCopy: () -> Unit = {},
    val onShare: () -> Unit = {},
    val onRemove: () -> Unit = {},
    val onNoteDraftChange: (String) -> Unit = {},
    val onSaveNote: () -> Unit = {},
    val onCancelNote: () -> Unit = {},
)

@Composable
fun SelectionPopover(state: SelectionPopoverState, actions: SelectionPopoverActions, modifier: Modifier = Modifier) {
    if (!state.visible) return
    Column(
        modifier
            .widthIn(max = 340.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(CARD)
            .testTag("selection-popover"),
    ) {
        ColorRow(state.activeColor, actions.onColor)
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(DIVIDER))
        when (state.mode) {
            PopoverMode.NOTE -> NoteCompose(state.noteDraft, actions)
            PopoverMode.EDIT -> ActionRow(editMode = true, actions = actions)
            PopoverMode.SELECT -> ActionRow(editMode = false, actions = actions)
        }
    }
}

@Composable
private fun ColorRow(active: AnnotationColor, onColor: (AnnotationColor) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AnnotationColor.palette.forEach { c ->
            val selected = c == active
            Box(
                Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(colorOf(c.dotHex))
                    .then(if (selected) Modifier.border(2.5.dp, colorOf(c.dotHex), CircleShape) else Modifier)
                    .clickable { onColor(c) }
                    .testTag("popover-color-${c.key}"),
            )
        }
        Box(Modifier.size(width = 0.5.dp, height = 26.dp).background(DIVIDER))
        Box(
            Modifier.size(28.dp).clip(CircleShape).border(1.5.dp, VReaderColors.InkMuted, CircleShape),
            contentAlignment = Alignment.Center,
        ) { Text("+", color = VReaderColors.InkMuted, fontSize = 16.sp) }
    }
}

@Composable
private fun ActionRow(editMode: Boolean, actions: SelectionPopoverActions) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (editMode) {
            ActionBtn(Icons.Outlined.EditNote, "Note", actions.onNote)
            ActionBtn(Icons.Filled.ContentCopy, "Copy", actions.onCopy)
            ActionBtn(Icons.Filled.Share, "Share", actions.onShare)
            ActionBtn(Icons.Filled.Close, "Remove", actions.onRemove, danger = true)
        } else {
            ActionBtn(Icons.Outlined.BorderColor, "Highlight", actions.onHighlight)
            ActionBtn(Icons.Outlined.EditNote, "Note", actions.onNote)
            ActionBtn(Icons.Filled.ContentCopy, "Copy", actions.onCopy)
            // Translate is in the design but routes to #119 (bilingual/AI) — omitted here (plan §OOS)
            // rather than shipped as a dead no-op; it lands when #119 wires the translation path.
            ActionBtn(Icons.Filled.Share, "Share", actions.onShare)
        }
    }
}

@Composable
private fun ActionBtn(icon: ImageVector, label: String, onClick: () -> Unit, danger: Boolean = false) {
    val tint = if (danger) DANGER else VReaderColors.Ink
    Column(
        Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 4.dp).widthIn(min = 52.dp).testTag("popover-action-$label"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(20.dp))
        Text(label, color = if (danger) DANGER else VReaderColors.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun NoteCompose(draft: String, actions: SelectionPopoverActions) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp)) {
        Text("ADD NOTE", color = VReaderColors.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        Box(
            Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(10.dp))
                .background(Color(0x0A1D1A14)).padding(horizontal = 12.dp, vertical = 10.dp).height(72.dp),
        ) {
            BasicTextField(
                value = draft,
                onValueChange = actions.onNoteDraftChange,
                textStyle = TextStyle(color = VReaderColors.Ink, fontFamily = VReaderFonts.Serif, fontSize = 15.sp),
                modifier = Modifier.fillMaxWidth().testTag("popover-note-field"),
            )
        }
        Row(Modifier.fillMaxWidth().padding(top = 11.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Text(
                "Cancel", color = VReaderColors.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.Medium,
                modifier = Modifier.clip(RoundedCornerShape(9.dp)).clickable(onClick = actions.onCancelNote).padding(horizontal = 12.dp, vertical = 7.dp).testTag("popover-note-cancel"),
            )
            Text(
                "Save", color = Color.White, fontFamily = VReaderFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                modifier = Modifier.clip(RoundedCornerShape(9.dp)).background(VReaderColors.Accent).clickable(onClick = actions.onSaveNote).padding(horizontal = 16.dp, vertical = 7.dp).testTag("popover-note-save"),
            )
        }
    }
}
