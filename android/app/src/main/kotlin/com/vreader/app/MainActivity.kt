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
import com.vreader.app.library.LibraryEvent
import com.vreader.app.library.LibraryScreen
import com.vreader.app.library.LibraryViewModel
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
            initializer { LibraryViewModel(container.repository, container.importer, contentResolver) }
        }

        setContent {
            VReaderTheme {
                val viewModel: LibraryViewModel = viewModel(factory = factory)
                val state by viewModel.uiState.collectAsStateWithLifecycle()

                val picker = rememberLauncherForActivityResult(
                    ActivityResultContracts.OpenDocument(),
                ) { uri -> uri?.let(viewModel::import) }

                LaunchedEffect(Unit) {
                    viewModel.events.collect { event ->
                        if (event is LibraryEvent.ImportFailed) {
                            Toast.makeText(this@MainActivity, event.message, Toast.LENGTH_SHORT).show()
                        }
                    }
                }

                LibraryScreen(
                    state = state,
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
                                Toast.makeText(
                                    this@MainActivity,
                                    "${book.format} reading isn't available yet",
                                    Toast.LENGTH_SHORT,
                                ).show()
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
            }
        }
    }
}
