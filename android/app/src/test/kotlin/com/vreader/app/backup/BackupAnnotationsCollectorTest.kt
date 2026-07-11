package com.vreader.app.backup

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.backup.archive.BackupArchiveReader
import com.vreader.app.backup.archive.BackupArchiveWriter
import com.vreader.app.data.Book
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import vreader.contracts.Locator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryEntry
import vreader.contracts.backup.BackupLibraryManifestEnvelope
import vreader.contracts.backup.BackupMetadata
import vreader.contracts.backup.BackupSchema
import java.io.File
import java.time.Instant

/**
 * Feature #132 WI-8 — annotations.json backup + restore (box B remainder). BackupCollector emits a
 * deterministic `annotations.json` (a BackupAnnotationsEnvelope of highlights + notes + bookmarks,
 * filtered to the backed-up books + sorted by (bookFingerprintKey, id) → byte-stable, UUID preserved);
 * RestoreImporter decodes it and calls WI-6b's UUID-preserving restore seam, scoped to the manifest's
 * in-selection books. CRITICAL: `locatorJSON` is the PLAIN serialized `Locator` (`BackupJson.encode`),
 * matching iOS `encoder.encode(locator)` + `contracts/vectors/backup-sections.json` + WI-6b's plain
 * decode — NOT `Locator.canonicalJson()`. In-memory Room (Robolectric).
 */
