package com.vreader.app.reader.details

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.Book
import com.vreader.app.data.BookEntity
import com.vreader.app.data.CollectionEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat

/**
 * Feature #134 WI-1 — the pure [BookDetailsMapper] (`Book`→`BookDetailsUiModel`) plus the new
 * `collectionNamesForBook` join query (in-memory Room). Robolectric is only for the DB query half;
 * the mapper itself is a pure JVM function with NO Android/Compose deps (rule 50 boundary) — it is
 * exercised here without any Android context.
 */
@RunWith(RobolectricTestRunner::class)
class BookDetailsMapperTest {

    private val sha = "a".repeat(64)

    private fun book(
        format: BookFormat = BookFormat.epub,
        bytes: Long = 2_097_152L,
        localFilePath: String? = "/data/user/0/com.vreader.app/files/books/epub_${sha}_2097152",
        author: String? = "Ada Lovelace",
        title: String = "The Analytical Engine",
    ): Book = Book(
        fingerprintKey = "${format.name}:$sha:$bytes",
        title = title,
        originalFormat = format,
        contentSHA256 = sha,
        fileByteCount = bytes,
        localFilePath = localFilePath,
        sourceUri = null,
        addedAt = 1L,
        lastOpenedAt = null,
        author = author,
    )

    // --- size formatting (§size-formatting) ---

    @Test fun size_zeroIsUnknown() {
        assertEquals("Unknown", BookDetailsMapper.map(book(bytes = 0L), emptyList(), null).sizeLabel)
    }

    @Test fun size_negativeIsUnknown() {
        assertEquals("Unknown", BookDetailsMapper.map(book(bytes = -1L), emptyList(), null).sizeLabel)
    }

    @Test fun size_kbBoundary() {
        // 1_000 bytes crosses into KB with the SI (decimal) divisor (matches the .file count style).
        assertEquals("1 KB", BookDetailsMapper.map(book(bytes = 1_000L), emptyList(), null).sizeLabel)
    }

    @Test fun size_belowKbShownInBytes() {
        assertEquals("512 B", BookDetailsMapper.map(book(bytes = 512L), emptyList(), null).sizeLabel)
    }

    @Test fun size_mbBoundary() {
        assertEquals("1.0 MB", BookDetailsMapper.map(book(bytes = 1_000_000L), emptyList(), null).sizeLabel)
    }

    @Test fun size_longMaxDoesNotCrashAndIsNonEmpty() {
        val label = BookDetailsMapper.map(book(bytes = Long.MAX_VALUE), emptyList(), null).sizeLabel
        assertTrue("Long.MAX_VALUE size must be non-empty", label.isNotEmpty())
        assertFalse("Long.MAX_VALUE size must not be Unknown", label == "Unknown")
    }

    // --- fingerprint (§fingerprint) ---

    @Test fun fingerprintFull_isTheWholeKey() {
        val b = book()
        assertEquals(b.fingerprintKey, BookDetailsMapper.map(b, emptyList(), null).fingerprintFull)
    }

    @Test fun fingerprintDisplay_middleTruncatesLongKey() {
        val b = book() // key length = epub(4)+:+sha(64)+:+7 digits = well over 28
        val display = BookDetailsMapper.map(b, emptyList(), null).fingerprintDisplay
        assertEquals(b.fingerprintKey.take(14) + "…" + b.fingerprintKey.takeLast(8), display)
        assertTrue("must contain the ellipsis", display.contains("…"))
    }

    @Test fun fingerprintDisplay_shortKeyIsUntruncated() {
        // A synthetic short key (<= 28 chars) is shown verbatim — no ellipsis.
        val shortBook = book().copy(fingerprintKey = "txt:short")
        val display = BookDetailsMapper.map(shortBook, emptyList(), null).fingerprintDisplay
        assertEquals("txt:short", display)
        assertFalse(display.contains("…"))
    }

    // --- format label (per BookFormat, md -> Markdown) ---

    @Test fun formatLabel_perBookFormat() {
        assertEquals("EPUB", BookDetailsMapper.map(book(format = BookFormat.epub), emptyList(), null).formatLabel)
        assertEquals("PDF", BookDetailsMapper.map(book(format = BookFormat.pdf), emptyList(), null).formatLabel)
        assertEquals("TXT", BookDetailsMapper.map(book(format = BookFormat.txt), emptyList(), null).formatLabel)
        assertEquals("AZW3", BookDetailsMapper.map(book(format = BookFormat.azw3), emptyList(), null).formatLabel)
    }

