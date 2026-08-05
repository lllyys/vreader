// Purpose: feature #155 WI-3 (plan D3/D6/D8) — turns an inbound content URI into a
// [PendingImport]: a resolved BookFormat, a sanitized display name, and ONE already-open,
// rewound stream that the caller owns.
//
// Pipeline (first success wins): DISPLAY_NAME extension -> last-path-segment extension ->
// MIME type -> magic bytes -> throw UnsupportedFormat.
//
// Key decisions:
//   * STEPS 1-2 ALWAYS BEAT 3-4 (identity stability). Format is part of the canonical key
//     `format:sha:bytes`, so a sniff that CONTRADICTED an extension would mint a second
//     library row for a book already imported, plus a second copy on disk. Sniffing only
//     ever fills a gap; a lying extension is accepted (plan §13.3).
//   * EXACTLY ONE STREAM. `resolveAndOpen` opens once and returns that same rewound
//     stream. A separate `openStream()` would be a TOCTOU window, and a one-shot provider
//     may refuse the second open or hand back different bytes.
//   * `peek` OPENS NOTHING — it is a cursor query, so the caller's size / free-space
//     preflight (D8) can reject before any file descriptor exists.
//   * The stream is closed on EVERY throwing path and on no other.
//
// @coordinates-with: BookMagicSniffer (step 4), ImportActivity (WI-5: the caller that owns
//   the URI grant), BookImporter.importStream (consumes format + displayName + stream)
package com.vreader.app.imports

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import com.vreader.app.data.ImportException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vreader.contracts.BookFormat
import vreader.contracts.DocumentFingerprint
import java.io.BufferedInputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.text.Normalizer

/** Metadata-only result of the pre-open cursor query (plan D8's preflight input). */
data class IncomingMetadata(val displayName: String?, val declaredSize: Long?)

/**
 * A resolved inbound document whose [stream] is ALREADY OPEN and rewound — the file
 * descriptor outlives the URI read grant, which is why it is opened while the calling
 * activity is still alive. The CALLER owns [stream] and must close it on every path.
 */
data class PendingImport(
    val uri: Uri,
    val displayName: String,
    val format: BookFormat,
    /** `uri.toString()` already capped to [IncomingBookResolver.MAX_SOURCE_URI_CHARS]. */
    val sourceUri: String,
    /** `OpenableColumns.SIZE`; null when absent or negative. */
    val declaredSize: Long?,
    val stream: InputStream,
)

