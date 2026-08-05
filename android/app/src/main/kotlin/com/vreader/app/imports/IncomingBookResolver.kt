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
//   * OWNERSHIP IS EXPLICIT ACROSS THE DISPATCHER HAND-OFF. The stream is closed on every
//     exit except the one that delivers it, INCLUDING a cancellation that discards
//     `withContext`'s result after the block already completed.
//
// Known limitation (not fixable inside this file): `query` / `openInputStream` / `getType`
// and the sniffer's probe read are synchronous and uninterruptible, so a provider that
// blocks forever stalls resolution. Plan D8 puts the stall watchdog in the COORDINATOR,
// which only sees an item after resolution finished — the gap is a cross-WI design issue,
// not a defect this file can close.
//
// @coordinates-with: BookMagicSniffer (step 4), ImportActivity (WI-5: the caller that owns
//   the URI grant and must close every returned stream), BookImporter.importStream
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
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.cancellation.CancellationException

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
    /**
     * `uri.toString()` capped to [IncomingBookResolver.MAX_SOURCE_URI_CHARS]. Enforced as a
     * construction invariant, not just a convention at the one assignment site, so a caller
     * that re-derives this from `uri.toString()` (silently discarding the cap) fails loudly
     * instead of persisting an unbounded attacker-controlled string.
     */
    val sourceUri: String,
    /** `OpenableColumns.SIZE`; null when absent or negative. */
    val declaredSize: Long?,
    val stream: InputStream,
) {
    init {
        require(sourceUri.length <= IncomingBookResolver.MAX_SOURCE_URI_CHARS) {
            "sourceUri exceeds ${IncomingBookResolver.MAX_SOURCE_URI_CHARS} chars"
        }
    }
}

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
    suspend fun resolveAndOpen(uri: Uri): PendingImport? {
        // `withContext` DISCARDS its result and throws CancellationException if the caller
        // is cancelled after the block completed but before the value is delivered — the
        // documented pitfall of returning a closeable from it. The block's own catch never
        // sees that cancellation, so the stream would end up with no owner at all. This
        // reference carries ownership across the hand-off; the finally closes anything the
        // caller never received.
        val undelivered = AtomicReference<InputStream?>(null)
        var delivered = false
        try {
            val pending = withContext(ioDispatcher) { resolveBlocking(uri, undelivered) }
            delivered = true
            return pending
        } finally {
            if (!delivered) undelivered.getAndSet(null)?.let { closeQuietly(it) }
        }
    }

    /** The blocking body. Owns the stream until it publishes it to [undelivered]. */
    private fun resolveBlocking(
        uri: Uri,
        undelivered: AtomicReference<InputStream?>,
    ): PendingImport? {
        // A provider may refuse `query` yet allow `openInputStream`. Losing the name costs
        // us step 1; it must not cost us the book, so the later steps still run.
        val metadata = providerCall { queryMetadata(uri) } ?: IncomingMetadata(null, null)

        val opened = openOrNull(uri) ?: return null

        // From here the stream is OWNED. `owned` starts as the raw stream and only becomes
        // the wrapper once that wrapper exists, so a hostile `markSupported()` or a failed
        // allocation cannot strand the open descriptor between the two.
        var owned: InputStream = opened
        try {
            // Sniffing needs mark/reset. Wrapping (never rejecting) keeps providers that
            // hand back a plain FileInputStream working.
            val stream = if (opened.markSupported()) {
                opened
            } else {
                BufferedInputStream(opened, BookMagicSniffer.PROBE_BYTES * 2).also { owned = it }
            }

            val declaredName = cleanedName(metadata.displayName)
            val nameFormat = declaredName?.let { DocumentFingerprint.formatForFilename(it) }
            val segmentName = if (nameFormat == null) {
                cleanedName(providerCall { uri.lastPathSegment })
            } else {
                null
            }
            val segmentFormat = segmentName?.let { DocumentFingerprint.formatForFilename(it) }

            val format = nameFormat                                                  // 1
                ?: segmentFormat                                                     // 2
                ?: formatForMimeType(providerCall { resolver.getType(uri) })         // 3
                ?: BookMagicSniffer.sniff(stream)                                    // 4
                ?: throw ImportException.UnsupportedFormat(                          // 5
                    declaredName ?: segmentName ?: FALLBACK_NAME,
                )

            val pending = PendingImport(
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
            // Constructed successfully: hand ownership to the cross-boundary guard.
            undelivered.set(owned)
            return pending
        } catch (t: Throwable) {
            // Every non-delivering exit closes: UnsupportedFormat, a hostile provider's
            // RuntimeException, a failed PendingImport invariant, and cancellation alike.
            closeQuietly(owned)
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

    /**
     * A step that consults the (attacker-influenced) provider. An ordinary failure costs
     * that step only. Cancellation is RETHROWN — `runCatching` would swallow it and quietly
     * carry on doing work for a caller that is gone — and JVM errors keep propagating.
     */
    private inline fun <T> providerCall(block: () -> T): T? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    private fun closeQuietly(stream: InputStream) {
        try {
            stream.close()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // A provider that fails to release is not something the caller can act on.
        }
    }

    companion object {
        const val MAX_NAME_CHARS = 200
        const val MAX_SOURCE_URI_CHARS = 2048
        const val FALLBACK_NAME = "Untitled"

        /** Longest tail (dot included) still treated as an extension worth preserving. */
        private const val MAX_EXTENSION_CHARS = 16

        /**
         * Defensive bound applied to the RAW provider name before any normalization. The
         * 200-char cap alone is applied too late: NFC normalization, the filtering
         * StringBuilder and the whitespace regex would each allocate an attacker-sized
         * copy first. Generous enough that no real name is affected before the real cap.
         */
        private const val MAX_RAW_NAME_CHARS = 8192

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

        private val SPACE_RUN = Regex(" {2,}")

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
         * A provider-supplied name made safe to show and to derive a title from: reduced to
         * its last path component, NFC normalized, control / bidi-control / lone-surrogate
         * code points removed, whitespace runs collapsed, trimmed, and capped at
         * [MAX_NAME_CHARS] with the extension preserved and no surrogate pair split.
         *
         * CJK and RTL LETTERS survive untouched — only control characters are removed. When
         * nothing usable remains the result is [FALLBACK_NAME] plus [format]'s extension.
         */
        fun sanitizeDisplayName(raw: String?, format: BookFormat? = null): String =
            cleanedName(raw) ?: (FALLBACK_NAME + (format?.let { "." + it.name } ?: ""))

        /** The sanitized name, or null when nothing usable is left. */
        private fun cleanedName(raw: String?): String? {
            if (raw.isNullOrEmpty()) return null

            // Leaf first, then a raw bound: only the last path component can ever become a
            // title, so "../../etc/passwd" reduces to "passwd" and no traversal survives —
            // and everything downstream works on a bounded string. NFC never introduces or
            // removes an ASCII separator, so splitting before normalizing is equivalent.
            val leaf = raw.substringAfterLast('/').substringAfterLast('\\')
            val bounded = capLength(leaf, MAX_RAW_NAME_CHARS)

            val normalized = runCatching { Normalizer.normalize(bounded, Normalizer.Form.NFC) }
                .getOrDefault(bounded)

            val stripped = buildString(normalized.length) {
                var index = 0
                while (index < normalized.length) {
                    val codePoint = normalized.codePointAt(index)
                    index += Character.charCount(codePoint)
                    when {
                        // Cc covers NUL, CR, LF, TAB, DEL and NEL: removed outright.
                        Character.getType(codePoint) == Character.CONTROL.toInt() -> Unit
                        codePoint in BIDI_CONTROLS -> Unit
                        // An UNPAIRED surrogate; a valid pair arrives as one astral code
                        // point and is kept. Malformed UTF-16 must not reach a title.
                        codePoint in 0xD800..0xDFFF -> Unit
                        Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint) ->
                            append(' ')
                        else -> appendCodePoint(codePoint)
                    }
                }
            }

            val collapsed = stripped.replace(SPACE_RUN, " ").trim()
            if (collapsed.isEmpty() || collapsed.all { it == '.' }) return null
            return capLength(collapsed, MAX_NAME_CHARS)
        }

        private fun capLength(name: String, limit: Int): String {
            if (name.length <= limit) return name
            val dot = name.lastIndexOf('.')
            val extension = if (dot > 0 && name.length - dot in 2..MAX_EXTENSION_CHARS) {
                name.substring(dot)
            } else {
                ""
            }
            return truncateWholeCharacters(name, limit - extension.length) + extension
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
