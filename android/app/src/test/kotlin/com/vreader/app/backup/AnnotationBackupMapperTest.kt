package com.vreader.app.backup

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import vreader.contracts.Locator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupBookmark
import vreader.contracts.backup.BackupHighlight
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupNote
import vreader.contracts.backup.BackupSchema
import java.time.Instant

/**
 * Feature #165 WI-1 — `AnnotationBackupMapper` is the SINGLE record→wire mapping for the
 * `annotations.json` contract section, extracted out of `BackupCollector`'s privates so the
 * #165 exporter and the backup collector cannot carry two copies that drift.
 *
 * The load-bearing test is [collector_annotationsSection_isByteIdenticalToGolden]: GOLDEN_SECTION
 * is the VERBATIM `annotations.json` text the collector emitted BEFORE the extraction (captured by
 * running this test against the pre-extraction `BackupCollector`). It pins the bytes, not merely the
 * assertions — a reordered key set, a dropped field, or a different timestamp/number format all
 * break it even though every semantic assertion elsewhere would stay green.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationBackupMapperTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var db: VReaderDatabase
    private lateinit var library: LibraryRepository
    private lateinit var annotations: AnnotationsRepository
    private val readable = mutableSetOf<String>()
    private val now = Instant.parse("2026-08-05T09:00:00Z")

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        library = LibraryRepository(db.bookDao(), db.readingPositionDao())
        annotations = AnnotationsRepository(db.annotationDao())
    }

    @After fun tearDown() { db.close() }

    // ── fixtures (fully deterministic: fixed UUIDs, fixed epoch-millis) ──────────

    private val keyA = Identity.canonicalKey(BookFormat.epub.name, "a".repeat(64), 2048L)
    private val keyB = Identity.canonicalKey(BookFormat.txt.name, "b".repeat(64), 4096L)

    private fun locator(key: String, offset: Int): Locator {
        val parts = key.split(":")
        return Locator(
            contentSHA256 = parts[1], fileByteCount = parts[2].toLong(), format = parts[0],
            href = "c.xhtml", charOffsetUTF16 = offset,
        )
    }

    /** Highlights deliberately supplied OUT of (bookKey, id) order, with a CJK selection, a null
     *  note (omitted on the wire) and a non-null note (present). */
    private fun highlights() = listOf(
        com.vreader.app.annotations.HighlightRecord(
            id = "22222222-2222-2222-2222-222222222222", bookKey = keyB,
            color = com.vreader.app.annotations.AnnotationColor.DEFAULT,
            selectedText = "选中的文本", note = null,
            locator = locator(keyB, 949), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_060_000L,
        ),
        com.vreader.app.annotations.HighlightRecord(
            id = "11111111-1111-1111-1111-111111111111", bookKey = keyA,
            color = com.vreader.app.annotations.AnnotationColor.DEFAULT,
            selectedText = "hello", note = "a note",
            locator = locator(keyA, 10), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
    )

    private fun notes() = listOf(
        com.vreader.app.annotations.NoteRecord(
            id = "44444444-4444-4444-4444-444444444444", bookKey = keyA,
            content = "second", locator = locator(keyA, 40), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
        com.vreader.app.annotations.NoteRecord(
            id = "33333333-3333-3333-3333-333333333333", bookKey = keyA,
            content = "first", locator = locator(keyA, 30), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
    )

    private fun bookmarks() = listOf(
        com.vreader.app.annotations.BookmarkRecord(
            id = "55555555-5555-5555-5555-555555555555", bookKey = keyA,
            title = "Chapter 1", locator = locator(keyA, 5),
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
        com.vreader.app.annotations.BookmarkRecord(
            id = "66666666-6666-6666-6666-666666666666", bookKey = keyB,
            title = null, locator = locator(keyB, 6),
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
    )

    /** Seeds the two books + the fixture rows through the UUID-and-timestamp-PRESERVING restore
     *  seam, so the collector reads back exactly the fixture ids/instants (the create methods would
     *  mint fresh UUIDs and stamp `now`, which no golden could pin). */
    private suspend fun seed() {
        library.upsertBook(Book(keyA, "Book A", BookFormat.epub, "a".repeat(64), 2048L, "/data/a.epub", null, 1000L, null))
        library.upsertBook(Book(keyB, "Book B", BookFormat.txt, "b".repeat(64), 4096L, "/data/b.txt", null, 1000L, null))
        readable += "/data/a.epub"; readable += "/data/b.txt"
        annotations.restoreAnnotations(
            BackupAnnotationsEnvelope(
                BackupSchema.CURRENT_SCHEMA_VERSION,
                highlights = highlights().map { wireHighlight(it) },
                bookmarks = bookmarks().map { wireBookmark(it) },
                notes = notes().map { wireNote(it) },
            ),
            allowedBookKeys = setOf(keyA, keyB),
        )
    }

    // Local, INDEPENDENT record→wire builders for SEEDING only. Deliberately not the production
    // mapper: seeding through the thing under test would make the golden self-fulfilling.
    private fun wireHighlight(r: com.vreader.app.annotations.HighlightRecord) = BackupHighlight(
        highlightId = r.id, bookFingerprintKey = r.bookKey,
        locatorJSON = BackupJson.encode(r.locator), selectedText = r.selectedText,
        color = r.color.key, note = r.note,
        createdAt = Instant.ofEpochMilli(r.createdAt), updatedAt = Instant.ofEpochMilli(r.updatedAt),
    )

    private fun wireNote(r: com.vreader.app.annotations.NoteRecord) = BackupNote(
        annotationId = r.id, bookFingerprintKey = r.bookKey,
        locatorJSON = BackupJson.encode(r.locator), content = r.content,
        createdAt = Instant.ofEpochMilli(r.createdAt), updatedAt = Instant.ofEpochMilli(r.updatedAt),
    )

    private fun wireBookmark(r: com.vreader.app.annotations.BookmarkRecord) = BackupBookmark(
        bookmarkId = r.id, bookFingerprintKey = r.bookKey,
        locatorJSON = BackupJson.encode(r.locator), title = r.title,
        createdAt = Instant.ofEpochMilli(r.createdAt), updatedAt = Instant.ofEpochMilli(r.updatedAt),
    )

    private suspend fun collectAnnotationsSection(): String {
        val collector = BackupCollector(
            library, fileChecker = { it in readable }, annotationsRepository = annotations,
        )
        return collector.collect("Dev", "0.0.0", "bid", now)
            .sections[BackupCollector.ANNOTATIONS_SECTION]!!
    }

    // ── the byte-identity pin ────────────────────────────────────────────────────

    @Test fun collector_annotationsSection_isByteIdenticalToGolden() = runTest {
        seed()
        assertEquals(
            "annotations.json must be BYTE-identical to the pre-extraction collector output",
            GOLDEN_SECTION,
            collectAnnotationsSection(),
        )
    }

    /** The single-copy proof: the mapper's own wire text over the SAME records is byte-identical to
     *  what the collector emits — so the #165 exporter reusing [AnnotationBackupMapper] cannot drift
     *  from the backup path. */
    @Test fun mapperJson_isByteIdenticalToCollectorSection() = runTest {
        seed()
        assertEquals(
            AnnotationBackupMapper.json(highlights(), notes(), bookmarks()),
            collectAnnotationsSection(),
        )
    }

    // ── mapper unit surface ─────────────────────────────────────────────────────

    @Test fun envelope_sortsEveryKindBy_bookKeyThenId() {
        // Same book, ids supplied descending → must come back ascending by id.
        val h1 = highlights()[1]                                   // keyA, id 1111…
        val h2 = h1.copy(id = "99999999-9999-9999-9999-999999999999")
        val env = AnnotationBackupMapper.envelope(
            highlights = listOf(h2, h1), notes = notes(), bookmarks = bookmarks(),
        )
        assertEquals(listOf(h1.id, h2.id), env.highlights.map { it.highlightId })
        // notes()/bookmarks() are supplied out of order too.
        assertEquals(
            listOf("33333333-3333-3333-3333-333333333333", "44444444-4444-4444-4444-444444444444"),
            env.notes.map { it.annotationId },
        )
        assertEquals(
            listOf("55555555-5555-5555-5555-555555555555", "66666666-6666-6666-6666-666666666666"),
            env.bookmarks.map { it.bookmarkId },
        )
        assertEquals(BackupSchema.CURRENT_SCHEMA_VERSION, env.schemaVersion)
    }

    @Test fun envelope_highlight_mapsEveryWireField() {
        val r = highlights()[1]
        val w = AnnotationBackupMapper.envelope(listOf(r), emptyList(), emptyList()).highlights.single()
        assertEquals(r.id, w.highlightId)
        assertEquals(r.bookKey, w.bookFingerprintKey)
        assertEquals(BackupJson.encode(r.locator), w.locatorJSON)
        assertEquals(r.selectedText, w.selectedText)
        assertEquals(r.color.key, w.color)
        assertEquals(r.note, w.note)
        assertEquals(Instant.ofEpochMilli(r.createdAt), w.createdAt)
        assertEquals(Instant.ofEpochMilli(r.updatedAt), w.updatedAt)
    }

    @Test fun envelope_note_mapsEveryWireField() {
        val r = notes()[1]
        val w = AnnotationBackupMapper.envelope(emptyList(), listOf(r), emptyList()).notes.single()
        assertEquals(r.id, w.annotationId)
        assertEquals(r.bookKey, w.bookFingerprintKey)
        assertEquals(BackupJson.encode(r.locator), w.locatorJSON)
        assertEquals(r.content, w.content)
        assertEquals(Instant.ofEpochMilli(r.createdAt), w.createdAt)
        assertEquals(Instant.ofEpochMilli(r.updatedAt), w.updatedAt)
    }

    @Test fun envelope_bookmark_mapsEveryWireField() {
        val r = bookmarks()[0]
        val w = AnnotationBackupMapper.envelope(emptyList(), emptyList(), listOf(r)).bookmarks.single()
        assertEquals(r.id, w.bookmarkId)
        assertEquals(r.bookKey, w.bookFingerprintKey)
        assertEquals(BackupJson.encode(r.locator), w.locatorJSON)
        assertEquals(r.title, w.title)
        assertEquals(Instant.ofEpochMilli(r.createdAt), w.createdAt)
        assertEquals(Instant.ofEpochMilli(r.updatedAt), w.updatedAt)
    }

    /** `locatorJSON` is the PLAIN `Locator` (W14) — `canonicalJson()`'s flattened dotted keys are
     *  not `Locator`-decodable, so shipping them would break every restore. */
    @Test fun envelope_locatorJson_isPlainNotCanonical() {
        val r = highlights()[1]
        val w = AnnotationBackupMapper.envelope(listOf(r), emptyList(), emptyList()).highlights.single()
        assertEquals(r.locator, BackupJson.decode<Locator>(w.locatorJSON))
        assertNotEquals("locatorJSON must be plain, never canonical", r.locator.canonicalJson(), w.locatorJSON)
    }

    /** `explicitNulls=false` (Swift parity): a null highlight note / bookmark title is OMITTED,
     *  never emitted as `null` — a wire-shape detail the byte golden also pins. */
    @Test fun json_nullNoteAndTitle_areOmittedNotNull() {
        val json = AnnotationBackupMapper.json(
            highlights = listOf(highlights()[0]),          // note = null
            notes = emptyList(),
            bookmarks = listOf(bookmarks()[1]),            // title = null
        )
        assertFalse("null optionals must be omitted", json.contains("null"))
        assertFalse(json.contains("\"note\""))
        assertFalse(json.contains("\"title\""))
        assertTrue("CJK selection survives unescaped", json.contains("选中的文本"))
    }

    /** Timestamps are epoch-millis → `Instant` → ISO8601 UTC at SECOND precision (sub-second
     *  truncated). Pins the serialisation format, not just the value. */
    @Test fun json_timestamps_areIso8601SecondPrecision() {
        val r = notes()[1].copy(createdAt = 1_780_000_000_500L, updatedAt = 1_780_000_000_999L)
        val json = AnnotationBackupMapper.json(emptyList(), listOf(r), emptyList())
        assertTrue(json, json.contains("\"createdAt\":\"2026-05-28T20:26:40Z\""))
        assertTrue(json, json.contains("\"updatedAt\":\"2026-05-28T20:26:40Z\""))
    }

    @Test fun envelope_emptyInput_isValidEmptyEnvelope() {
        val env = AnnotationBackupMapper.envelope(emptyList(), emptyList(), emptyList())
        assertTrue(env.highlights.isEmpty() && env.notes.isEmpty() && env.bookmarks.isEmpty())
        assertEquals(
            """{"schemaVersion":${BackupSchema.CURRENT_SCHEMA_VERSION},"highlights":[],"bookmarks":[],"notes":[]}""",
            AnnotationBackupMapper.json(emptyList(), emptyList(), emptyList()),
        )
    }

    companion object {
        /** VERBATIM pre-extraction `BackupCollector` output for the fixtures above (sha256
         *  `ace51490a5fc3ede2be8c8282362478455b79f652679b0bf610dc91e767dac0b`). Captured by running
         *  this test against `BackupCollector`'s private mappers before WI-1 deleted them. */
        const val GOLDEN_SECTION = """{"schemaVersion":3,"highlights":[{"highlightId":"11111111-1111-1111-1111-111111111111","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":10}","selectedText":"hello","color":"yellow","note":"a note","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"},{"highlightId":"22222222-2222-2222-2222-222222222222","bookFingerprintKey":"txt:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:4096","locatorJSON":"{\"contentSHA256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"fileByteCount\":4096,\"format\":\"txt\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":949}","selectedText":"选中的文本","color":"yellow","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:27:40Z"}],"bookmarks":[{"bookmarkId":"55555555-5555-5555-5555-555555555555","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":5}","title":"Chapter 1","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"},{"bookmarkId":"66666666-6666-6666-6666-666666666666","bookFingerprintKey":"txt:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:4096","locatorJSON":"{\"contentSHA256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"fileByteCount\":4096,\"format\":\"txt\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":6}","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"}],"notes":[{"annotationId":"33333333-3333-3333-3333-333333333333","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":30}","content":"first","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"},{"annotationId":"44444444-4444-4444-4444-444444444444","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":40}","content":"second","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"}]}"""
    }
}
