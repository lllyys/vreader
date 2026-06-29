// Purpose: the collections bottom sheets — feature #127 WI-4 (assign) / WI-5 (manage). A Compose
// recreation of the committed design `vreader-library-android.jsx` AssignSheet: an "Add to Collection"
// modal bottom sheet (book header + a checklist of collections + an inline "New Collection…"). Tapping
// a collection row toggles membership and does NOT close the sheet (batch assign). Pure function of
// (book, collections, memberIds) + callbacks (rule 50 §4). SheetRoute is the hoisted open-sheet state.
package com.vreader.app.library

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.data.Collection
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts

/** Which collections sheet is open. Saveable across rotation/process death via [SheetRouteSaver]. */
sealed interface SheetRoute {
    data object None : SheetRoute
    data object Manage : SheetRoute
    data class Assign(val bookKey: String) : SheetRoute
}

/** Serializes [SheetRoute] to a string so `rememberSaveable` survives process death. */
val SheetRouteSaver: Saver<SheetRoute, String> = Saver(
    save = {
        when (it) {
            SheetRoute.None -> "none"
            SheetRoute.Manage -> "manage"
            is SheetRoute.Assign -> "assign:${it.bookKey}"
        }
    },
    restore = {
        when {
            it == "manage" -> SheetRoute.Manage
            it.startsWith("assign:") -> SheetRoute.Assign(it.removePrefix("assign:"))
            else -> SheetRoute.None
        }
    },
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssignToCollectionsSheet(
    bookTitle: String,
    collections: List<Collection>,
    memberIds: Set<String>,
    onToggle: (collectionId: String, nowMember: Boolean) -> Unit,
    onCreateAndAssign: (name: String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = VReaderColors.Surface,
        modifier = Modifier.testTag("assign-sheet"),
    ) {
        AssignSheetContent(bookTitle, collections, memberIds, onToggle, onCreateAndAssign)
    }
}

/** The sheet's content, extracted from the [ModalBottomSheet] wrapper so it's directly UI-testable. */
@Composable
fun AssignSheetContent(
    bookTitle: String,
    collections: List<Collection>,
    memberIds: Set<String>,
    onToggle: (collectionId: String, nowMember: Boolean) -> Unit,
    onCreateAndAssign: (name: String) -> Unit,
) {
    Column(Modifier.testTag("assign-sheet-content")) {
        // Header — a placeholder cover + "Add to Collection" + the book title.
        Row(
            Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                Modifier.size(44.dp, 60.dp).clip(RoundedCornerShape(4.dp)).background(VReaderColors.Ink.copy(alpha = 0.08f)),
            )
            Column(Modifier.weight(1f)) {
                Text("Add to Collection", color = VReaderColors.Ink, fontFamily = VReaderFonts.Serif, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Text(bookTitle, color = VReaderColors.InkMuted, fontSize = 12.5.sp, maxLines = 1, fontFamily = VReaderFonts.Sans)
            }
        }

        // Collection rows in the designed rounded card with row dividers — tap toggles membership
        // (no auto-close, batch assign).
        Column(Modifier.padding(horizontal = 16.dp)) {
            Surface(shape = RoundedCornerShape(14.dp), color = VReaderColors.Background) {
                Column {
                    collections.forEachIndexed { i, c ->
                        val member = c.id in memberIds
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 52.dp)
                                .clickable { onToggle(c.id, !member) }
                                .testTag("assign-row-${c.name}")
                                .padding(horizontal = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.Folder, contentDescription = null, tint = VReaderColors.InkMuted, modifier = Modifier.size(19.dp))
                            Text(c.name, Modifier.weight(1f).padding(start = 11.dp), color = VReaderColors.Ink, fontSize = 15.5.sp, fontFamily = VReaderFonts.Sans)
                            if (member) {
                                Icon(Icons.Filled.CheckCircle, contentDescription = "In collection", tint = VReaderColors.Accent, modifier = Modifier.size(22.dp).testTag("assign-check-${c.name}"))
                            } else {
                                Box(Modifier.size(22.dp).clip(CircleShape).border(1.7.dp, VReaderColors.Ink.copy(alpha = 0.18f), CircleShape).testTag("assign-uncheck-${c.name}"))
                            }
                        }
                        if (i < collections.lastIndex) {
                            HorizontalDivider(Modifier.padding(start = 44.dp), thickness = 0.5.dp, color = VReaderColors.Ink.copy(alpha = 0.08f))
                        }
                    }
                }
            }

            NewCollectionRow(onCreate = onCreateAndAssign)
        }
    }
}

/** The inline "New Collection…" row — reveals a text field + Add on tap; submits a non-blank name. */
@Composable
private fun NewCollectionRow(onCreate: (String) -> Unit) {
    var editing by rememberSaveable { mutableStateOf(false) }
    var draft by rememberSaveable { mutableStateOf("") }

    if (!editing) {
        Row(
            Modifier.fillMaxWidth().clickable { editing = true }.testTag("assign-new-collection").padding(vertical = 15.dp, horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = VReaderColors.Accent, modifier = Modifier.size(19.dp))
            Text("New Collection…", color = VReaderColors.Accent, fontSize = 15.sp, fontWeight = FontWeight.Medium, fontFamily = VReaderFonts.Sans)
        }
    } else {
        fun submit() {
            val name = draft.trim()
            if (name.isNotEmpty()) onCreate(name)
            draft = ""; editing = false
        }
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            singleLine = true,
            placeholder = { Text("Collection name", color = Color.Gray) },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { submit() }),
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag("assign-new-collection-field"),
        )
    }
}
