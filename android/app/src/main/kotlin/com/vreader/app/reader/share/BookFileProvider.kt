// Purpose: feature #134 WI-2 — a FileProvider subclass that overrides the OpenableColumns.DISPLAY_NAME
// cursor column so a shared book file reports a human-usable `title.ext` (§display-name) instead of the
// raw on-disk name. Imported artifacts are stored under a SANITIZED fingerprint key with NO extension
// (BookImporter.fileNameForKey → e.g. `epub_a1b2…_4`), so the receiver of a shared content URI would
// otherwise present an unusable attachment name. This override changes ONLY the reported label — the
// canonical file on disk is NEVER renamed. Title→filename sanitization keeps Unicode/CJK, replaces the
// reserved filename chars \ / : * ? " < > | and control chars with '_', and falls back to a safe stem
// for an empty/all-illegal title (never a dotfile). shareBookFileIntent (BookShareIntent.kt) registers
// each file's display name here just before it grants the URI; the map is keyed by the file's canonical
// (absolute, symlink-resolved) path.
// @coordinates-with BookShareIntent.kt (registers display names), AndroidManifest.xml (declares this
// provider with authority ${applicationId}.fileprovider + @xml/file_paths).
package com.vreader.app.reader.share

import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.vreader.app.data.Book
import vreader.contracts.BookFormat
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * The book-file FileProvider. Declared in the manifest as `${applicationId}.fileprovider`
 * (exported=false, grantUriPermissions=true) with `@xml/file_paths` scoped to `filesDir/books`.
 */
class BookFileProvider : FileProvider() {

    /**
     * Intercept the DISPLAY_NAME column so the shared file presents `title.ext`. Falls through to the
     * default provider cursor (raw on-disk name + size) for any file we have no registration for, or
     * any query not asking for DISPLAY_NAME. The on-disk file is never touched.
     */
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val base = super.query(uri, projection, selection, selectionArgs, sortOrder)
        val display = displayNameFor(uri) ?: return base

        // Rebuild the cursor, overriding DISPLAY_NAME with our label and preserving every other column.
        val columns = base.columnNames
        val out = MatrixCursor(columns)
        base.use { c ->
            while (c.moveToNext()) {
                val row = arrayOfNulls<Any?>(columns.size)
                for (i in columns.indices) {
                    row[i] = if (columns[i] == OpenableColumns.DISPLAY_NAME) display else valueAt(c, i)
                }
                out.addRow(row)
            }
        }
        return out
    }

    private fun valueAt(c: Cursor, i: Int): Any? = when (c.getType(i)) {
        Cursor.FIELD_TYPE_NULL -> null
        Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
        Cursor.FIELD_TYPE_FLOAT -> c.getDouble(i)
        Cursor.FIELD_TYPE_BLOB -> c.getBlob(i)
        else -> c.getString(i)
    }

    private fun displayNameFor(uri: Uri): String? {
        // FileProvider's internal getFileForUri is not accessible; resolve by the URI's trailing
        // segment, which is the on-disk filename (the sanitized fingerprint key — globally unique
        // within books/). Match it against the registry populated by registerDisplayName.
        val fileName = uri.lastPathSegment?.substringAfterLast('/') ?: return null
        return registrations.values.firstOrNull { it.fileName == fileName }?.displayName
    }

    companion object {
        private data class Registration(val fileName: String, val displayName: String)

        // Keyed by the file's canonical absolute path so re-registration is idempotent.
        private val registrations = ConcurrentHashMap<String, Registration>()

        /** The reserved filename characters (Windows/SAF-hostile) replaced with '_'. */
        private val ILLEGAL = charArrayOf('\\', '/', ':', '*', '?', '"', '<', '>', '|')

        /** Register the `title.ext` display name for [file] (a book under books/) before granting a URI. */
        fun registerDisplayName(file: File, book: Book) {
            val name = safeDisplayName(book.title, extensionFor(book.originalFormat))
            registrations[file.canonicalPathOrSelf()] = Registration(file.name, name)
        }

        /** Test seam: drop all registrations. */
        fun clearRegistrations() = registrations.clear()

        /** The file extension for a book format (matches the share intent's per-format mapping). */
        fun extensionFor(format: BookFormat): String = when (format) {
            BookFormat.epub -> "epub"
            BookFormat.pdf -> "pdf"
            BookFormat.txt -> "txt"
            BookFormat.md -> "md"
            BookFormat.azw3 -> "azw3"
        }

        /**
         * Build a safe `stem.ext` label: sanitize [title] (reserved chars → '_', control chars dropped,
         * collapse whitespace runs, trim leading/trailing '_'/'.'/space), fall back to "book" when the
         * result is empty (empty / all-illegal title) so we never emit a bare ".ext" dotfile. Length-cap
         * the stem so a pathological title can't produce an over-long filename.
         */
        fun safeDisplayName(title: String, ext: String): String {
            val cleaned = buildString {
                for (ch in title) {
                    when {
                        ch in ILLEGAL -> append('_')
                        ch.isISOControl() -> { /* drop */ }
                        else -> append(ch)
                    }
                }
            }
            val stem = cleaned
                .replace(Regex("\\s+"), " ")
                .trim()
                .trim('_', '.', ' ')
                .take(120)
                .ifBlank { "book" }
            return "$stem.$ext"
        }

        private fun File.canonicalPathOrSelf(): String =
            try { canonicalPath } catch (_: Exception) { absolutePath }
    }
}
