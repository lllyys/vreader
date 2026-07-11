// Purpose: feature #134 WI-2 — the book-file share-intent contract (§share-hardening). Robolectric
// (needs a Context for FileProvider.getUriForFile + resolveActivity). Asserts shareBookFileIntent
// builds an ACTION_SEND chooser with a `fileprovider` content URI on EXTRA_STREAM, the per-format
// MIME, FLAG_GRANT_READ_URI_PERMISSION + a matching ClipData (belt-and-suspenders grant), that a
// path OUTSIDE filesDir/books is REJECTED, and that a missing file / no receiver never crashes.
package com.vreader.app.reader.share

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.Book
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import java.io.File

@RunWith(RobolectricTestRunner::class)
class BookShareIntentTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val booksDir = File(context.filesDir, "books")

    @Before fun setUp() {
        // FileProvider caches its per-authority PathStrategy statically (sCache); Robolectric gives
        // each test method a fresh temp filesDir, so the cached root from an earlier method would
        // reject a later method's file. Clear the cache per method.
        resetFileProviderCache()
        booksDir.mkdirs()
        // Purge any prior-test artifacts so filename→display registrations don't bleed across tests.
        booksDir.listFiles()?.forEach { it.delete() }
    }

    private fun resetFileProviderCache() {
        try {
            val f = androidx.core.content.FileProvider::class.java.getDeclaredField("sCache")
            f.isAccessible = true
            (f.get(null) as? MutableMap<*, *>)?.clear()
        } catch (_: Exception) { /* tolerate SDK internal name changes */ }
    }

    /** Create a real on-disk file under books/ named like the sanitized fingerprint key. */
    private fun seedBookFile(key: String): File {
        val onDisk = File(booksDir, key.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        onDisk.writeBytes(byteArrayOf(1, 2, 3, 4))
        return onDisk
    }

    private fun book(
        key: String,
        title: String = "My Book",
        format: BookFormat = BookFormat.epub,
        localFilePath: String?,
    ) = Book(
        fingerprintKey = key,
        title = title,
        originalFormat = format,
        contentSHA256 = "a".repeat(64),
        fileByteCount = 4,
        localFilePath = localFilePath,
        addedAt = 1L,
    )

    @Test
    fun buildsActionSendChooser_withFileProviderUri_andPerFormatMime() {
        val key = "epub:${"a".repeat(64)}:4"
        val file = seedBookFile(key)
        val intent = shareBookFileIntent(context, book(key, format = BookFormat.epub, localFilePath = file.absolutePath))

        assertNotNull("expected a non-null chooser intent for a valid book file", intent)
        // A createChooser() wraps the real send intent in EXTRA_INTENT.
        val send = intent!!.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: intent
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("application/epub+zip", send.type)

        val uri = send.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
        assertNotNull("EXTRA_STREAM must carry the content URI", uri)
        assertEquals("content", uri!!.scheme)
        assertTrue("URI must go through the app FileProvider authority", uri.authority == "com.vreader.app.fileprovider")
    }

    @Test
    fun setsReadGrantFlag_andMatchingClipData() {
        val key = "pdf:${"b".repeat(64)}:4"
        val file = seedBookFile(key)
        val intent = shareBookFileIntent(context, book(key, format = BookFormat.pdf, localFilePath = file.absolutePath))!!
        val send = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: intent

        assertTrue(
            "FLAG_GRANT_READ_URI_PERMISSION must be set",
            send.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0,
        )
        val clip = send.clipData
        assertNotNull("a matching ClipData must accompany the flag (belt-and-suspenders grant)", clip)
        val clipUri = clip!!.getItemAt(0).uri
        assertEquals(
            "ClipData URI must equal the EXTRA_STREAM URI",
            send.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM),
            clipUri,
        )
    }

    @Test
    fun perFormatMime_coversEveryBookFormat() {
        val expected = mapOf(
            BookFormat.epub to "application/epub+zip",
            BookFormat.pdf to "application/pdf",
            BookFormat.txt to "text/plain",
            BookFormat.md to "text/markdown",
            BookFormat.azw3 to "application/vnd.amazon.ebook",
        )
        expected.forEach { (format, mime) ->
            val key = "${format.name}:${"c".repeat(64)}:4"
            val file = seedBookFile(key)
            val intent = shareBookFileIntent(context, book(key, format = format, localFilePath = file.absolutePath))!!
            val send = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: intent
            assertEquals("MIME for $format", mime, send.type)
        }
    }

    @Test
    fun pathOutsideBooksDir_isRejected_returnsNull() {
        // A file that exists but lives OUTSIDE filesDir/books must not be shareable.
        val outside = File(context.filesDir, "not-books-secret.epub")
        outside.writeBytes(byteArrayOf(9))
        val key = "epub:${"d".repeat(64)}:1"
        val intent = shareBookFileIntent(context, book(key, localFilePath = outside.absolutePath))
        assertNull("a path outside filesDir/books must be rejected (no shareable intent)", intent)
    }

    @Test
    fun missingLocalFilePath_returnsNull_noCrash() {
        val key = "epub:${"e".repeat(64)}:4"
        val intent = shareBookFileIntent(context, book(key, localFilePath = null))
        assertNull("a null localFilePath yields no intent, not a crash", intent)
    }

    @Test
    fun deletedFileRace_returnsNull_noCrash() {
        // File was under books/ but is gone by share time (the deletion race, §share-missing-file).
        val key = "epub:${"f".repeat(64)}:4"
        val onDisk = File(booksDir, key.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        // Do NOT create it — points at a non-existent path inside books/.
        val intent = shareBookFileIntent(context, book(key, localFilePath = onDisk.absolutePath))
        assertNull("a deleted/missing book file yields no intent, not a crash", intent)
    }

    @Test
    fun shareBook_startActivity_noReceiver_isSilentNoOp() {
        // With no chooser receiver, launching must be a silent no-op (caught), never a crash.
        val key = "txt:${"1".repeat(64)}:4"
        val file = seedBookFile(key)
        // shareBook launches; Robolectric's default has no ACTION_SEND receiver → must not throw.
        shareBook(context, book(key, format = BookFormat.txt, localFilePath = file.absolutePath))
        assertTrue("shareBook must never crash even with no receiver", true)
    }

    @Test
    fun shareBook_withMissingFile_isSilentNoOp() {
        val key = "epub:${"2".repeat(64)}:4"
        shareBook(context, book(key, localFilePath = null))
        assertTrue("shareBook must never crash on a missing file", true)
    }
}