@RunWith(RobolectricTestRunner::class)
class BackupAnnotationsCollectorTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private lateinit var annotations: AnnotationsRepository
    private val readable = mutableSetOf<String>()
    private val now = Instant.parse("2026-07-11T12:00:00Z")

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        annotations = AnnotationsRepository(db.annotationDao())
    }

    @After fun tearDown() { db.close() }

    // ── seeding ──────────────────────────────────────────────

    private suspend fun seedBook(seed: Char, bytes: Long = 2048L): String {
        val sha = seed.toString().repeat(64)
        val key = Identity.canonicalKey(BookFormat.epub.name, sha, bytes)
        val path = "/data/$seed.epub"; readable += path
        repo.upsertBook(Book(key, "Book-$seed", BookFormat.epub, sha, bytes, path, null, 1000L, null))
        return key
    }

    /** A plain Locator for [key] with a distinguishing char offset (so different rows get distinct anchors). */
    private fun locatorFor(key: String, offset: Int): Locator {
        val (sha, bytes) = shaBytesOf(key)
        return Locator(contentSHA256 = sha, fileByteCount = bytes, format = "epub", href = "c.xhtml", charOffsetUTF16 = offset)
    }

    private fun shaBytesOf(key: String): Pair<String, Long> {
        val parts = key.split(":")  // "epub:<sha>:<bytes>"
        return parts[1] to parts[2].toLong()
    }

    private fun collector() =
        BackupCollector(repo, fileChecker = { it in readable }, annotationsRepository = annotations)

    private suspend fun collect() = collector().collect("Dev", "0.14.0", "bid", now)

    private suspend fun annotationsJson(): String =
        collect().sections[BackupCollector.ANNOTATIONS_SECTION]!!

    private fun importer() =
        BookImporter(File(context.cacheDir, "books-${System.nanoTime()}"), repo, Dispatchers.Unconfined)

    private fun restorer() = RestoreImporter(
        importer(), repo, fetchBlob = { throw IllegalStateException("no blobs in this test") },
        ioDispatcher = Dispatchers.Unconfined, annotationsRepository = annotations,
    )

    /** A *.vreader.zip reader carrying [env] (nullable) as the annotations section + a manifest listing
     *  [manifestKeys] (which scopes the annotation restore's allowed books). */
    private fun readerFor(env: BackupAnnotationsEnvelope?, manifestKeys: Set<String>): BackupArchiveReader {
        val sections = buildMap {
            if (env != null) put(BackupCollector.ANNOTATIONS_SECTION, BackupJson.encode(env))
        }
        val entries = manifestKeys.map { key ->
            val (sha, bytes) = shaBytesOf(key)
            BackupLibraryEntry(
                fingerprintKey = key, format = "epub", sha256 = sha, byteCount = bytes,
                originalExtension = "epub", title = "Book", addedAt = now,
                blobPath = "VReader/books/epub/$sha",
            )
        }
        val manifest = BackupLibraryManifestEnvelope(BackupSchema.MANIFEST_SCHEMA_VERSION, entries)
        val meta = BackupMetadata("bid", now, "Dev", "0.14.0", bookCount = entries.size, totalSizeBytes = 0L)
        return BackupArchiveReader.read(BackupArchiveWriter.write(meta, manifest, sections))
    }

    /** Wipe the whole annotation store (fresh restore-target for round-trips). */
    private suspend fun clearAnnotations() {
        for (h in annotations.allHighlights()) annotations.removeHighlight(h.id)
        for (n in annotations.allNotes()) annotations.removeNote(n.id)
        for (b in annotations.allBookmarks()) annotations.removeBookmark(b.id)
    }

    // ── collect ──────────────────────────────────────────────

    @Test fun collect_emitsPlainLocatorJson_notCanonical() = runTest {
        val a = seedBook('a')
        annotations.addHighlight(a, AnnotationColor.DEFAULT, "hi", locatorFor(a, 949), anchor = null)

        val env = BackupJson.decode<BackupAnnotationsEnvelope>(annotationsJson())
        assertEquals(1, env.highlights.size)
        val locJson = env.highlights[0].locatorJSON

        // (1) it decodes back as a PLAIN Locator (round-trippable, WI-6b-decodable).
        val decoded = BackupJson.decode<Locator>(locJson)
        assertEquals(a, decoded.fingerprintKey)
        assertEquals(949, decoded.charOffsetUTF16)

        // (2) it is NOT the canonical form — canonicalJson emits flattened dotted keys, plain does not.
        val canonical = locatorFor(a, 949).canonicalJson()
        assertFalse("locatorJSON must be plain, not canonical", locJson == canonical)
        assertTrue("plain Locator JSON carries the object field 'charOffsetUTF16'", locJson.contains("charOffsetUTF16"))
    }

    @Test fun collect_isByteStable_sortedAndDeterministic() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        // Insert jumbled across two books; the section must serialize identically each time + sorted.
        annotations.addHighlight(b, AnnotationColor.DEFAULT, "hb1", locatorFor(b, 20), anchor = null)
        annotations.addHighlight(a, AnnotationColor.DEFAULT, "ha1", locatorFor(a, 10), anchor = null)
        annotations.addNote(a, "na", locatorFor(a, 30))
        annotations.addNote(b, "nb", locatorFor(b, 40))

        val first = annotationsJson()
        val second = annotationsJson()
        assertEquals("annotations.json is byte-stable across repeat collects", first, second)

        val env = BackupJson.decode<BackupAnnotationsEnvelope>(first)
        assertEquals(2, env.highlights.size)
        val keysInOrder = env.highlights.map { it.bookFingerprintKey }
        assertEquals("highlights sorted by bookFingerprintKey", keysInOrder.sorted(), keysInOrder)
    }

    @Test fun collect_filtersToManifestBooks() = runTest {
        val a = seedBook('a')
        val throwaway = seedBook('z', 4096L)
        annotations.addHighlight(a, AnnotationColor.DEFAULT, "kept", locatorFor(a, 1), anchor = null)
        annotations.addHighlight(throwaway, AnnotationColor.DEFAULT, "dropped", locatorFor(throwaway, 2), anchor = null)

        // Remove the throwaway book from the library so it isn't a collected manifest book.
        repo.deleteBook(throwaway)
        readable.remove("/data/z.epub")

        val env = BackupJson.decode<BackupAnnotationsEnvelope>(annotationsJson())
        assertEquals("only the manifest book's highlight survives", 1, env.highlights.size)
        assertEquals(a, env.highlights[0].bookFingerprintKey)
    }

    @Test fun collect_populatesBookmarks() = runTest {
        val a = seedBook('a')
        annotations.addBookmark(a, "Chapter 1", locatorFor(a, 5))
        val env = BackupJson.decode<BackupAnnotationsEnvelope>(annotationsJson())
        assertEquals(1, env.bookmarks.size)
        assertEquals("Chapter 1", env.bookmarks[0].title)
        assertEquals(a, BackupJson.decode<Locator>(env.bookmarks[0].locatorJSON).fingerprintKey)
    }

    @Test fun collect_emptyStore_emitsEmptyEnvelope_orOmitted() = runTest {
        seedBook('a')  // a book but no annotations
        val json = collect().sections[BackupCollector.ANNOTATIONS_SECTION]
        // If present it must be a valid empty envelope; if omitted, that is also legal (no annotations).
        if (json != null) {
            val env = BackupJson.decode<BackupAnnotationsEnvelope>(json)
            assertTrue(env.highlights.isEmpty() && env.notes.isEmpty() && env.bookmarks.isEmpty())
        }
    }

    @Test fun collect_includesSectionInTotalSize() = runTest {
        val a = seedBook('a')
        annotations.addHighlight(a, AnnotationColor.DEFAULT, "hi", locatorFor(a, 1), anchor = null)
        val collected = collect()
        val section = collected.sections[BackupCollector.ANNOTATIONS_SECTION]!!
        val sectionBytes = section.toByteArray(Charsets.UTF_8).size.toLong()
        assertTrue("totalSize includes the annotations section", collected.metadata.totalSizeBytes >= sectionBytes)
    }

    // ── round-trip (restore) ─────────────────────────────────

    @Test fun roundTrip_restoresHighlightsNotesBookmarks_preservingUuids() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        val h1 = annotations.addHighlight(a, AnnotationColor.DEFAULT, "hi-a", locatorFor(a, 10), anchor = null)
        val n1 = annotations.addNote(b, "note-b", locatorFor(b, 20))
        val bk1 = annotations.addBookmark(a, "bm-a", locatorFor(a, 30))

        val env = BackupJson.decode<BackupAnnotationsEnvelope>(annotationsJson())
        clearAnnotations()
        assertTrue(annotations.allHighlights().isEmpty())

        val result = restorer().restore(readerFor(env, setOf(a, b)))
        assertEquals("1 highlight + 1 note + 1 bookmark applied", 3, result.annotationsRestored)

        val restoredH = annotations.findHighlight(h1.id)
        assertNotNull("highlight restored under its original UUID", restoredH)
        assertEquals(h1.id, restoredH!!.id)
        assertEquals(1, annotations.allNotes().size)
        assertEquals(n1.id, annotations.allNotes()[0].id)
        assertEquals(1, annotations.allBookmarks().size)
        assertEquals(bk1.id, annotations.allBookmarks()[0].id)
    }

    @Test fun roundTrip_isIdempotent_secondRestoreAppliesZero() = runTest {
        val a = seedBook('a')
        annotations.addHighlight(a, AnnotationColor.DEFAULT, "hi", locatorFor(a, 10), anchor = null)
        annotations.addNote(a, "note", locatorFor(a, 20))
        val env = BackupJson.decode<BackupAnnotationsEnvelope>(annotationsJson())
        clearAnnotations()

        val first = restorer().restore(readerFor(env, setOf(a)))
        assertEquals(2, first.annotationsRestored)  // 1 highlight + 1 note
        val second = restorer().restore(readerFor(env, setOf(a)))
        assertEquals("repeat restore applies zero", 0, second.annotationsRestored)
        assertEquals(1, annotations.allHighlights().size)
        assertEquals(1, annotations.allNotes().size)
    }

    @Test fun restore_filtersToManifestScope_dropsOutOfScope() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        annotations.addHighlight(a, AnnotationColor.DEFAULT, "hi-a", locatorFor(a, 10), anchor = null)
        annotations.addHighlight(b, AnnotationColor.DEFAULT, "hi-b", locatorFor(b, 20), anchor = null)
        val env = BackupJson.decode<BackupAnnotationsEnvelope>(annotationsJson())
        clearAnnotations()

        // Manifest lists only book a → book b's annotation is out of scope (dropped, not applied).
        val result = restorer().restore(readerFor(env, setOf(a)))
        assertEquals("only book a's highlight applied", 1, result.annotationsRestored)
        assertEquals(1, annotations.allHighlights().size)
        assertEquals(a, annotations.allHighlights()[0].bookKey)
    }

    @Test fun restore_absentAnnotationsSection_isNoOp_noCrash() = runTest {
        val a = seedBook('a')
        val result = restorer().restore(readerFor(null, setOf(a)))  // pre-#132 backup: no annotations.json
        assertEquals(0, result.annotationsRestored)
        assertTrue(annotations.allHighlights().isEmpty())
    }

    @Test fun restore_malformedRow_dropped_notApplied() = runTest {
        val a = seedBook('a')
        annotations.addHighlight(a, AnnotationColor.DEFAULT, "good", locatorFor(a, 10), anchor = null)
        annotations.addNote(a, "goodnote", locatorFor(a, 20))
        val env = BackupJson.decode<BackupAnnotationsEnvelope>(annotationsJson())
        val poisoned = env.copy(notes = env.notes.map { it.copy(locatorJSON = "{not-valid-json") })
        clearAnnotations()

        val result = restorer().restore(readerFor(poisoned, setOf(a)))
        // 1 highlight applied; the corrupt note fails (not applied) → only the highlight counts.
        assertEquals(1, result.annotationsRestored)
        assertEquals(1, annotations.allHighlights().size)
        assertTrue(annotations.allNotes().isEmpty())
    }
}