    @Test fun formatLabel_mdIsMarkdown() {
        assertEquals("Markdown", BookDetailsMapper.map(book(format = BookFormat.md), emptyList(), null).formatLabel)
    }

    // --- location (§location) ---

    @Test fun location_relativeBooksLabel() {
        val b = book(localFilePath = "/data/user/0/com.vreader.app/files/books/epub_abc_123")
        assertEquals("Books/epub_abc_123", BookDetailsMapper.map(b, emptyList(), null).locationLabel)
    }

    @Test fun location_nullWhenNoLocalPath() {
        assertNull(BookDetailsMapper.map(book(localFilePath = null), emptyList(), null).locationLabel)
    }

    // --- author (omitted/null when absent) ---

    @Test fun author_passedThroughWhenPresent() {
        assertEquals("Ada Lovelace", BookDetailsMapper.map(book(author = "Ada Lovelace"), emptyList(), null).author)
    }

    @Test fun author_nullWhenAbsent() {
        assertNull(BookDetailsMapper.map(book(author = null), emptyList(), null).author)
    }

    // --- pages (PDF-only; non-null only when supplied) ---

    @Test fun pages_nullWhenNoCountSupplied() {
        assertNull(BookDetailsMapper.map(book(), emptyList(), null).pagesLabel)
    }

    @Test fun pages_labelWhenCountSupplied() {
        assertEquals("42", BookDetailsMapper.map(book(format = BookFormat.pdf), emptyList(), 42).pagesLabel)
    }

    // --- tags = collection names (empty when none) ---

    @Test fun tags_areTheSuppliedCollectionNames() {
        val model = BookDetailsMapper.map(book(), listOf("Fiction", "To Read"), null)
        assertEquals(listOf("Fiction", "To Read"), model.tags)
    }

    @Test fun tags_emptyWhenNoCollections() {
        assertEquals(emptyList<String>(), BookDetailsMapper.map(book(), emptyList(), null).tags)
    }

    // --- absence invariant: no year field on the model (data source doesn't exist) ---

    @Test fun model_hasNoYearProperty() {
        // Structural guard: reflection over the data class shows the year row is never present.
        val propNames = BookDetailsUiModel::class.members.map { it.name }.toSet()
        assertFalse("BookDetailsUiModel must not carry a year field", propNames.contains("year"))
        assertFalse("BookDetailsUiModel must not carry a coverPath field", propNames.contains("coverPath"))
    }

    // --- collectionNamesForBook join query (in-memory Room) ---

    private lateinit var db: VReaderDatabase
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val bookKey = "epub:${"b".repeat(64)}:2048"

    @Before fun setUpDb() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        runBlocking {
            db.bookDao().upsert(
                BookEntity(bookKey, "T", "epub", "b".repeat(64), 2048L, null, null, 1L, null),
            )
        }
    }

    @After fun tearDownDb() = db.close()

    @Test fun collectionNamesForBook_returnsOrderedNames() = runBlocking {
        val dao = db.collectionDao()
        // Insert out of chronological order to prove the ORDER BY c.createdAt ASC.
        dao.insertCollection(CollectionEntity("c2", "Later", "later", 2L))
        dao.insertCollection(CollectionEntity("c1", "Earlier", "earlier", 1L))
        dao.addMembership(bookKey, "c2")
        dao.addMembership(bookKey, "c1")
        assertEquals(listOf("Earlier", "Later"), dao.collectionNamesForBook(bookKey).first())
    }

    @Test fun collectionNamesForBook_emptyWhenNoMembership() = runBlocking {
        val dao = db.collectionDao()
        dao.insertCollection(CollectionEntity("c1", "Fiction", "fiction", 1L))
        // No membership added for bookKey.
        assertEquals(emptyList<String>(), dao.collectionNamesForBook(bookKey).first())
    }

    @Test fun collectionNamesForBook_onlyThisBooksCollections() = runBlocking {
        val dao = db.collectionDao()
        val otherKey = "epub:${"c".repeat(64)}:4096"
        db.bookDao().upsert(BookEntity(otherKey, "Other", "epub", "c".repeat(64), 4096L, null, null, 1L, null))
        dao.insertCollection(CollectionEntity("c1", "Mine", "mine", 1L))
        dao.insertCollection(CollectionEntity("c2", "Theirs", "theirs", 2L))
        dao.addMembership(bookKey, "c1")
        dao.addMembership(otherKey, "c2")
        assertEquals(listOf("Mine"), dao.collectionNamesForBook(bookKey).first())
    }
}
