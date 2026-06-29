// Purpose: feature #106 — the vreader Android app's entry Activity. Hosts the
// Library screen (WI-8, the committed vreader-fidelity-v1 design) wired to the
// shipped plumbing: the LibraryViewModel (Room-backed StateFlow) + the SAF
// OpenDocument picker → BookImporter. Opening a book is the reader host (#1745),
// resumed against vreader-reader.jsx.
//
// @coordinates-with: AndroidManifest.xml (the launcher activity), VReaderApp.kt
//   (the DI container), library/LibraryViewModel.kt, library/LibraryScreen.kt
package com.vreader.app

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.vreader.app.library.AssignToCollectionsSheet
import com.vreader.app.library.ManageCollectionsSheet
import com.vreader.app.library.LibraryEvent
import com.vreader.app.library.LibraryScreen
import com.vreader.app.library.LibraryViewModel
import com.vreader.app.library.SheetRoute
import com.vreader.app.library.SheetRouteSaver
import com.vreader.app.reader.Azw3ReaderActivity
import com.vreader.app.reader.ReaderActivity
import com.vreader.app.reader.PdfReaderActivity
import com.vreader.app.reader.TxtReaderActivity
import com.vreader.app.ui.theme.VReaderTheme
import vreader.contracts.BookFormat
import androidx.compose.runtime.LaunchedEffect

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as VReaderApp).container
        val factory = viewModelFactory {
            initializer { LibraryViewModel(container.repository, container.importer, container.collectionRepository, contentResolver) }
        }

        setContent {
            VReaderTheme {
                val viewModel: LibraryViewModel = viewModel(factory = factory)
                val state by viewModel.uiState.collectAsStateWithLifecycle()
                val collections by viewModel.collections.collectAsStateWithLifecycle()
                val selectedCollectionId by viewModel.selectedCollectionId.collectAsStateWithLifecycle()
                // feature #127 WI-4 — which collections sheet is open (survives rotation/process death).
                var sheetRoute by rememberSaveable(stateSaver = SheetRouteSaver) { mutableStateOf<SheetRoute>(SheetRoute.None) }

                val picker = rememberLauncherForActivityResult(
                    ActivityResultContracts.OpenDocument(),
                ) { uri -> uri?.let(viewModel::import) }

                LaunchedEffect(Unit) {
                    viewModel.events.collect { event ->
                        val message = when (event) {
                            is LibraryEvent.ImportFailed -> event.message
                            is LibraryEvent.CollectionOpFailed -> event.message
                        }
                        Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
                    }
                }

                LibraryScreen(
                    state = state,
                    collections = collections,
                    selectedCollectionId = selectedCollectionId,
                    onSelectCollection = viewModel::selectCollection,
                    onAssignBook = { book -> sheetRoute = SheetRoute.Assign(book.id) },
                    onManageCollections = { sheetRoute = SheetRoute.Manage },
                    onOpenBook = { book ->
                        // Route by the typed format (exhaustive — never open a format into
                        // the wrong host). Formats without a reader yet are surfaced, not
                        // silently mis-opened.
                        when (book.originalFormat) {
                            BookFormat.epub ->
                                startActivity(ReaderActivity.intent(this@MainActivity, book.id))
                            BookFormat.txt, BookFormat.md ->
                                // .md reuses the text reader host (#112): same decode/
                                // document/resume/chrome, MarkdownRenderer per chunk.
                                startActivity(TxtReaderActivity.intent(this@MainActivity, book.id))
                            BookFormat.pdf ->
                                // #115 — continuous-scroll PdfRenderer reader.
                                startActivity(PdfReaderActivity.intent(this@MainActivity, book.id))
                            BookFormat.azw3 ->
                                // #126 — foliate-js WebView reader (AZW3/MOBI/KF8).
                                startActivity(Azw3ReaderActivity.intent(this@MainActivity, book.id))
                        }
                    },
                    // EPUBs are exposed by SAF providers under varied MIME types
                    // (epub+zip, octet-stream, generic); accept broadly and let
                    // BookImporter reject non-EPUBs by extension with a clear toast.
                    onImport = {
                        picker.launch(
                            arrayOf("application/epub+zip", "application/octet-stream", "*/*"),
                        )
                    },
                )

                // feature #127 WI-4 — the assign-to-collections sheet (long-press a book).
                val route = sheetRoute
                if (route is SheetRoute.Assign) {
                    // resolve from the UNFILTERED library so unassigning from a filtered collection
                    // doesn't drop the book + close the sheet (Gate-4 WI-4 High).
                    val allBooks by viewModel.allBooks.collectAsStateWithLifecycle()
                    val book = allBooks.firstOrNull { it.id == route.bookKey }
                    if (book == null && allBooks.isNotEmpty()) {
                        // the library has loaded and the book is genuinely gone (deleted) → close.
                        LaunchedEffect(route) { sheetRoute = SheetRoute.None }
                    } else if (book != null) {
                        val memberIdsFlow = remember(route.bookKey) { viewModel.collectionIdsForBook(route.bookKey) }
                        val memberIds by memberIdsFlow.collectAsStateWithLifecycle(emptyList())
                        AssignToCollectionsSheet(
                            bookTitle = book.title,
                            collections = collections,
                            memberIds = memberIds.toHashSet(),
                            onToggle = { id, nowMember ->
                                if (nowMember) viewModel.assign(route.bookKey, id) else viewModel.unassign(route.bookKey, id)
                            },
                            onCreateAndAssign = { name -> viewModel.createCollectionAndAssign(name, route.bookKey) },
                            onDismiss = { sheetRoute = SheetRoute.None },
                        )
                    }
                }

                // feature #127 WI-5 — the manage-collections sheet (list + rename + create), opened from
                // the designed scoped-collection "edit collection" header. Delete is deferred to a
                // needs-design follow-up (the design routes it behind an undepicted detail disclosure).
                if (route is SheetRoute.Manage) {
                    ManageCollectionsSheet(
                        collections = collections,
                        onRename = { id, newName -> viewModel.renameCollection(id, newName) },
                        onCreate = { name -> viewModel.createCollection(name) },
                        onDismiss = { sheetRoute = SheetRoute.None },
                    )
                }
            }
        }
    }
}
