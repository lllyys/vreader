// Purpose: feature #135 WI-4 — the TXT/MD host-supplied preview seam for a bookmark row. The TXT/MD
// reader (which owns the decoded document text) implements this to hand [BookmarkPresentation] a
// bounded snippet around a stored char offset; every other format passes null (no arbitrary body
// extraction). Pure functional interface — no Android/Compose deps, no I/O contract of its own.
package com.vreader.app.reader.nav

/**
 * Supplies a short body snippet for a TXT/MD bookmark row.
 *
 * The TXT/MD host implements this over its ALREADY-DECODED, in-memory text. The implementation MUST be
 * pure and side-effect-free — a plain read against an immutable text buffer — so [BookmarkPresentation]
 * stays a deterministic, no-I/O projection (Risk-7): do NOT read files, hit the DB, or touch mutable
 * state here. [BookmarkPresentation] passes the bookmark's UTF-16 char offset (clamped non-negative) and
 * the max length it wants; the projection still clamps/single-lines/ellipsizes the returned text, so an
 * over-long or multi-line snippet is safe. Return null when no meaningful snippet is available (empty
 * document, offset past EOF).
 */
fun interface BookmarkPreviewProvider {
    /** A snippet starting near [charOffsetUTF16] (clamped >= 0), at most [maxLen] chars, or null. */
    fun snippet(charOffsetUTF16: Int, maxLen: Int): String?
}
