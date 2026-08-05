// Purpose: feature #165 WI-2 — writes ONE book's annotations as the versioned `annotations.json`
// cross-platform contract text (highlights + notes + bookmarks, C-12), plus the derived file name a
// destination picker is seeded with. The bytes leave the app and are handed to another program
// (iOS, a future import), so this is a contract artifact, not an internal blob.
//
// Key decisions:
//  - The wire text comes from `AnnotationBackupMapper.json(...)` (WI-1) and NOWHERE else. The
//    deterministic (bookFingerprintKey, id) sort and the record->wire mapping are part of the
//    contract's byte-stability guarantee, so an export must be the backup collector's own
//    `annotations.json` section filtered to one book — never a second, separately-assembled copy.
//    `schemaVersion` therefore comes from `BackupSchema.CURRENT_SCHEMA_VERSION` by construction.
//  - A book with no annotations still exports a VALID EMPTY envelope (C-13) — a silent no-op would
//    leave the user staring at a picker that produced nothing.
//  - `writeTo` does NOT close the sink: the caller opened it (a SAF `OutputStream`) and owns its
//    lifetime, including the close that a bounded-call gate may have to perform off-deadline.
//  - `suggestedFileName` is DERIVED from the book's title + fingerprint, never a caller-supplied
//    name, and reuses `IncomingBookResolver.sanitizeDisplayName` (the repo's answer to hostile
//    display text: leaf-only, NFC, control/bidi/lone-surrogate strip, surrogate-safe cap) rather
//    than re-deriving a weaker sanitizer here.
//
// @coordinates-with AnnotationBackupMapper (the single record->wire mapping), AnnotationsRepository
// (the per-book row reads), IncomingBookResolver.sanitizeDisplayName (the shared name sanitizer).
package com.vreader.app.annotations

import com.vreader.app.backup.AnnotationBackupMapper
import com.vreader.app.imports.IncomingBookResolver
import kotlinx.coroutines.flow.first
import java.io.OutputStream

/** Exports one book's annotations as the `annotations.json` contract section. */
class AnnotationsExportWriter(private val repo: AnnotationsRepository) {

    /** The full `annotations.json` text for ONE book (highlights + notes + bookmarks). An unknown
     *  or empty [bookKey] yields the valid empty envelope, never a failure (C-13). */
    suspend fun exportJson(bookKey: String): String = rows(bookKey).json()

    /**
     * Writes [exportJson] for [bookKey] as UTF-8 to [sink] and returns the number of annotation
     * rows written (highlights + notes + bookmarks). Flushes; deliberately does NOT close [sink].
     */
    suspend fun writeTo(sink: OutputStream, bookKey: String): Int {
        val rows = rows(bookKey)
        sink.write(rows.json().toByteArray(Charsets.UTF_8))
        sink.flush()
        return rows.count
    }

    private suspend fun rows(bookKey: String): Rows {
        val snapshot = repo.annotationsForBook(bookKey)
        return Rows(snapshot.highlights, snapshot.notes, repo.bookmarks(bookKey).first())
    }

    /** One book's three kinds, on their way to the shared mapper. */
    private class Rows(
        val highlights: List<HighlightRecord>,
        val notes: List<NoteRecord>,
        val bookmarks: List<BookmarkRecord>,
    ) {
        val count: Int get() = highlights.size + notes.size + bookmarks.size

        fun json(): String = AnnotationBackupMapper.json(highlights, notes, bookmarks)
    }

    companion object {
        /** The whole file name's cap, suffix included (#155's `IncomingBookResolver` precedent). */
        const val MAX_NAME_CHARS = 200

        private const val SUFFIX = " annotations.json"
        private const val UNNAMED = "annotations.json"
        private const val FINGERPRINT_PREFIX_CHARS = 8

        /**
         * `"<sanitized title> annotations.json"` — CJK/RTL letters preserved, path separators and
         * control/bidi characters stripped, capped at [MAX_NAME_CHARS] without splitting a
         * surrogate pair, and always ending in `.json`.
         *
         * When the title is null/blank/fully-stripped it falls back to the fingerprint's sha
         * prefix. Note the one accepted collision: `sanitizeDisplayName` reports "nothing usable"
         * only by returning its own `FALLBACK_NAME`, so a book literally titled *Untitled* also
         * gets the sha-prefixed name — correct, merely less pretty.
         */
        fun suggestedFileName(bookTitle: String?, bookKey: String): String {
            val base = titleBase(bookTitle) ?: fingerprintBase(bookKey)
            return if (base.isEmpty()) UNNAMED else base + SUFFIX
        }

        /** The sanitized title, or null when nothing usable survived sanitization. */
        private fun titleBase(bookTitle: String?): String? {
            if (bookTitle.isNullOrBlank()) return null
            val cleaned = IncomingBookResolver.sanitizeDisplayName(bookTitle, format = null)
            if (cleaned == IncomingBookResolver.FALLBACK_NAME) return null
            return cap(cleaned)
        }

        /** The fingerprint key's sha segment, prefix-trimmed — `""` for a key with no sha. */
        private fun fingerprintBase(bookKey: String): String =
            bookKey.substringAfter(':', "")
                .substringBefore(':')
                .filter { it.isLetterOrDigit() }
                .take(FINGERPRINT_PREFIX_CHARS)

        /** Caps [base] so `base + SUFFIX` fits [MAX_NAME_CHARS], never splitting a surrogate pair
         *  (astral CJK, emoji) and never leaving a trailing space before the suffix. */
        private fun cap(base: String): String {
            val limit = MAX_NAME_CHARS - SUFFIX.length
            if (base.length <= limit) return base
            var end = limit
            if (end > 0 && Character.isHighSurrogate(base[end - 1])) end--
            return base.substring(0, end).trimEnd()
        }
    }
}
