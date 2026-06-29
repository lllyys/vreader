// Purpose: feature #127 WI-5 — the collections "manage" surface for the Android library.
// `ScopedCollectionHeader` is the DESIGNED scoped-collection header (vreader-library-android.jsx
// `scope === 'collection'`: a back breadcrumb to "All", the collection name in serif, and a
// "N books · edit collection" subtitle whose tap opens the manage sheet). `ManageCollectionsSheet`
// is the list+rename+create bottom sheet (the design's `CollectionsManageSheet` list mode). Delete is
// intentionally absent — the design routes it behind an undepicted Edit-mode detail disclosure, so its
// UI is deferred to needs-design #1875 (rule 51); the capability stays repo/VM-backed + tested.
//
// @coordinates-with: library/LibraryScreen.kt (renders ScopedCollectionHeader), library/CollectionSheets.kt
//   (the sibling AssignToCollectionsSheet + SheetRoute), MainActivity.kt (wires the sheet to the VM)
package com.vreader.app.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Add
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.data.Collection
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The DESIGNED scoped-collection header (vreader-library-android.jsx `scope === 'collection'`): a back
 * breadcrumb to the all-library view, the collection name (serif), and a "N books · edit collection"
 * subtitle whose tap is the entry into the manage sheet. Replaces the "Library" title + shelf-bar when a
 * collection is selected; per the design the scoped view has NO action pills (Gate-4 WI-5 round-2 Medium).
 */
@Composable
fun ScopedCollectionHeader(
    collectionName: String,
    bookCount: Int,
    onBack: () -> Unit,
    onEditCollection: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable { onBack() }
            .padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 4.dp)
            .testTag("scoped-back"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowLeft,
            contentDescription = "Back to all books",
            tint = VReaderColors.Ink.copy(alpha = 0.8f),
        )
        Text("Library", color = VReaderColors.InkMuted, fontSize = 14.sp)
    }
    Text(
        collectionName,
        Modifier.padding(start = 22.dp, end = 22.dp, top = 2.dp),
        color = VReaderColors.Ink,
        fontFamily = VReaderFonts.Serif,
        fontSize = 25.sp,
        fontWeight = FontWeight.Bold,
    )
    Text(
        "$bookCount books · edit collection",
        Modifier
            .clickable { onEditCollection() }
            .padding(start = 22.dp, end = 22.dp, top = 2.dp, bottom = 14.dp)
            .testTag("scoped-edit-collection"),
        color = VReaderColors.InkMuted,
        fontSize = 13.sp,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManageCollectionsSheet(
    collections: List<Collection>,
    onRename: (id: String, newName: String) -> Unit,
    onCreate: (name: String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = VReaderColors.Surface,
        modifier = Modifier.testTag("manage-sheet"),
    ) {
        ManageSheetContent(collections, onRename, onCreate)
    }
}

/** The manage-sheet content (extracted for direct UI testing). Lists collections with their book counts
 *  (the design's `CollectionsManageSheet` list mode); tapping a name reveals an inline rename field; the
 *  bottom "New Collection" row inline-creates. Per the design — NO reorder (the contract has no order
 *  field). Delete is intentionally absent: the design routes it behind the Edit-mode per-collection
 *  detail disclosure, which is not yet depicted — deferred to a needs-design follow-up (rule 51). */
@Composable
fun ManageSheetContent(
    collections: List<Collection>,
    onRename: (id: String, newName: String) -> Unit,
    onCreate: (name: String) -> Unit,
) {
    var renamingId by rememberSaveable { mutableStateOf<String?>(null) }
    var renameDraft by rememberSaveable { mutableStateOf("") }

    Column(Modifier.testTag("manage-sheet-content")) {
        Text(
            "Collections",
            Modifier.padding(start = 18.dp, end = 18.dp, bottom = 12.dp),
            color = VReaderColors.Ink, fontFamily = VReaderFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
        )
        Column(Modifier.padding(horizontal = 16.dp)) {
            Surface(shape = RoundedCornerShape(14.dp), color = VReaderColors.Background) {
                Column {
                    collections.forEachIndexed { i, c ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("manage-row-${c.name}").padding(horizontal = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.Folder, contentDescription = null, tint = VReaderColors.Accent, modifier = Modifier.size(19.dp))
                            if (renamingId == c.id) {
                                fun submit() {
                                    val name = renameDraft.trim()
                                    if (name.isNotEmpty()) onRename(c.id, name)
                                    renamingId = null
                                }
                                OutlinedTextField(
                                    value = renameDraft,
                                    onValueChange = { renameDraft = it },
                                    singleLine = true,
                                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                                    keyboardActions = KeyboardActions(onDone = { submit() }),
                                    modifier = Modifier.weight(1f).padding(start = 8.dp, top = 4.dp, bottom = 4.dp).testTag("manage-rename-field"),
                                )
                            } else {
                                Text(
                                    c.name,
                                    Modifier.weight(1f).padding(start = 11.dp)
                                        .clickable { renamingId = c.id; renameDraft = c.name }
                                        .testTag("manage-name-${c.name}"),
                                    color = VReaderColors.Ink, fontSize = 15.5.sp, fontFamily = VReaderFonts.Sans,
                                )
                                Text("${c.bookCount}", color = VReaderColors.InkMuted, fontSize = 13.5.sp, fontFamily = VReaderFonts.Sans)
                            }
                        }
                        if (i < collections.lastIndex) {
                            HorizontalDivider(Modifier.padding(start = 44.dp), thickness = 0.5.dp, color = VReaderColors.Ink.copy(alpha = 0.08f))
                        }
                    }
                }
            }

            ManageNewCollectionRow(onCreate = onCreate)
        }
    }
}

/** The manage sheet's "New Collection" inline-create row. */
@Composable
private fun ManageNewCollectionRow(onCreate: (String) -> Unit) {
    var editing by rememberSaveable { mutableStateOf(false) }
    var draft by rememberSaveable { mutableStateOf("") }

    if (!editing) {
        Row(
            Modifier.fillMaxWidth().clickable { editing = true }.testTag("manage-new-collection").padding(vertical = 15.dp, horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = VReaderColors.Accent, modifier = Modifier.size(20.dp))
            Text("New Collection", color = VReaderColors.Accent, fontSize = 15.5.sp, fontWeight = FontWeight.Medium, fontFamily = VReaderFonts.Sans)
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
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag("manage-new-collection-field"),
        )
    }
}