class IncomingBookResolver(
    private val resolver: ContentResolver,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    /**
     * DISPLAY_NAME + SIZE only. Opens no stream, so the caller can reject an oversized or
     * unreadable document before any descriptor exists. Provider exceptions PROPAGATE —
     * a `query` that throws is a permission failure the preflight must see, not hide.
     */
    suspend fun peek(uri: Uri): IncomingMetadata = withContext(ioDispatcher) { queryMetadata(uri) }

    /**
     * Runs the whole chain over EXACTLY ONE stream and returns it rewound.
     *
     * Returns null only when the provider refuses to open the document at all. Throws
     * [ImportException.UnsupportedFormat] — after closing the stream — when every step
     * fails. Any other provider exception propagates for the caller to map.
     */
    suspend fun resolveAndOpen(uri: Uri): PendingImport? = withContext(ioDispatcher) {
        // A provider may refuse `query` yet allow `openInputStream`. Losing the name costs
        // us step 1; it must not cost us the book, so the later steps still run.
        val metadata = runCatching { queryMetadata(uri) }.getOrElse { IncomingMetadata(null, null) }

        val opened = openOrNull(uri) ?: return@withContext null
        // Sniffing needs mark/reset. Wrapping (never rejecting) keeps providers that hand
        // back a plain FileInputStream working.
        val stream = if (opened.markSupported()) {
            opened
        } else {
            BufferedInputStream(opened, BookMagicSniffer.PROBE_BYTES * 2)
        }

        try {
            val declaredName = cleanedName(metadata.displayName)
            val nameFormat = declaredName?.let { DocumentFingerprint.formatForFilename(it) }
            val segmentName = if (nameFormat == null) {
                cleanedName(runCatching { uri.lastPathSegment }.getOrNull())
            } else {
                null
            }
            val segmentFormat = segmentName?.let { DocumentFingerprint.formatForFilename(it) }

            val format = nameFormat                                                  // 1
                ?: segmentFormat                                                     // 2
                ?: formatForMimeType(runCatching { resolver.getType(uri) }.getOrNull())   // 3
                ?: BookMagicSniffer.sniff(stream)                                    // 4
                ?: throw ImportException.UnsupportedFormat(                           // 5
                    declaredName ?: segmentName ?: FALLBACK_NAME,
                )

            PendingImport(
                uri = uri,
                // The provider's name when it gave one; otherwise the path segment, but
                // only when THAT is what identified the format — an opaque document id
                // ("12345") is not a name and would make a nonsense title.
                displayName = declaredName
                    ?: segmentName?.takeIf { segmentFormat != null }
                    ?: (FALLBACK_NAME + "." + format.name),
                format = format,
                sourceUri = uri.toString().take(MAX_SOURCE_URI_CHARS),
                declaredSize = metadata.declaredSize,
                stream = stream,
            )
        } catch (t: Throwable) {
            // Every non-returning exit closes the stream: UnsupportedFormat, a hostile
            // provider's RuntimeException, and cancellation alike. Ownership only
            // transfers to the caller on the success path.
            runCatching { stream.close() }
            throw t
        }
    }

    /** A refusal to open is a null return, not an exception — the caller maps it to Unreadable. */
    private fun openOrNull(uri: Uri): InputStream? = try {
        resolver.openInputStream(uri)
    } catch (e: FileNotFoundException) {
        null
    }

    private fun queryMetadata(uri: Uri): IncomingMetadata {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        resolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return IncomingMetadata(null, null)
            return IncomingMetadata(
                displayName = cursor.stringOrNull(OpenableColumns.DISPLAY_NAME),
                declaredSize = cursor.longOrNull(OpenableColumns.SIZE)?.takeIf { it >= 0 },
            )
        }
        return IncomingMetadata(null, null)
    }

    private fun Cursor.stringOrNull(column: String): String? {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getString(index) else null
    }

    private fun Cursor.longOrNull(column: String): Long? {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getLong(index) else null
    }

    companion object {
        const val MAX_NAME_CHARS = 200
        const val MAX_SOURCE_URI_CHARS = 2048
        const val FALLBACK_NAME = "Untitled"

        /** Longest tail (dot included) still treated as an extension worth preserving. */
        private const val MAX_EXTENSION_CHARS = 16

        /**
         * The FULL Unicode Bidi_Control set. Enumerated rather than "strip category Cf",
         * because Cf also holds ZWNJ/ZWJ, which are orthographic in Persian and Indic
         * scripts — stripping those would corrupt real book names.
         */
        private val BIDI_CONTROLS = setOf(
            0x061C,                                      // ARABIC LETTER MARK
            0x200E, 0x200F,                              // LRM, RLM
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E,      // LRE, RLE, PDF, LRO, RLO
            0x2066, 0x2067, 0x2068, 0x2069,              // LRI, RLI, FSI, PDI
        )

        /**
         * Plan D4's MIME map. An octet-stream type, a wildcard type, and null all carry no
         * information and map to nothing, which is exactly why the magic-byte step exists.
         */
        fun formatForMimeType(mime: String?): BookFormat? {
            val normalized = mime?.substringBefore(';')?.trim()?.lowercase() ?: return null
            return when (normalized) {
                "application/epub+zip", "application/x-epub+zip", "application/epub" ->
                    BookFormat.epub
                "application/pdf", "application/x-pdf" -> BookFormat.pdf
                "text/plain" -> BookFormat.txt
                "text/markdown", "text/x-markdown" -> BookFormat.md
                "application/vnd.amazon.ebook", "application/vnd.amazon.mobi8-ebook",
                "application/x-mobipocket-ebook",
                -> BookFormat.azw3
                else -> null
            }
        }

        /**
         * A provider-supplied name made safe to show and to derive a title from: NFC
         * normalized, control and bidi-control characters removed, reduced to its last
         * path component, whitespace runs collapsed, trimmed, and capped at
         * [MAX_NAME_CHARS] with the extension preserved.
         *
         * CJK and RTL LETTERS survive untouched — only control characters are removed. When
         * nothing usable remains the result is [FALLBACK_NAME] plus [format]'s extension.
         */
        fun sanitizeDisplayName(raw: String?, format: BookFormat? = null): String =
            cleanedName(raw) ?: (FALLBACK_NAME + (format?.let { "." + it.name } ?: ""))

        /** The sanitized name, or null when nothing usable is left. */
        private fun cleanedName(raw: String?): String? {
            if (raw.isNullOrEmpty()) return null
            val normalized = runCatching { Normalizer.normalize(raw, Normalizer.Form.NFC) }
                .getOrDefault(raw)

            val stripped = buildString(normalized.length) {
                var index = 0
                while (index < normalized.length) {
                    val codePoint = normalized.codePointAt(index)
                    index += Character.charCount(codePoint)
                    when {
                        // Cc covers NUL, CR, LF, TAB, DEL and NEL: removed outright.
                        Character.getType(codePoint) == Character.CONTROL.toInt() -> Unit
                        codePoint in BIDI_CONTROLS -> Unit
                        Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint) ->
                            append(' ')
                        else -> appendCodePoint(codePoint)
                    }
                }
            }

            // Only the last path component can ever become a title, so "../../etc/passwd"
            // reduces to "passwd" and no traversal can survive into a name.
            val leaf = stripped.substringAfterLast('/').substringAfterLast('\\')
            val collapsed = leaf.replace(SPACE_RUN, " ").trim()
            if (collapsed.isEmpty() || collapsed.all { it == '.' }) return null
            return capLength(collapsed)
        }

        private val SPACE_RUN = Regex(" {2,}")

        private fun capLength(name: String): String {
            if (name.length <= MAX_NAME_CHARS) return name
            val dot = name.lastIndexOf('.')
            val extension = if (dot > 0 && name.length - dot in 2..MAX_EXTENSION_CHARS) {
                name.substring(dot)
            } else {
                ""
            }
            return truncateWholeCharacters(name, MAX_NAME_CHARS - extension.length) + extension
        }

        /** Truncates without ever leaving a lone high surrogate (astral CJK, emoji). */
        private fun truncateWholeCharacters(name: String, limit: Int): String {
            if (limit <= 0) return ""
            var end = minOf(limit, name.length)
            if (end > 0 && Character.isHighSurrogate(name[end - 1])) end--
            return name.substring(0, end)
        }
    }
}
