// Purpose: feature #117 WI-2 (#110 Phase 3) — downloads an OPDS entry's book and imports it via the
// existing Android BookImporter (re-fingerprint → canonical identity, idempotent). Picks ONLY an
// auto-importable acquisition link (generic / open-access — never buy/borrow/sample/subscribe/
// unknown), prefers EPUB, validates the bytes are actually a book (content-type + magic bytes — so
// an HTML login/error page never imports under an `.epub` name), and derives a display name whose
// EXTENSION drives BookImporter's format detection.
package com.vreader.app.opds

import com.vreader.app.data.Book
import com.vreader.app.data.BookImporter
import java.io.ByteArrayInputStream

class OpdsAcquisitionService(
    /** Downloads a resolved acquisition URL — production passes `OpdsClient::download`; tests fake it. */
    private val download: suspend (String) -> OpdsDownload,
    private val importer: BookImporter,
) {
    /**
     * Download + import [entry]'s best supported acquisition. [baseUrl] (the feed's) resolves a
     * relative href. Throws [OpdsError.UnsupportedAcquisition] if nothing is auto-importable, or
     * [OpdsError.NotABook] if the bytes aren't a supported book.
     */
    suspend fun importEntry(entry: OpdsEntry, baseUrl: String?): Book {
        val link = chooseLink(entry)
            ?: throw OpdsError.UnsupportedAcquisition("no open-access/generic acquisition for '${entry.title}'")
        val href = link.resolvedHref(baseUrl)
            ?: throw OpdsError.UnsupportedAcquisition("unresolvable href for '${entry.title}'")

        val dl = download(href)
        if (dl.contentType?.contains("text/html", ignoreCase = true) == true) {
            throw OpdsError.NotABook("server returned HTML (likely a login/error page) for '${entry.title}'")
        }
        val ext = link.formatExtension
            ?: throw OpdsError.UnsupportedAcquisition("unsupported media type ${link.type} for '${entry.title}'")
        if (!magicMatches(dl.bytes, ext)) {
            throw OpdsError.NotABook("downloaded bytes are not a valid $ext for '${entry.title}'")
        }
        return importer.importStream(
            sourceUri = "opds://$href",
            displayName = "${sanitizeTitle(entry.title)}.$ext",
            input = ByteArrayInputStream(dl.bytes),
        )
    }

    /** Best auto-importable acquisition link: prefer EPUB, then PDF, then AZW3. */
    private fun chooseLink(entry: OpdsEntry): OpdsLink? {
        val importable = entry.acquisitionLinks.filter { it.isAutoImportable && it.formatExtension != null }
        return PREFERENCE.firstNotNullOfOrNull { ext -> importable.firstOrNull { it.formatExtension == ext } }
            ?: importable.firstOrNull()
    }

    /** Cheap structural sanity check so an HTML/error page never imports as a book. */
    private fun magicMatches(bytes: ByteArray, ext: String): Boolean = when (ext) {
        "epub", "azw3" -> bytes.size >= 4 && bytes[0] == 'P'.code.toByte() && bytes[1] == 'K'.code.toByte() &&
            bytes[2] == 0x03.toByte() && bytes[3] == 0x04.toByte()  // ZIP local-file-header (EPUB/AZW3 KF8)
        "pdf" -> bytes.size >= 5 && String(bytes, 0, 5, Charsets.US_ASCII) == "%PDF-"
        else -> false
    }

    private fun sanitizeTitle(title: String): String {
        val cleaned = title.trim().replace(Regex("[^\\p{L}\\p{N} ._-]"), "_").take(80)
        return cleaned.ifBlank { "book" }
    }

    private companion object {
        val PREFERENCE = listOf("epub", "pdf", "azw3")
    }
}
