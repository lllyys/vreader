package com.vreader.app.annotations

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.backup.AnnotationBackupMapper
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant

/**
 * Feature #165 WI-2 — [AnnotationsExportWriter] writes ONE book's annotations as the versioned
 * `annotations.json` contract text.
 *
 * The two byte pins ([exportJson_bookA_isByteIdenticalToTheCollectorsRowsForThatBook] /
 * [exportJson_bookB_preservesCjkAndOmitsNullTitle]) are NOT generated from the code under test:
 * the fixtures are WI-1's fixtures verbatim, and each expected row object is copied from
 * `AnnotationBackupMapperTest.GOLDEN_SECTION` — the collector output captured BEFORE the mapper
 * extraction. A per-book export is by definition that whole-library section filtered to the book.
 *
 * The contract-vector check is the leg `:identity BackupConformanceTest` cannot cover: that suite
 * decodes and re-encodes the *wire DTO* and never exercises a record→wire mapping, so it stays
 * green for an exporter that emits the wrong keys entirely.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationsExportWriterTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var db: VReaderDatabase
    private lateinit var library: LibraryRepository
    private lateinit var annotations: AnnotationsRepository
    private lateinit var writer: AnnotationsExportWriter

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        library = LibraryRepository(db.bookDao(), db.readingPositionDao())
        annotations = AnnotationsRepository(db.annotationDao())
        writer = AnnotationsExportWriter(annotations)
    }

    @After fun tearDown() { db.close() }

    // ── fixtures: WI-1's, verbatim (fixed UUIDs + fixed epoch-millis) ────────────

    private val keyA = Identity.canonicalKey(BookFormat.epub.name, "a".repeat(64), 2048L)
    private val keyB = Identity.canonicalKey(BookFormat.txt.name, "b".repeat(64), 4096L)
    private val keyEmpty = Identity.canonicalKey(BookFormat.md.name, "c".repeat(64), 512L)

    private fun locator(key: String, offset: Int): Locator {
        val parts = key.split(":")
        return Locator(
            contentSHA256 = parts[1], fileByteCount = parts[2].toLong(), format = parts[0],
            href = "c.xhtml", charOffsetUTF16 = offset,
        )
    }

    private fun highlights() = listOf(
        HighlightRecord(
            id = "22222222-2222-2222-2222-222222222222", bookKey = keyB,
            color = AnnotationColor.DEFAULT, selectedText = "选中的文本", note = null,
            locator = locator(keyB, 949), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_060_000L,
        ),
        HighlightRecord(
            id = "11111111-1111-1111-1111-111111111111", bookKey = keyA,
            color = AnnotationColor.DEFAULT, selectedText = "hello", note = "a note",
            locator = locator(keyA, 10), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
    )

    private fun notes() = listOf(
        NoteRecord(
            id = "44444444-4444-4444-4444-444444444444", bookKey = keyA,
            content = "second", locator = locator(keyA, 40), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
        NoteRecord(
            id = "33333333-3333-3333-3333-333333333333", bookKey = keyA,
            content = "first", locator = locator(keyA, 30), anchor = null,
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
    )

    private fun bookmarks() = listOf(
        BookmarkRecord(
            id = "55555555-5555-5555-5555-555555555555", bookKey = keyA,
            title = "Chapter 1", locator = locator(keyA, 5),
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
        BookmarkRecord(
            id = "66666666-6666-6666-6666-666666666666", bookKey = keyB,
            title = null, locator = locator(keyB, 6),
            createdAt = 1_780_000_000_000L, updatedAt = 1_780_000_000_000L,
        ),
    )

    /** Seeds through the UUID-and-timestamp-PRESERVING restore seam via LOCAL wire builders —
     *  seeding through the production mapper would make the byte pins self-fulfilling. */
    private suspend fun seed() {
        library.upsertBook(Book(keyA, "Book A", BookFormat.epub, "a".repeat(64), 2048L, "/data/a.epub", null, 1000L, null))
        library.upsertBook(Book(keyB, "Book B", BookFormat.txt, "b".repeat(64), 4096L, "/data/b.txt", null, 1000L, null))
        library.upsertBook(Book(keyEmpty, "Book C", BookFormat.md, "c".repeat(64), 512L, "/data/c.md", null, 1000L, null))
        annotations.restoreAnnotations(
            BackupAnnotationsEnvelope(
                BackupSchema.CURRENT_SCHEMA_VERSION,
                highlights = highlights().map { r ->
                    BackupHighlight(
                        highlightId = r.id, bookFingerprintKey = r.bookKey,
                        locatorJSON = BackupJson.encode(r.locator), selectedText = r.selectedText,
                        color = r.color.key, note = r.note,
                        createdAt = Instant.ofEpochMilli(r.createdAt),
                        updatedAt = Instant.ofEpochMilli(r.updatedAt),
                    )
                },
                bookmarks = bookmarks().map { r ->
                    BackupBookmark(
                        bookmarkId = r.id, bookFingerprintKey = r.bookKey,
                        locatorJSON = BackupJson.encode(r.locator), title = r.title,
                        createdAt = Instant.ofEpochMilli(r.createdAt),
                        updatedAt = Instant.ofEpochMilli(r.updatedAt),
                    )
                },
                notes = notes().map { r ->
                    BackupNote(
                        annotationId = r.id, bookFingerprintKey = r.bookKey,
                        locatorJSON = BackupJson.encode(r.locator), content = r.content,
                        createdAt = Instant.ofEpochMilli(r.createdAt),
                        updatedAt = Instant.ofEpochMilli(r.updatedAt),
                    )
                },
            ),
            allowedBookKeys = setOf(keyA, keyB),
        )
    }

    // ── A-1 / byte stability ────────────────────────────────────────────────────

    @Test fun exportJson_bookA_isByteIdenticalToTheCollectorsRowsForThatBook() = runTest {
        seed()
        assertEquals(GOLDEN_BOOK_A, writer.exportJson(keyA))
    }

    /** Also the scoping pin: book B's rows carry the CJK selection and the null title, and book A's
     *  export contains neither — a writer that ignored `bookKey` fails both. */
    @Test fun exportJson_bookB_preservesCjkAndOmitsNullTitle() = runTest {
        seed()
        val json = writer.exportJson(keyB)
        assertEquals(GOLDEN_BOOK_B, json)
        assertFalse("CJK must not be \\u-escaped", json.contains("\\u"))
        val needle = "选中的文本".toByteArray(Charsets.UTF_8)
        val bytes = json.toByteArray(Charsets.UTF_8)
        val at = bytes.indexOfSlice(needle)
        assertTrue("CJK bytes absent from the UTF-8 output", at >= 0)
        assertArrayEquals("CJK must survive byte-for-byte", needle, bytes.copyOfRange(at, at + needle.size))
    }

    @Test fun exportJson_matchesRepositoryRows_fieldByField() = runTest {
        seed()
        val env = BackupJson.decode<BackupAnnotationsEnvelope>(writer.exportJson(keyA))
        val snapshot = annotations.annotationsForBook(keyA)
        assertEquals(
            snapshot.highlights.map {
                listOf(
                    it.id, it.bookKey, BackupJson.encode(it.locator), it.selectedText, it.color.key,
                    it.note, Instant.ofEpochMilli(it.createdAt), Instant.ofEpochMilli(it.updatedAt),
                )
            }.toSet(),
            env.highlights.map {
                listOf(
                    it.highlightId, it.bookFingerprintKey, it.locatorJSON, it.selectedText,
                    it.color, it.note, it.createdAt, it.updatedAt,
                )
            }.toSet(),
        )
        assertEquals(
            snapshot.notes.map {
                listOf(
                    it.id, it.bookKey, BackupJson.encode(it.locator), it.content,
                    Instant.ofEpochMilli(it.createdAt), Instant.ofEpochMilli(it.updatedAt),
                )
            }.toSet(),
            env.notes.map {
                listOf(
                    it.annotationId, it.bookFingerprintKey, it.locatorJSON, it.content,
                    it.createdAt, it.updatedAt,
                )
            }.toSet(),
        )
        assertEquals(
            annotations.bookmarks(keyA).first().map {
                listOf(
                    it.id, it.bookKey, BackupJson.encode(it.locator), it.title,
                    Instant.ofEpochMilli(it.createdAt), Instant.ofEpochMilli(it.updatedAt),
                )
            }.toSet(),
            env.bookmarks.map {
                listOf(
                    it.bookmarkId, it.bookFingerprintKey, it.locatorJSON, it.title,
                    it.createdAt, it.updatedAt,
                )
            }.toSet(),
        )
    }

    /**
     * Output equivalence over the SAME rows: the writer's text equals `AnnotationBackupMapper`'s
     * for this book's records, so a re-assembly that sorted, enveloped or encoded differently is
     * caught. It does NOT prove delegation — hand-built text that happened to be byte-identical
     * would pass, and its expected value comes from the same mapper production calls. The
     * INDEPENDENT evidence is the two goldens above, copied from the pre-extraction collector
     * output; this test is the same-rows integration check on top of them.
     */
    @Test fun exportJson_equalsTheSharedMappersOutputForTheSameRows() = runTest {
        seed()
        val expected = AnnotationBackupMapper.json(
            highlights = highlights().filter { it.bookKey == keyA },
            notes = notes().filter { it.bookKey == keyA },
            bookmarks = bookmarks().filter { it.bookKey == keyA },
        )
        assertEquals(expected, writer.exportJson(keyA))
    }

    // ── A-2: contract shape + schema version ────────────────────────────────────

    /** The VALUE, not the type: a `schemaVersion = 1` export is type-correct and silently drops
     *  whatever v2/v3 added, so the shape check below cannot be the only version assertion. */
    @Test fun exportJson_schemaVersion_isCurrentSchemaVersion() = runTest {
        seed()
        val json = writer.exportJson(keyA)
        assertEquals(
            BackupSchema.CURRENT_SCHEMA_VERSION,
            BackupJson.decode<BackupAnnotationsEnvelope>(json).schemaVersion,
        )
        assertEquals(
            BackupSchema.CURRENT_SCHEMA_VERSION,
            Json.parseToJsonElement(json).jsonObject.getValue("schemaVersion").jsonPrimitive.int,
        )
    }

    @Test fun exportJson_conformsToTheContractVector() = runTest {
        seed()
        val vector = Json.parseToJsonElement(vectorFile().readText())
            .jsonObject.getValue("sections").jsonObject.getValue("annotations").jsonObject
        val exports = listOf(writer.exportJson(keyA), writer.exportJson(keyB))
            .map { Json.parseToJsonElement(it).jsonObject }

        exports.forEach { export ->
            assertEquals("top-level key set", vector.keys, export.keys)
            vector.keys.forEach { key ->
                assertEquals("type of '$key'", typeTag(vector.getValue(key)), typeTag(export.getValue(key)))
            }
        }
        // The vector's bookmark has a null title and its highlight a non-null note; `explicitNulls
        // = false` means an omitted key IS how a null serializes — so an optional key may be
        // absent, but a present one still carries the DTO's only legal type.
        mapOf(
            "highlights" to mapOf("note" to "string"),
            "bookmarks" to mapOf("title" to "string"),
            "notes" to emptyMap<String, String>(),
        ).forEach { (kind, optional) ->
            val reference = (vector.getValue(kind) as JsonArray).single().jsonObject
            val actual = exports.flatMap { (it.getValue(kind) as JsonArray).map { e -> e.jsonObject } }
            assertTrue("$kind: nothing was exported to check", actual.isNotEmpty())
            actual.forEach { assertConforms(kind, it, reference, optional) }
            assertTrue(
                "$kind: no exported element matches the vector's exact key set ${reference.keys}",
                actual.any { it.keys == reference.keys },
            )
        }
    }

    // ── C-13 + the degenerate keys ──────────────────────────────────────────────

    @Test fun exportJson_bookWithNoAnnotations_isValidEmptyEnvelope() = runTest {
        seed()
        val empty = """{"schemaVersion":${BackupSchema.CURRENT_SCHEMA_VERSION},"highlights":[],"bookmarks":[],"notes":[]}"""
        assertEquals(empty, writer.exportJson(keyEmpty))
        assertEquals(empty, writer.exportJson("epub:${"f".repeat(64)}:1"))
        assertEquals(empty, writer.exportJson(""))
    }

    // ── writeTo ─────────────────────────────────────────────────────────────────

    @Test fun writeTo_writesExactlyExportJsonBytes_andReturnsRowCount() = runTest {
        seed()
        val sink = ByteArrayOutputStream()
        val written = writer.writeTo(sink, keyA)
        assertArrayEquals(GOLDEN_BOOK_A.toByteArray(Charsets.UTF_8), sink.toByteArray())
        assertEquals("1 highlight + 2 notes + 1 bookmark", 4, written)
        assertEquals(0, writer.writeTo(ByteArrayOutputStream(), keyEmpty))
    }

    /** A buffered SAF sink only reaches the file on flush, and the caller (not the writer) owns
     *  the close — so both halves are asserted. `ByteArrayOutputStream` surfaces its bytes without
     *  a flush, which is exactly why the flush is counted rather than inferred from the output. */
    @Test fun writeTo_flushesAfterWriting_andDoesNotCloseTheSink() = runTest {
        seed()
        val events = mutableListOf<String>()
        val sink = object : ByteArrayOutputStream() {
            override fun write(b: ByteArray, off: Int, len: Int) { events += "write"; super.write(b, off, len) }
            override fun flush() { events += "flush"; super.flush() }
            override fun close() { events += "close"; super.close() }
        }
        writer.writeTo(sink, keyB)
        // The ORDER, not just the counts: `ByteArrayOutputStream` surfaces its bytes without a
        // flush, so a flush that happened before the write would look identical in the output.
        assertEquals(listOf("write", "flush"), events)
        assertTrue(sink.toByteArray().isNotEmpty())
    }

    // ── suggestedFileName ───────────────────────────────────────────────────────

    /** Derived, never echoed: a caller-supplied string is a TITLE, not the file name. */
    @Test fun suggestedFileName_isDerivedFromTheTitle_neverTheCallersString() {
        assertEquals("Moby Dick annotations.json", AnnotationsExportWriter.suggestedFileName("Moby Dick", keyA))
        assertEquals("evil.json annotations.json", AnnotationsExportWriter.suggestedFileName("evil.json", keyA))
    }

    @Test fun suggestedFileName_preservesCjkAndRtlLetters() {
        assertEquals("白夜行 annotations.json", AnnotationsExportWriter.suggestedFileName("白夜行", keyA))
        assertEquals("كتاب annotations.json", AnnotationsExportWriter.suggestedFileName("كتاب", keyA))
    }

    @Test fun suggestedFileName_stripsPathSeparatorsAndControlCharacters() {
        // NUL (a control char) and RLO (a bidi override that would reverse the surrounding UI) are
        // removed; the traversal prefix never survives because only the leaf can name a file.
        val name = AnnotationsExportWriter.suggestedFileName(HOSTILE_TITLE, keyA)
        assertEquals("passwrd annotations.json", name)
        assertFalse(name.contains('/'))
        assertFalse(name.contains('\\'))
        assertFalse("control / bidi-override survived", name.any { it.code < 0x20 || it == RLO })
        // A real space is orthographic, not a control char — kept, with runs collapsed.
        assertEquals("A B annotations.json", AnnotationsExportWriter.suggestedFileName("A  B", keyA))
    }

    @Test fun suggestedFileName_capsAtMaxNameChars_withoutSplittingASurrogatePair() {
        val astral = "𝄞"          // U+1D11E MUSICAL SYMBOL G CLEF — one surrogate PAIR
        val name = AnnotationsExportWriter.suggestedFileName(astral.repeat(300), keyA)
        assertTrue("length was ${name.length}", name.length <= AnnotationsExportWriter.MAX_NAME_CHARS)
        assertTrue(name.endsWith(" annotations.json"))
        val base = name.removeSuffix(" annotations.json")
        assertEquals("base must be whole surrogate pairs", 0, base.length % 2)
        assertTrue("a surrogate pair was split", base.chunked(2).all { it == astral })
    }

    @Test fun suggestedFileName_nullBlankOrFullyStrippedTitle_fallsBackToTheFingerprintPrefix() {
        listOf(null, "", "   ", RLO.toString(), NUL.toString(), "...", "///").forEach { title ->
            assertEquals(
                "title=<$title>",
                "aaaaaaaa annotations.json",
                AnnotationsExportWriter.suggestedFileName(title, keyA),
            )
        }
        assertEquals("bbbbbbbb annotations.json", AnnotationsExportWriter.suggestedFileName(null, keyB))
        // A degenerate key leaves nothing to name the file after — still a valid .json name.
        assertEquals("annotations.json", AnnotationsExportWriter.suggestedFileName(null, ""))
        assertEquals("annotations.json", AnnotationsExportWriter.suggestedFileName(null, "nokey"))
    }

    @Test fun suggestedFileName_alwaysEndsWithJson() {
        listOf(null, "", "白夜行", "Moby Dick", "   ", "a".repeat(5000), HOSTILE_TITLE, "..").forEach {
            assertTrue(AnnotationsExportWriter.suggestedFileName(it, keyA).endsWith(".json"))
        }
    }

    // ── helpers ─────────────────────────────────────────────────────────────────

    private fun assertConforms(
        kind: String,
        exported: JsonObject,
        reference: JsonObject,
        optional: Map<String, String>,
    ) {
        val required = reference.keys - optional.keys
        assertTrue("$kind: missing ${required - exported.keys}", exported.keys.containsAll(required))
        val unknown = exported.keys - reference.keys - optional.keys
        assertTrue("$kind: unknown keys $unknown", unknown.isEmpty())
        exported.keys.intersect(reference.keys).forEach {
            assertEquals("$kind.$it type", typeTag(reference.getValue(it)), typeTag(exported.getValue(it)))
        }
        optional.forEach { (key, type) ->
            exported[key]?.let { assertEquals("$kind.$key type", type, typeTag(it)) }
        }
    }

    private fun typeTag(element: JsonElement): String = when (element) {
        is JsonObject -> "object"
        is JsonArray -> "array"
        is JsonPrimitive -> when {
            element.isString -> "string"
            element.content == "null" -> "null"
            element.content == "true" || element.content == "false" -> "boolean"
            else -> "number"
        }
    }

    /** The SHARED cross-platform vector. Located by walking up from the test's working directory
     *  (`:app` does not inject `:identity`'s `vreader.vectors.dir` sysprop); a miss is a hard
     *  failure, never a silent skip — a conformance test that cannot find its vector must not pass. */
    private fun vectorFile(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "contracts/vectors/backup-sections.json")
            if (candidate.isFile) return candidate
            dir = dir.parentFile
        }
        throw AssertionError("contracts/vectors/backup-sections.json not found from ${File("").absolutePath}")
    }

    private fun ByteArray.indexOfSlice(needle: ByteArray): Int {
        outer@ for (i in 0..size - needle.size) {
            for (j in needle.indices) if (this[i + j] != needle[j]) continue@outer
            return i
        }
        return -1
    }

    private companion object {
        // Built from code points, never written as raw characters: a literal NUL in a source file
        // is a diff/tooling hazard and a literal RLO reorders the surrounding code visually.
        private val NUL = 0x0000.toChar()
        private val RLO = 0x202E.toChar()      // RIGHT-TO-LEFT OVERRIDE

        /** Path traversal + a control character + a bidi override — the three things a book title
         *  must never carry into a file name. */
        private val HOSTILE_TITLE = "../../etc/pas${NUL}sw${RLO}rd"

        // Each row object below is a VERBATIM copy of the corresponding object in
        // `AnnotationBackupMapperTest.GOLDEN_SECTION` — the pre-extraction collector output. A
        // per-book export is that section filtered to the book, so these are copied, not derived.
        private const val H_A = """{"highlightId":"11111111-1111-1111-1111-111111111111","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":10}","selectedText":"hello","color":"yellow","note":"a note","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"}"""
        private const val H_B = """{"highlightId":"22222222-2222-2222-2222-222222222222","bookFingerprintKey":"txt:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:4096","locatorJSON":"{\"contentSHA256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"fileByteCount\":4096,\"format\":\"txt\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":949}","selectedText":"选中的文本","color":"yellow","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:27:40Z"}"""
        private const val BM_A = """{"bookmarkId":"55555555-5555-5555-5555-555555555555","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":5}","title":"Chapter 1","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"}"""
        private const val BM_B = """{"bookmarkId":"66666666-6666-6666-6666-666666666666","bookFingerprintKey":"txt:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:4096","locatorJSON":"{\"contentSHA256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"fileByteCount\":4096,\"format\":\"txt\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":6}","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"}"""
        private const val N_A1 = """{"annotationId":"33333333-3333-3333-3333-333333333333","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":30}","content":"first","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"}"""
        private const val N_A2 = """{"annotationId":"44444444-4444-4444-4444-444444444444","bookFingerprintKey":"epub:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2048","locatorJSON":"{\"contentSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"fileByteCount\":2048,\"format\":\"epub\",\"href\":\"c.xhtml\",\"charOffsetUTF16\":40}","content":"second","createdAt":"2026-05-28T20:26:40Z","updatedAt":"2026-05-28T20:26:40Z"}"""

        const val GOLDEN_BOOK_A = """{"schemaVersion":3,"highlights":[$H_A],"bookmarks":[$BM_A],"notes":[$N_A1,$N_A2]}"""
        const val GOLDEN_BOOK_B = """{"schemaVersion":3,"highlights":[$H_B],"bookmarks":[$BM_B],"notes":[]}"""
    }
}
