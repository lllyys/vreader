// Purpose: feature #116 WI-2 (#110 Phase 3) — maps (format, sha256, byteCount) ↔ the WebDAV-safe
// content-addressed blob path, byte-for-byte the iOS `BlobPath` (vreader/Services/Backup/
// BlobPath.swift) so an Android backup's blobs land where iOS restore looks and vice-versa.
//
// Layout: VReader/books/<format>/<sha256>_<byteCount>.<canonicalExt>
// The path uses only [0-9a-f_./] (no colons — some WebDAV proxies/shares mangle them); the
// canonical fingerprintKey stays inside the manifest as pure data. originalExtension is NOT in
// the path — .mobi/.prc/.azw for one SHA collapse to the canonical .azw3 blob; the original
// extension travels in the manifest. The BookFormat enum names ARE the canonical extensions
// (epub/pdf/txt/md/azw3 = iOS `BookFormat.fileExtensions.first`).
package com.vreader.app.backup.archive

import vreader.contracts.BookFormat

object BlobPath {
    /** Top-level dir for content-addressed book blobs — pinned (changing it invalidates every
     *  previously-uploaded backup). Matches iOS `BlobPath.booksRoot`. */
    const val BOOKS_ROOT = "VReader/books"

    /** `VReader/books/<format>/<sha256>_<byteCount>.<canonicalExt>`. */
    fun make(format: BookFormat, sha256: String, byteCount: Long): String =
        "$BOOKS_ROOT/${format.name}/${sha256}_$byteCount.${format.name}"

    /** Inverse of [make]; null if the path doesn't match the layout, the format is unknown, the
     *  SHA isn't 64 hex chars, or the byte count isn't a non-negative integer. */
    fun parse(path: String): Triple<BookFormat, String, Long>? {
        val prefix = "$BOOKS_ROOT/"
        if (!path.startsWith(prefix)) return null
        val trail = path.removePrefix(prefix)
        val segments = trail.split("/")
        if (segments.size != 2) return null
        val format = runCatching { BookFormat.valueOf(segments[0]) }.getOrNull() ?: return null
        val filename = segments[1]
        val dot = filename.lastIndexOf('.')
        if (dot <= 0) return null  // require an extension and a non-empty stem
        // The extension MUST be the format's canonical ext — `make` always emits it, so a path
        // like `books/epub/<sha>_10.pdf` or `books/azw3/<sha>_10.mobi` is NOT our layout.
        if (filename.substring(dot + 1) != format.name) return null
        val stem = filename.substring(0, dot)
        val parts = stem.split("_")
        if (parts.size != 2) return null
        val sha = parts[0]
        val bytes = parts[1].toLongOrNull() ?: return null
        if (!isValidSha256(sha) || bytes < 0) return null
        return Triple(format, sha, bytes)
    }

    private fun isValidSha256(s: String): Boolean =
        s.length == 64 && s.all { it in '0'..'9' || it in 'a'..'f' }
}
