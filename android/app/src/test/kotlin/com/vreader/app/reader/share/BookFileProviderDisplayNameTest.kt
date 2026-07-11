// Purpose: feature #134 WI-2 — the FileProvider DISPLAY_NAME override contract (§display-name).
// Imported book files are stored under a sanitized fingerprint key with NO extension, so a raw
// content URI would present an unusable attachment name (e.g. `epub_a1b2…_4`). BookFileProvider
// overrides the OpenableColumns.DISPLAY_NAME cursor column so a shared book reports `title.ext`
// (title from Book.title, ext from the format) — Unicode/CJK preserved, illegal filename chars
// sanitized, an all-illegal title falling back to a safe stem — WITHOUT renaming the canonical
// file on disk. Robolectric (the query() path resolves a content URI through the provider).
package com.vreader.app.reader.share

import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.Book
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import java.io.File

@RunWith(RobolectricTestRunner::class)
class BookFileProviderDisplayNameTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val booksDir = File(context.filesDir, "books")
    private val authority = "com.vreader.app.fileprovider"

    @Before fun setUp() {
        // Robolectric gives each test method a FRESH temp filesDir, but FileProvider caches its
        // per-authority PathStrategy statically (sCache) — the first method's root would then be
        // checked against a later method's file (different temp dir) → "Failed to find configured
        // root". Clear the static cache so each method rebuilds the strategy against ITS filesDir.
        resetFileProviderCache()
        booksDir.mkdirs()
        booksDir.listFiles()?.forEach { it.delete() }
        BookFileProvider.clearRegistrations()
    }

    @After fun tearDown() { BookFileProvider.clearRegistrations() }

    private fun resetFileProviderCache() {
        try {
            val f = FileProvider::class.java.getDeclaredField("sCache")
            f.isAccessible = true
            (f.get(null) as? MutableMap<*, *>)?.clear()
        } catch (_: Exception) { /* SDK internal name changed — tolerate */ }
    }

    private fun seed(key: String): File {
        val onDisk = File(booksDir, key.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        onDisk.writeBytes(byteArrayOf(1, 2, 3, 4))
        return onDisk
    }

    private fun book(key: String, title: String, format: BookFormat, file: File) = Book(
        fingerprintKey = key,
        title = title,
        originalFormat = format,
        contentSHA256 = "a".repeat(64),
        fileByteCount = 4,
        localFilePath = file.absolutePath,
        addedAt = 1L,
    )

    /** Build the content URI the same way the share intent does, registering the display name. */
    private fun uriFor(book: Book): Uri {
        val file = File(book.localFilePath!!)
        BookFileProvider.registerDisplayName(file, book)
        return FileProvider.getUriForFile(context, authority, file)
    }

    private fun queryDisplayName(uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    @Test
    fun displayName_reportsTitleDotExt_perFormat() {
        val cases = mapOf(
            BookFormat.epub to "epub",
            BookFormat.pdf to "pdf",
            BookFormat.txt to "txt",
            BookFormat.md to "md",
            BookFormat.azw3 to "azw3",
        )
        cases.forEach { (format, ext) ->
            val key = "${format.name}:${"a".repeat(64)}:4"
            val file = seed(key)
            val uri = uriFor(book(key, "Great Novel", format, file))
            assertEquals("DISPLAY_NAME for $format", "Great Novel.$ext", queryDisplayName(uri))
        }
    }

    @Test
    fun displayName_preservesUnicodeAndCJK() {
        val key = "epub:${"b".repeat(64)}:4"
        val file = seed(key)
        val uri = uriFor(book(key, "红楼梦 曹雪芹", BookFormat.epub, file))
        // CJK + spaces + the middle dot are legal filename characters — preserved, not mangled.
        assertEquals("红楼梦 曹雪芹.epub", queryDisplayName(uri))
    }

    @Test
    fun displayName_sanitizesIllegalChars() {
        val key = "pdf:${"c".repeat(64)}:4"
        val file = seed(key)
        // Illegal filename chars: \ / : * ? " < > | and control chars → replaced with _
        val uri = uriFor(book(key, "A/B:C*D?\"E<F>G|H", BookFormat.pdf, file))
        val name = queryDisplayName(uri)!!
        assertTrue("no path separators or reserved chars in the display name: $name",
            name.none { it in "\\/:*?\"<>|" })
        assertTrue("keeps the .pdf extension", name.endsWith(".pdf"))
    }

    @Test
    fun displayName_allIllegalTitle_fallsBackToSafeStem() {
        val key = "txt:${"d".repeat(64)}:4"
        val file = seed(key)
        // A title that is ONLY illegal chars → must not yield a bare ".txt" (dotfile) or empty stem.
        val uri = uriFor(book(key, "///:::***", BookFormat.txt, file))
        val name = queryDisplayName(uri)!!
        assertTrue("must have a non-empty stem before .txt (not a dotfile): $name",
            name.endsWith(".txt") && name.length > ".txt".length && !name.startsWith("."))
    }

    @Test
    fun displayName_emptyTitle_fallsBackToSafeStem() {
        val key = "md:${"e".repeat(64)}:4"
        val file = seed(key)
        val uri = uriFor(book(key, "   ", BookFormat.md, file))
        val name = queryDisplayName(uri)!!
        assertTrue("blank title → safe non-empty stem + .md: $name",
            name.endsWith(".md") && name.length > ".md".length && !name.startsWith("."))
    }

    @Test
    fun displayNameOverride_doesNotRenameOnDiskFile() {
        val key = "epub:${"f".repeat(64)}:4"
        val file = seed(key)
        val onDiskName = file.name
        val uri = uriFor(book(key, "Pretty Title", BookFormat.epub, file))
        queryDisplayName(uri) // triggers query()
        // The canonical on-disk file keeps its sanitized-key name; only the reported label changes.
        assertTrue("the on-disk file must still exist unchanged", file.exists())
        assertEquals("the on-disk filename must NOT be renamed", onDiskName, file.name)
        assertNotNull("registration is by File, verify file still under books/", booksDir.listFiles()?.firstOrNull { it.name == onDiskName })
    }
}
