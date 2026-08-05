// Purpose: feature #106 — the vreader Android app's entry Activity. Hosts the
// Library screen (WI-8, the committed vreader-fidelity-v1 design) wired to the
// shipped plumbing: the LibraryViewModel (Room-backed StateFlow) + the SAF
// OpenDocument picker → BookImporter. Opening a book is the reader host (#1745),
// resumed against vreader-reader.jsx.
//
// It is also where feature #155's inbound imports SURFACE: ImportActivity does the
// resolving and hands off here, and this screen collects the coordinator's outcomes
// and shows the already-shipped import-failure toast for the failing ones.
//
// @coordinates-with: AndroidManifest.xml (the launcher activity), VReaderApp.kt
//   (the DI container), library/LibraryViewModel.kt, library/LibraryScreen.kt,
//   imports/ImportActivity.kt + imports/IncomingImportCoordinator.kt (#155)
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
import com.vreader.app.imports.IncomingImportOutcome
import com.vreader.app.search.SearchScreen
import com.vreader.app.ui.theme.VReaderTheme
import kotlinx.coroutines.launch
import vreader.contracts.BookFormat
import androidx.compose.runtime.LaunchedEffect

/**
 * The user-visible text for ONE inbound-import outcome (feature #155), or null when that outcome
 * is silent.
 *
 * RULE 51 — every string here is the ALREADY-SHIPPED SAF-import copy from
 * `LibraryViewModel.import`, reused verbatim; nothing new is introduced. Success is SILENT for a
 * new book AND for a duplicate, matching iOS. The designed in-progress / added / already-in-library
 * / unsupported treatments are BLOCKED on needs-design #2030 and are not invented here — which is
 * also why a too-large document reports the generic failure copy rather than a bespoke message.
 */
fun importFailureMessage(outcome: IncomingImportOutcome): String? = when (outcome) {
    is IncomingImportOutcome.Imported -> null
    is IncomingImportOutcome.Unsupported -> "Unsupported format: ${outcome.displayName}"
    IncomingImportOutcome.Unreadable -> "Couldn't open the file"
    IncomingImportOutcome.TooLarge, IncomingImportOutcome.Failed -> "Import failed"
}

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
                // feature #128 WI-7 — the search takeover open/closed flag (the SheetRoute saveable
                // precedent; a Boolean needs no custom Saver, so rememberSaveable survives rotation/death).
                var searchOpen by rememberSaveable { mutableStateOf(false) }

                val picker = rememberLauncherForActivityResult(
                    ActivityResultContracts.OpenDocument(),
                ) { uri -> uri?.let(viewModel::import) }

                LaunchedEffect(Unit) {
                    launch {
                        viewModel.events.collect { event ->
                            val message = when (event) {
                                is LibraryEvent.ImportFailed -> event.message
                                is LibraryEvent.CollectionOpFailed -> event.message
                            }
                            Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
                        }
                    }
                    // feature #155 — inbound "Open with VReader" / "Share to VReader" results. The
                    // coordinator buffers them, so an import that finished before this screen even
                    // existed (cold start from ImportActivity's hand-off) is still reported. A
                    // sibling collector, not a second LaunchedEffect: `collect` never returns, so
                    // the two must run concurrently.
                    launch {
                        container.incomingImportCoordinator.outcomes.collect { outcome ->
                            importFailureMessage(outcome)?.let { message ->
                                Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
                            }
                        }
                    }
                }

                // Route by the typed format (exhaustive — never open a format into the wrong host).
                // Shared by the library grid tap and the search result tap (both carry a typed format +
                // fingerprintKey).
                fun openBook(format: BookFormat, key: String) {
                    when (format) {
                        BookFormat.epub ->
                            startActivity(ReaderActivity.intent(this@MainActivity, key))
                        BookFormat.txt, BookFormat.md ->
                            // .md reuses the text reader host (#112): same decode/
                            // document/resume/chrome, MarkdownRenderer per chunk.
                            startActivity(TxtReaderActivity.intent(this@MainActivity, key))
                        BookFormat.pdf ->
                            // #115 — continuous-scroll PdfRenderer reader.
                            startActivity(PdfReaderActivity.intent(this@MainActivity, key))
                        BookFormat.azw3 ->
                            // #126 — foliate-js WebView reader (AZW3/MOBI/KF8).
                            startActivity(Azw3ReaderActivity.intent(this@MainActivity, key))
                    }
                }

                LibraryScreen(
                    state = state,
                    collections = collections,
                    selectedCollectionId = selectedCollectionId,
                    onSelectCollection = viewModel::selectCollection,
                    onAssignBook = { book -> sheetRoute = SheetRoute.Assign(book.id) },
                    onManageCollections = { sheetRoute = SheetRoute.Manage },
                    onOpenSearch = { searchOpen = true },
                    onOpenBook = { book -> openBook(book.originalFormat, book.id) },
                    // EPUBs are exposed by SAF providers under varied MIME types
                    // (epub+zip, octet-stream, generic); accept broadly and let
                    // BookImporter reject non-EPUBs by extension with a clear toast.
                    onImport = {
                        picker.launch(
                            arrayOf("application/epub+zip", "application/octet-stream", "*/*"),
                        )
                    },
                )

                // feature #128 WI-7 — the search takeover. Rendered OVER the library when open; fed by
                // the AppContainer's SearchViewModel (WI-6). Obtained through `viewModel(factory=…)` so it's
                // owned by the Activity's ViewModelStore — its viewModelScope is properly cleared on the
                // Activity's destroy (a raw `remember { … }` would leak the coroutine collector forever).
                if (searchOpen) {
                    val searchViewModel: com.vreader.app.search.SearchViewModel = viewModel(
                        key = "search",
                        factory = viewModelFactory { initializer { container.searchViewModel() } },
                    )
                    val searchState by searchViewModel.state.collectAsStateWithLifecycle()
                    SearchScreen(
                        state = searchState,
                        onQueryChange = searchViewModel::onQueryChange,
                        onCancel = { searchOpen = false },
                        onRecentTap = searchViewModel::onQueryChange,
                        onPickCollection = { id ->
                            // Filter the library to the chosen collection and close the takeover.
                            viewModel.selectCollection(id)
                            searchOpen = false
                        },
                        onOpenResult = { row ->
                            // Record the query as recent (WI-6) AND open the book, then dismiss.
                            searchViewModel.recordCurrentQuery()
                            openBook(row.book.originalFormat, row.book.fingerprintKey)
                            searchOpen = false
                        },
                    )
                }

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
