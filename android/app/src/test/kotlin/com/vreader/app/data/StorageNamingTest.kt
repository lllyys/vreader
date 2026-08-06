package com.vreader.app.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.library.covers.CoverPaths
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import java.io.ByteArrayInputStream
import java.io.File
import java.util.Random

/**
 * Feature #152 WI-1 — the key→filename mapping, frozen.
 *
 * [StorageNaming.fileNameForKey] already names every book artifact on every user's device, and
 * `BookEntity.localFilePath` points at those names. So this is an EXTRACTION, not a redesign: any
 * change to the mapping silently orphans every existing library. These tests exist to make that
 * change impossible to land accidentally — the golden cases pin the literal output, and the
 * import case pins the fact that `BookImporter` and `CoverPaths` call ONE function rather than
 * two copies that can drift apart.
 *
 * The mapping is injective only on the CANONICAL-KEY domain (`Identity.parseCanonicalKey != null`),
 * which is where the precondition test belongs; `a:b` and `a/b` really do both map to `a_b`, but
 * neither is a key any caller can produce. See the plan's §4 M-9 disposition.
 */
@RunWith(RobolectricTestRunner::class)
class StorageNamingTest {
    @get:Rule val tmp = TemporaryFolder()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var db: VReaderDatabase

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
    }

    @After fun tearDown() = db.close()

    // ---- the frozen mapping -------------------------------------------------------------------

    /**
     * Golden cases. The expectations are written out literally, NOT derived from the function
     * under test, so a one-character change to the substitution reddens this immediately.
     */
    @Test fun fileNameForKey_producesTheNamesAlreadyOnDisk() {
        assertEquals(
            "epub_${SHA_A}_4096",
            StorageNaming.fileNameForKey("epub:$SHA_A:4096"),
        )
        assertEquals(
            "azw3_${SHA_B}_6288371",
            StorageNaming.fileNameForKey("azw3:$SHA_B:6288371"),
        )
        assertEquals(
            "txt_${SHA_ZEROS}_0",
            StorageNaming.fileNameForKey("txt:$SHA_ZEROS:0"),
        )
        assertEquals(
            "pdf_${SHA_FS}_9223372036854775807",
            StorageNaming.fileNameForKey("pdf:$SHA_FS:9223372036854775807"),
        )
        assertEquals(
            "md_${SHA_A}_1",
            StorageNaming.fileNameForKey("md:$SHA_A:1"),
        )
    }

    /**
     * The substitution table itself, pinned. This is NOT the deleted "sanitised-different keys do
     * not collide" case — it asserts nothing about injectivity or about non-canonical keys being
     * usable. It pins WHICH characters survive, because that is what decides the names already
     * written to disk. Without it, dropping `.` or `-` from the safe set is an undetectable edit.
     */
    @Test fun fileNameForKey_preservesExactlyTheSafeCharacterClass() {
        val safe = "AZaz09._-"
        assertEquals(safe, StorageNaming.fileNameForKey(safe))
        assertEquals("_________", StorageNaming.fileNameForKey(":/\\ *?\"<>"))
    }

    @Test fun fileNameForKey_leavesNoPathSeparatorOrColon() {
        for (key in generatedCanonicalKeys(perFormat = 4)) {
            val name = StorageNaming.fileNameForKey(key)
            assertFalse(name, name.contains('/'))
            assertFalse(name, name.contains('\\'))
            assertFalse(name, name.contains(':'))
            assertTrue(name, name.all { it.isLetterOrDigit() || it == '.' || it == '_' || it == '-' })
        }
    }

    // ---- one function, not two ----------------------------------------------------------------

    /**
     * The extraction's load-bearing assertion: a REAL import through [BookImporter] names its
     * artifact with exactly [StorageNaming.fileNameForKey]. A `BookImporter` that kept its own
     * private copy of the regex would pass every other test in this file and still be a
     * data-loss bug the day the two drift.
     */
    @Test fun bookImporter_namesItsArtifactWith_storageNaming() = runTest {
        val booksDir = tmp.newFolder("books")
        val importer = BookImporter(
            booksDir,
            LibraryRepository(db.bookDao(), db.readingPositionDao()),
            Dispatchers.Unconfined,
        ) { 1000L }

        val book = importer.importStream(
            sourceUri = "content://saf/1",
            displayName = "Moby-Dick.epub",
            input = ByteArrayInputStream(ByteArray(4096) { (it % 251).toByte() }),
        )

        val actualName = File(book.localFilePath!!).name
        assertEquals(StorageNaming.fileNameForKey(book.fingerprintKey), actualName)
        // And independently of the function under test: the key with ':' → '_'.
        assertEquals(book.fingerprintKey.replace(':', '_'), actualName)
    }

    /** The cover store derives its stem from the same function — one scheme across both stores. */
    @Test fun coverPaths_derivesItsStemFrom_storageNaming() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        val key = "epub:$SHA_A:4096"
        assertEquals("${StorageNaming.fileNameForKey(key)}.jpg", paths.coverFile(key).name)
    }

    // ---- injectivity, on the domain the contract actually declares ----------------------------

    /**
     * Constructive injectivity: a canonical key contains no `_` and exactly two `:`, so `:`→`_`
     * is INVERTIBLE on this domain. An inverse is a stronger proof than sampled distinctness,
     * and it holds for every key rather than for the ones we happened to generate.
     */
    @Test fun fileNameForKey_isInvertible_onTheCanonicalDomain() {
        for (key in generatedCanonicalKeys(perFormat = 20)) {
            assertFalse("canonical keys carry no '_'", key.contains('_'))
            assertEquals("canonical keys carry exactly two ':'", 2, key.count { it == ':' })
            assertEquals(key, StorageNaming.fileNameForKey(key).replace('_', ':'))
        }
    }

    /** Sampled distinctness across all five formats × varied sha × varied byte count. */
    @Test fun fileNameForKey_isInjective_overGeneratedCanonicalKeys() {
        val keys = generatedCanonicalKeys(perFormat = 40)
        assertEquals(BookFormat.entries.size * 40, keys.size)
        assertEquals("every generated key must be canonical", keys.size, keys.count { Identity.parseCanonicalKey(it) != null })
        val names = keys.map { StorageNaming.fileNameForKey(it) }
        assertEquals("distinct canonical keys must yield distinct filenames", keys.size, names.toSet().size)
    }

    // ---- the precondition ---------------------------------------------------------------------

    /**
     * The mapping is not a general-purpose escaper, so the store that DERIVES A PATH from it
     * states the precondition rather than pretending to be safe for arbitrary input. Every one of
     * these is rejected, including the two that would otherwise escape the covers directory.
     */
    @Test fun coverPaths_rejectsNonCanonicalKeys() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        val rejected = listOf(
            "",
            "epub",
            "epub:$SHA_A",
            "epub:$SHA_A:4096:extra",             // limit=3 keeps the tail, which is not a Long
            "zip:$SHA_A:4096",                    // unknown format
            "epub:${SHA_A.dropLast(1)}:4096",     // 63 hex chars
            "epub:${SHA_A.uppercase()}:4096",     // uppercase hex — Identity requires lowercase
            "epub:${SHA_A.dropLast(1)}g:4096",    // non-hex char
            "epub:$SHA_A:-1",                     // negative byte count
            "epub:$SHA_A:notanumber",
            "../../../etc/passwd",                // path traversal
            "..:$SHA_A:4096",
            "书名:$SHA_A:4096",                    // CJK
            "epub:$SHA_A:4096 ",
        )
        for (key in rejected) {
            assertThrowsIllegalArgument("coverFile($key)") { paths.coverFile(key) }
        }
    }

    /** Both boundaries of the byte-count domain are legal keys and must NOT be rejected. */
    @Test fun coverPaths_acceptsTheCanonicalBoundaries() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        assertEquals("epub_${SHA_A}_0.jpg", paths.coverFile("epub:$SHA_A:0").name)
        assertEquals(
            "epub_${SHA_A}_9223372036854775807.jpg",
            paths.coverFile("epub:$SHA_A:${Long.MAX_VALUE}").name,
        )
    }

    /** A typo'd fixture would silently weaken every case above. */
    @Test fun fixtureShasAreValid() {
        for (sha in listOf(SHA_A, SHA_B, SHA_ZEROS, SHA_FS)) {
            assertTrue(sha, Identity.isValidSHA256(sha))
        }
    }

    // ---- helpers -------------------------------------------------------------------------------

    private fun generatedCanonicalKeys(perFormat: Int): List<String> {
        val rng = Random(0xC0FFEE)
        val hex = "0123456789abcdef"
        return BookFormat.entries.flatMap { format ->
            (0 until perFormat).map { i ->
                val sha = buildString { repeat(64) { append(hex[rng.nextInt(16)]) } }
                val bytes = when (i % 4) {
                    0 -> 0L
                    1 -> 1L
                    2 -> Long.MAX_VALUE
                    else -> (rng.nextLong() ushr 1)
                }
                Identity.canonicalKey(format.name, sha, bytes)
            }
        }
    }

    private fun assertThrowsIllegalArgument(what: String, body: () -> Unit) {
        try {
            body()
            throw AssertionError("$what should have thrown IllegalArgumentException")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }

    private companion object {
        const val SHA_A = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        const val SHA_B = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        const val SHA_ZEROS = "0000000000000000000000000000000000000000000000000000000000000000"
        const val SHA_FS = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    }
}
