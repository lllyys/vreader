package com.vreader.app.annotations

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.BookEntity
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import vreader.contracts.Identity
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupBookmark
import vreader.contracts.backup.BackupHighlight
import vreader.contracts.backup.BackupNote
import vreader.contracts.backup.BackupSchema

/**
 * Feature #165 WI-4 — the in-memory-Room rig the applier suites share.
 *
 * The parent `BookEntity` is ALWAYS seeded explicitly (the #135 FK-unseeded-parent defect class):
 * all three annotation tables carry a cascading foreign key to `books.fingerprintKey`, so a test
 * that forgets the parent fails for a reason that has nothing to do with what it is asserting.
 *
 * [splitStores] is what makes C-5b **layer 2** reachable. Layer 1 is a `findBook` pre-check and
 * layer 2 is the foreign-key mapping; a test that deletes the book *before* `apply` only ever
 * exercises layer 1. With `splitStores = true` the `LibraryRepository` reads a database that HAS
 * the book while the `AnnotationsRepository` writes one that does not — the delete-after-the-check
 * interleaving frozen into a deterministic fixture, so the insert really does raise SQLite's
 * foreign-key error and the applier's mapping is really the thing under test.
 */
internal class ApplierHarness(splitStores: Boolean = false) {

    val annotationsDb: VReaderDatabase = newDb()
    private val libraryDb: VReaderDatabase = if (splitStores) newDb() else annotationsDb

    val repo = AnnotationsRepository(annotationsDb.annotationDao())
    val library = LibraryRepository(libraryDb.bookDao(), libraryDb.readingPositionDao())
    val applier = AnnotationsImportApplier(repo, library)

    /** Seeds the parent row in EVERY store — the production shape (one database). */
    suspend fun seedBook(key: String = Fx.BOOK_A) {
        seedLibraryBook(key)
        if (libraryDb !== annotationsDb) seedAnnotationsParent(key)
    }

    /** Seeds the parent only where `findBook` looks — layer 1 passes, the insert still has no parent. */
    suspend fun seedLibraryBook(key: String = Fx.BOOK_A) = libraryDb.bookDao().upsert(bookEntity(key))

    /** Seeds the parent only where the annotations are written. */
    suspend fun seedAnnotationsParent(key: String = Fx.BOOK_A) =
        annotationsDb.bookDao().upsert(bookEntity(key))

    suspend fun deleteLibraryBook(key: String = Fx.BOOK_A) = libraryDb.bookDao().delete(key)

    // NOTE: do not reach for `setForeignKeyConstraintsEnabled(false)` to isolate the layers — Room's
    // current driver re-applies `PRAGMA foreign_keys = ON` when it acquires a connection, so the
    // call is silently ineffective (measured: the orphan probe still raised SQLITE_CONSTRAINT_
    // FOREIGNKEY). The layers are separated by WHERE the parent row lives instead: seed only the
    // library store to reach layer 2, only the annotations store to isolate layer 1.

    /** Every annotation row in the annotations store, id-sorted — the deep-equality snapshot. */
    suspend fun snapshot(): Snapshot = Snapshot(
        highlights = repo.allHighlights().sortedBy { it.id },
        notes = repo.allNotes().sortedBy { it.id },
        bookmarks = repo.allBookmarks().sortedBy { it.id },
    )

    data class Snapshot(
        val highlights: List<HighlightRecord>,
        val notes: List<NoteRecord>,
        val bookmarks: List<BookmarkRecord>,
    ) {
        val size: Int get() = highlights.size + notes.size + bookmarks.size
    }

    /**
     * An [ImportPreview] over an envelope the test built by hand — for the apply-side cases that
     * need a row the READER would have refused (a corrupt inner locator, a foreign book). The
     * counts mirror the envelope, which is the reader's own post-collapse contract.
     */
    fun previewOf(envelope: BackupAnnotationsEnvelope, bookKey: String = Fx.BOOK_A) = ImportPreview(
        fileName = "annotations.json",
        bookKey = bookKey,
        bookTitle = "A Book",
        highlights = envelope.highlights.size,
        notes = envelope.notes.size,
        bookmarks = envelope.bookmarks.size,
        skipped = 0,
        sample = emptyList(),
        envelope = envelope,
    )

    fun close() {
        annotationsDb.close()
        if (libraryDb !== annotationsDb) libraryDb.close()
    }

    private fun newDb(): VReaderDatabase = Room.inMemoryDatabaseBuilder(
        ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java,
    ).build()

    private fun bookEntity(key: String): BookEntity {
        val p = requireNotNull(Identity.parseCanonicalKey(key)) { "bad fixture key $key" }
        return BookEntity(
            fingerprintKey = key, title = "A Book", originalFormat = p.format.name,
            contentSHA256 = p.contentSHA256, fileByteCount = p.fileByteCount,
            localFilePath = null, sourceUri = null, addedAt = 1L, lastOpenedAt = null,
        )
    }

    companion object {
        /** The typed envelope with the contract's own argument order made explicit. */
        fun env(
            highlights: List<BackupHighlight> = emptyList(),
            notes: List<BackupNote> = emptyList(),
            bookmarks: List<BackupBookmark> = emptyList(),
        ) = BackupAnnotationsEnvelope(
            schemaVersion = BackupSchema.CURRENT_SCHEMA_VERSION,
            highlights = highlights,
            bookmarks = bookmarks,
            notes = notes,
        )

        /** The `profileKey` a row at [charOffset] in [bookKey] will carry once persisted. */
        fun profileKeyAt(charOffset: Int, bookKey: String = Fx.BOOK_A) =
            profileKeyFor(bookKey, Fx.locator(bookKey, charOffset = charOffset))
    }
}
