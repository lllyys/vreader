// Purpose: The TXT/MD implementation of [InBookSearchHitResolver] — feature #133 WI-4. Maps a matched
// TXT/MD chunk + a raw occurrence to a jumpable canonical position via the DETERMINISTIC re-derivation the
// round-2 Critical-2 resolution relies on: `charOffsetUTF16 = TxtDocument.offsetForChunk(sectionIndex) +
// occurrence.startUtf16`. No stored offset column is needed because TXT/MD chunking is a PURE function of
// the decoded source text — `TxtDocument.of(decodedText)` re-derives the exact chunk boundaries the FTS
// extractor (TxtMdTextExtractor) used, so `chunkForOffset(resolvedOffset)` round-trips back to the matched
// `sectionIndex`. The FTS index is chunk-level + location-less; this is where the true raw source offset
// comes from (RawOffsetMatcher located the intra-chunk span; this adds the chunk start).
//
// Key decisions:
// - The TxtDocument is built ONCE (lazy) from the caller-provided decoded text and reused across every
//   hit in a session, so a page of N hits re-scans the source at most once — the memoized-per-session
//   contract from the plan. The caller (WI-6 repository) owns decoding via TxtDecoder and passes the text.
// - The occurrence's raw span becomes both the jump anchor (`charOffsetUTF16`) AND the highlight range
//   (`charRangeStartUTF16`/`charRangeEndUTF16`), shifted by the chunk start — the same identity triple +
//   offset shape the TXT/MD host builds for a bookmark/resume (txtBookmarkLocator).
// - `validatedOrNull()` gates the result: a corrupt/out-of-range occurrence (negative offset, inverted
//   range) yields `null` and the hit is skipped rather than jumped to a bogus position.
package com.vreader.app.search

import com.vreader.app.reader.TxtDocument
import vreader.contracts.Locator

/**
 * Resolves TXT/MD in-book search hits to jumpable canonical [Locator]s by re-deriving the chunk start
 * from [decodedText] (a pure function — no stored offsets) and adding the occurrence's raw UTF-16 span.
 *
 * @param contentSHA256 the book's content SHA-256 (identity triple)
 * @param fileByteCount the book's byte count (identity triple)
 * @param format the book's format raw value ("txt" / "md")
 * @param decodedText the FULL decoded book text (the same text TxtMdTextExtractor chunked)
 */
class TxtMdInBookHitResolver(
    private val contentSHA256: String,
    private val fileByteCount: Long,
    private val format: String,
    decodedText: String,
) : InBookSearchHitResolver {

    // Re-derive the chunk boundaries ONCE from the decoded source (pure, deterministic); reused per session.
    private val document: TxtDocument by lazy { TxtDocument.of(decodedText) }

    override fun resolve(sectionIndex: Int, occurrence: RawOccurrence): Locator? {
        val chunkStart = document.offsetForChunk(sectionIndex)
        val start = chunkStart + occurrence.startUtf16
        val end = chunkStart + occurrence.endUtf16
        return Locator(
            contentSHA256 = contentSHA256,
            fileByteCount = fileByteCount,
            format = format,
            charOffsetUTF16 = start,
            charRangeStartUTF16 = start,
            charRangeEndUTF16 = end,
        ).validatedOrNull()
    }
}
