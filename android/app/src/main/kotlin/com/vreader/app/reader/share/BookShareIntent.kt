// Purpose: feature #134 WI-2 — build + launch the "Share book" ACTION_SEND flow (§share-hardening,
// §share-missing-file). Given a Book with a validated local file UNDER filesDir/books, produce a
// chooser intent carrying a FileProvider content URI on EXTRA_STREAM, the per-format MIME, a read
// grant (FLAG_GRANT_READ_URI_PERMISSION) AND a matching ClipData (belt-and-suspenders — the flag
// alone can miss on some receivers), wrapped in Intent.createChooser. Security: the file MUST resolve
// to a readable, existing path inside filesDir/books; anything else (null path, path outside books/,
// deleted file, or a FileProvider that rejects the path) yields a null intent → a silent no-op, never
// a crash and never an invented error UI (rule 51). shareBook() adds the startActivity + no-receiver /
// ActivityNotFoundException guarding.
// @coordinates-with BookFileProvider.kt (the DISPLAY_NAME override + authority),
// AndroidManifest.xml (the <provider> declaration).
package com.vreader.app.reader.share

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.vreader.app.data.Book
import com.vreader.app.diagnostics.DiagnosticsCategory
import com.vreader.app.diagnostics.VLog
import vreader.contracts.BookFormat
import java.io.File

private const val TAG = "BookShare"
private const val FILE_PROVIDER_SUFFIX = ".fileprovider"

/**
 * Build the "Share book" chooser intent for [book], or `null` when the book has no shareable local
 * file. Returns null (a silent no-op signal) when: [Book.localFilePath] is null, the file does not
 * exist / is not readable, the file is NOT inside `filesDir/books`, or the FileProvider rejects the
 * path (out-of-scope). On the happy path the returned intent is a `createChooser` wrapping an
 * ACTION_SEND with the FileProvider content URI, the per-format MIME, the read grant flag + ClipData.
 */
fun shareBookFileIntent(context: Context, book: Book): Intent? {
    val path = book.localFilePath ?: return null
    val file = File(path)

    // Precondition: a readable, existing file physically INSIDE filesDir/books (§share-hardening).
    if (!file.exists() || !file.isFile || !file.canRead()) return null
    if (!isInsideBooksDir(context, file)) return null

    val authority = context.packageName + FILE_PROVIDER_SUFFIX
    val uri = try {
        BookFileProvider.registerDisplayName(file, book)
        FileProvider.getUriForFile(context, authority, file)
    } catch (e: IllegalArgumentException) {
        // FileProvider throws when the file is outside every configured <paths> root — reject.
        VLog.w(DiagnosticsCategory.LIBRARY, TAG, "file not shareable via FileProvider (outside grant scope)", e)
        return null
    }

    val send = Intent(Intent.ACTION_SEND).apply {
        type = mimeFor(book.originalFormat)
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // Matching ClipData so the grant sticks on receivers that read the clip rather than the flag.
        clipData = ClipData.newRawUri(book.title, uri)
    }
    return Intent.createChooser(send, null)
}

/**
 * Build + launch the share chooser for [book]. A missing/out-of-scope file, a chooser with no
 * receiver, or an [ActivityNotFoundException] is a SILENT no-op (logged) — never a crash and never a
 * visible error surface (rule 51, §share-missing-file).
 */
fun shareBook(context: Context, book: Book) {
    val chooser = (shareBookFileIntent(context, book) ?: return).apply {
        // Launching from a non-Activity Context (or a Compose host reached via applicationContext)
        // requires NEW_TASK; harmless when the caller is an Activity.
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    try {
        context.startActivity(chooser)
    } catch (e: ActivityNotFoundException) {
        VLog.w(DiagnosticsCategory.LIBRARY, TAG, "no activity to receive the shared book file", e)
    }
}

/**
 * The per-format share MIME (§share-hardening). Exhaustive over the closed [BookFormat] enum, so there
 * is no "unknown" case at runtime; adding a new format is a compile error here until it gets a MIME.
 */
fun mimeFor(format: BookFormat): String = when (format) {
    BookFormat.epub -> "application/epub+zip"
    BookFormat.pdf -> "application/pdf"
    BookFormat.txt -> "text/plain"
    BookFormat.md -> "text/markdown"
    BookFormat.azw3 -> "application/vnd.amazon.ebook"
}

/** True only when [file] resolves to a path physically inside `filesDir/books` (path-traversal safe). */
private fun isInsideBooksDir(context: Context, file: File): Boolean {
    val booksDir = File(context.filesDir, "books")
    val booksCanonical = booksDir.canonicalPathOrSelf() + File.separator
    val fileCanonical = file.canonicalPathOrSelf()
    return fileCanonical.startsWith(booksCanonical)
}

private fun File.canonicalPathOrSelf(): String =
    try { canonicalPath } catch (_: Exception) { absolutePath }
