// Purpose: Library screen state holder — feature #106 WI-8 (implements the committed
// design dev-docs/designs/vreader-fidelity-v1/vreader-library.jsx). Exposes the
// imported books as a StateFlow<LibraryUiState> (the iOS LibraryViewModel analog) and
// drives SAF import through the WI-4 BookImporter. Constructor-injected
// (LibraryRepository / BookImporter / ContentResolver) so it's testable at the
// boundary (rule 50 §5).
package com.vreader.app.library

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vreader.app.data.Book
import com.vreader.app.data.BookImporter
import com.vreader.app.data.ImportException
import com.vreader.app.data.LibraryRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A book as the Library grid/list renders it (the design's BOOK shape, available fields). */
data class LibraryBook(
    val id: String,           // fingerprintKey
    val title: String,
    val format: String,       // upper-case chip, e.g. "EPUB"
    val addedAt: Long,
    val lastOpenedAt: Long?,
)

/** Immutable Library UI state — a pure function of the persisted library. */
data class LibraryUiState(
    val loading: Boolean = true,
    val books: List<LibraryBook> = emptyList(),
) {
    val readingCount: Int get() = books.count { it.lastOpenedAt != null }
}

/** One-shot events (e.g. an import error toast) the screen consumes. */
sealed interface LibraryEvent {
    data class ImportFailed(val message: String) : LibraryEvent
}

class LibraryViewModel(
    private val repository: LibraryRepository,
    private val importer: BookImporter,
    private val resolver: ContentResolver,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {

    val uiState: StateFlow<LibraryUiState> = repository.observeLibrary()
        .map { books -> LibraryUiState(loading = false, books = books.map(::toUi)) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LibraryUiState(loading = true))

    // A Channel (one consumer) rather than a non-replaying SharedFlow: an import that
    // finishes during the LaunchedEffect collector gap around a config change is
    // buffered and delivered when collection resumes — the toast isn't dropped.
    private val _events = Channel<LibraryEvent>(Channel.BUFFERED)
    val events: Flow<LibraryEvent> = _events.receiveAsFlow()

    /** Import the SAF-picked document: resolve its name + stream, hand to the importer. */
    fun import(uri: Uri) {
        viewModelScope.launch {
            try {
                // The SAF cursor query + stream open can block on a cloud-backed
                // provider AND can throw (SecurityException / FileNotFound / etc.);
                // keep them off the main thread and inside the failure boundary.
                val (name, input) = withContext(ioDispatcher) {
                    val display = resolver.displayName(uri) ?: uri.lastPathSegment ?: "book"
                    display to resolver.openInputStream(uri)
                }
                if (input == null) {
                    _events.trySend(LibraryEvent.ImportFailed("Couldn't open the file"))
                    return@launch
                }
                importer.importStream(uri.toString(), name, input)
            } catch (e: CancellationException) {
                throw e   // honor structured cancellation — not a real import failure
            } catch (e: ImportException.UnsupportedFormat) {
                _events.trySend(LibraryEvent.ImportFailed("Unsupported format: ${e.name}"))
            } catch (e: Exception) {
                _events.trySend(LibraryEvent.ImportFailed("Import failed"))
            }
        }
    }

    private fun toUi(book: Book): LibraryBook = LibraryBook(
        id = book.fingerprintKey,
        title = book.title,
        format = book.originalFormat.name.uppercase(),
        addedAt = book.addedAt,
        lastOpenedAt = book.lastOpenedAt,
    )
}

/** Queries the SAF content provider for the document's display name. */
private fun ContentResolver.displayName(uri: Uri): String? =
    runCatching {
        query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            } else {
                null
            }
        }
    }.getOrNull()
