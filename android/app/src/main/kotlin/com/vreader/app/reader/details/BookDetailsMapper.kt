// Purpose: feature #134 WI-1 — the pure Book -> BookDetailsUiModel mapper. A PURE JVM object with NO
// Android/Compose deps (rule 50 boundary): callable and testable off any thread with no Context. Mirrors
// the iOS BookDetailsViewModel field map — fingerprintFull/Display (§fingerprint), an SI byte-size label
// with a 0/negative -> "Unknown" override (§size-formatting), a format label (md -> "Markdown"), a
// truthful relative location (§location), tags = collection names, and a PDF-only pages label
// (§page-count). Year/cover are ALWAYS-absent (no data source) so they never appear (§details-source).
package com.vreader.app.reader.details

import com.vreader.app.data.Book
import vreader.contracts.BookFormat
import java.io.File
import java.util.Locale

object BookDetailsMapper {

    /**
     * Map a [book] (+ its [collectionNames] and an optional [pageCount]) to the sheet's UI model.
     *
     * @param collectionNames the ordered collection names the book belongs to (empty when none).
     * @param pageCount the real page count, supplied ONLY by the PDF host; null everywhere else.
     */
    fun map(book: Book, collectionNames: List<String>, pageCount: Int?): BookDetailsUiModel =
        BookDetailsUiModel(
            title = book.title,
            author = book.author,
            tags = collectionNames,
            formatLabel = formatLabel(book.originalFormat),
            sizeLabel = sizeLabel(book.fileByteCount),
            pagesLabel = pageCount?.toString(),
            fingerprintDisplay = middleTruncate(book.fingerprintKey),
            fingerprintFull = book.fingerprintKey,
            locationLabel = book.localFilePath?.let { "Books/${File(it).name}" },
        )

    /** "Markdown" for md; the uppercased raw value otherwise (EPUB/PDF/TXT/AZW3). */
    private fun formatLabel(format: BookFormat): String = when (format) {
        BookFormat.md -> "Markdown"
        else -> format.name.uppercase(Locale.US)
    }

    /**
     * A human-readable SI (decimal-divisor) byte-size label, matching the platform `.file` count style
     * (the existing WebDavBackupService.sizeLabel precedent) — kept Context-free so the mapper stays pure.
     * A 0 or negative byte count reports "Unknown" (the iOS ViewModel override), never "0 B"/"Zero KB".
     */
    private fun sizeLabel(bytes: Long): String = when {
        bytes <= 0L -> "Unknown"
        bytes >= 1_000_000L -> String.format(Locale.US, "%.1f MB", bytes / 1_000_000.0)
        bytes >= 1_000L -> String.format(Locale.US, "%.0f KB", bytes / 1_000.0)
        else -> "$bytes B"
    }

    /**
     * The canonical key for display: shown verbatim when short (<= [DISPLAY_MAX]), otherwise
     * middle-truncated `take(14)…takeLast(8)` (the iOS truncateFingerprint thresholds).
     */
    private fun middleTruncate(key: String): String =
        if (key.length <= DISPLAY_MAX) key else key.take(14) + "…" + key.takeLast(8)

    private const val DISPLAY_MAX = 28
}
