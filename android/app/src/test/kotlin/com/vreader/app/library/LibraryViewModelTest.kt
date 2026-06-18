package com.vreader.app.library

import android.content.Context
import android.net.Uri
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.Book
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import vreader.contracts.BookFormat
import java.io.ByteArrayInputStream
import java.io.File

/**
 * LibraryViewModel maps the Room library to UI state and drives SAF import
 * (feature #106 WI-8). Robolectric for Room + the shadow ContentResolver. Uses
 * real-time `runBlocking` + `withTimeout` rather than virtual time, because Room's
 * Flow emits on its own executor (not the test scheduler).
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class LibraryViewModelTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var db: VReaderDatabase
    private lateinit var repository: LibraryRepository
    private lateinit var viewModel: LibraryViewModel

    @Before
    fun setUp() {
        Dispatchers.setMain(Dispatchers.Unconfined)
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        repository = LibraryRepository(db.bookDao(), db.readingPositionDao())
        val importer = BookImporter(
            File(context.cacheDir, "books-${System.nanoTime()}"), repository, Dispatchers.Unconfined,
        )
        viewModel = LibraryViewModel(repository, importer, context.contentResolver, Dispatchers.Unconfined)
    }

    @After
    fun tearDown() {
        db.close()
        Dispatchers.resetMain()
    }

    private fun book(title: String, key: String) = Book(
        fingerprintKey = key, title = title, originalFormat = BookFormat.epub,
        contentSHA256 = key.substringAfter(":").substringBefore(":"), fileByteCount = 10, addedAt = 1L,
    )

    @Test
    fun uiState_reflectsRepositoryBooks() = runBlocking {
        repository.upsertBook(book("Moby-Dick", "epub:${"a".repeat(64)}:10"))
        val state = withTimeout(5_000) { viewModel.uiState.first { it.books.isNotEmpty() } }
        assertEquals(1, state.books.size)
        assertEquals("Moby-Dick", state.books[0].title)
        assertEquals("EPUB", state.books[0].format)
        assertTrue(!state.loading)
    }

    @Test
    fun import_unsupportedExtension_emitsFailure() = runBlocking {
        val uri = Uri.parse("content://docs/notes.xyz")
        Shadows.shadowOf(context.contentResolver)
            .registerInputStream(uri, ByteArrayInputStream(ByteArray(16)))
        val event = withTimeout(5_000) {
            val collector = async { viewModel.events.first() }
            yield()   // let the collector subscribe before we emit
            viewModel.import(uri)
            collector.await()
        }
        assertTrue("an unsupported file surfaces ImportFailed", event is LibraryEvent.ImportFailed)
    }

    @Test
    fun import_unopenableUri_emitsFailure() = runBlocking {
        // No stream registered for this URI → openInputStream returns null → the
        // import surfaces a typed failure event rather than crashing the launch.
        val uri = Uri.parse("content://docs/missing.epub")
        val event = withTimeout(5_000) {
            val collector = async { viewModel.events.first() }
            yield()
            viewModel.import(uri)
            collector.await()
        }
        assertTrue("an unopenable URI surfaces ImportFailed", event is LibraryEvent.ImportFailed)
    }

    @Test
    fun import_epub_addsToLibrary() = runBlocking {
        val uri = Uri.parse("content://docs/Moby.epub")
        Shadows.shadowOf(context.contentResolver)
            .registerInputStream(uri, ByteArrayInputStream(ByteArray(2048) { it.toByte() }))
        viewModel.import(uri)
        val state = withTimeout(5_000) { viewModel.uiState.first { it.books.isNotEmpty() } }
        assertEquals(1, state.books.size)
        assertEquals("Moby", state.books[0].title)
        assertEquals("EPUB", state.books[0].format)
    }
}
