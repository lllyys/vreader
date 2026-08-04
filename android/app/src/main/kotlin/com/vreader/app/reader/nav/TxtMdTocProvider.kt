// Purpose: The [TocProvider] for the two non-Readium text formats — it turns an already-decoded
// TXT or MD document into the Contents sheet's [TocEntry] rows (feature #139 WI-4). The
// TXT/MD counterpart of [ReadiumTocProvider]; [EmptyTocProvider] still serves PDF and AZW3.
//
// Pipeline:
//   txt ──TxtTocRuleEngine.detectBestRule──► winning rule ──extractHeadings(cap+1)──┐
//   md  ──MdTocScanner.scan(cap+1)───────────────────────────────────────────────────┤
//                                                                                    ▼
//                                            applyCap ──► List<DetectedHeading> ──► List<TocEntry>
//
// Key decisions:
// - DETECTION POLICY IS EXACTLY iOS's: the engine's `>= 2` match threshold plus [MAX_TOC_ENTRIES].
//   There is deliberately NO density guard, NO saturation guard, NO ambiguous-rule set and NO
//   format-specific exemption — plan §4.4 (Option A) DELETED that machinery after four Gate-2
//   rounds failed to make an invented heuristic sound, and iOS ships none across features #23/#12.
//   A mis-detected TOC is then ugly rather than harmful: the cap bounds memory, and WI-6 makes the
//   Contents sheet lazy so it bounds rendering too — WI-6 lands BEFORE WI-7 wires this provider to
//   a host, so no user can reach a large TOC through today's eager sheet.
//   `TxtMdTocProviderTest.noDensityOrSaturationGuardExists` pins the deletion; if a real book ever
//   needs a guard it is designed FROM that failure (follow-up F6), not before it.
// - The cap REJECTS rather than truncates. A Contents list that silently stops at entry 50 000 of a
//   larger book is worse than none, because the user cannot tell it is incomplete.
// - Both scanners are called with `MAX_TOC_ENTRIES + 1`, so [ExtractResult.hitLimit] reads exactly
//   as "more than the cap" AND the scan stops there — a pathological document is never fully
//   materialized. Neither scanner supplies a default limit, precisely so this budget is stated here.
// - A row's `canonicalLocator` is built by CALLING `txtBookmarkLocator` — the same function #135's
//   bookmarks and the resume seam use — rather than by re-spelling its fields. Construction
//   identity is the point: a TOC row and a bookmark at one source offset must be one position.
//   Note this makes the locator's `format` leg `book.originalFormat`, not [format] (which only
//   routes); the host passes the canonical fingerprint-parsed format for routing (bug #246).
// - `pageLabel` is null (no page in scroll layout; the #138 paged index is windowed, so labelling
//   every entry would force a measure of the whole book at sheet-build time) and
//   `epubReadiumLocator` is null (non-Readium host). TXT depth is flat 0 (plan §4.3); MD carries
//   the scanner's real heading level, which `TocSheetRows` renders as indentation.
// - An EMPTY list is the "hide the Contents control" signal, not an error: `ReaderChromeScaffold`
//   derives the control's visibility from `tocEntries.isEmpty()`. A format this provider does not
//   serve therefore degrades to "no Contents" rather than throwing inside a working reader.
// - THIS type owns the `withContext(dispatcher)` hop on an INJECTED dispatcher (plan §4.5); the
//   host must not wrap the call, and nothing here may hardcode Dispatchers.IO/Default. Everything
//   it calls is pure CPU work that must not run on the main thread.
//
// @coordinates-with: TocProvider.kt, TocEntry.kt, TxtTocRuleEngine.kt, MdTocScanner.kt,
//                    DetectedHeading.kt, ../TxtReaderActivity.kt (txtBookmarkLocator)
package com.vreader.app.reader.nav

import com.vreader.app.data.Book
import com.vreader.app.reader.txtBookmarkLocator
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import vreader.contracts.BookFormat

/**
 * Builds the auto-generated table of contents for a TXT or MD book.
 *
 * @param text       the FULL decoded document — the same `String` the reader already holds
 *                   (`TxtDocument.text`), so the scan adds no new memory or I/O class.
 * @param book       the identity source for every row's canonical locator.
 * @param format     which scanner to run. Anything other than `txt`/`md` yields an empty TOC.
 * @param dispatcher the background dispatcher this provider hops onto; injected so tests and the
 *                   host control it (rule 50 §12.1 — never a hardcoded dispatcher).
 */
class TxtMdTocProvider(
    private val text: String,
    private val book: Book,
    private val format: BookFormat,
    private val dispatcher: CoroutineDispatcher,
) : TocProvider {

    /**
     * The book's chapter rows, or an empty list when it has no detectable headings — or more than
     * [MAX_TOC_ENTRIES] of them.
     *
     * @throws kotlinx.coroutines.CancellationException if the calling coroutine is cancelled; both
     *         scanners are cancellation-cooperative, so closing the reader mid-scan stops promptly.
     */
    override suspend fun toc(): List<TocEntry> = withContext(dispatcher) {
        val result = when (format) {
            BookFormat.txt -> {
                val rule = TxtTocRuleEngine.detectBestRule(text) ?: return@withContext emptyList()
                TxtTocRuleEngine.extractHeadings(text, rule, SCAN_LIMIT)
            }
            BookFormat.md -> MdTocScanner.scan(text, SCAN_LIMIT)
            else -> return@withContext emptyList()
        }
        applyCap(result).map(::toEntry)
    }

    private fun toEntry(heading: DetectedHeading): TocEntry = TocEntry(
        title = heading.title,
        depth = heading.depth,
        pageLabel = null,
        canonicalLocator = txtBookmarkLocator(book, heading.sourceOffsetUtf16),
        epubReadiumLocator = null,
    )

    companion object {
        /**
         * The most entries a Contents list may hold. Above this the TOC is REJECTED, never
         * truncated.
         *
         * Sized to sit above any plausible real book — Chinese web novels reach 20 000–30 000
         * chapters — while bounding memory (50 000 × ~80 B ≈ 4 MB) and staying renderable by the
         * lazy sheet. This is a memory/sanity backstop, NOT a mis-detection heuristic.
         */
        const val MAX_TOC_ENTRIES: Int = 50_000

        /**
         * The budget handed to both scanners. `cap + 1` is what makes [ExtractResult.hitLimit] mean
         * "more than [MAX_TOC_ENTRIES] exist" while stopping the scan one heading past the cap.
         */
        private const val SCAN_LIMIT: Int = MAX_TOC_ENTRIES + 1

        /**
         * The ENTIRE post-scan policy: keep everything, or — if the scan hit its limit, i.e. the
         * document has more than [MAX_TOC_ENTRIES] headings — keep nothing.
         *
         * It reads only [ExtractResult.hitLimit]: no entry count, no line count, no ratio, no
         * format and no rule identity. That is the shape plan §4.4 settled on, and a change here is
         * a change to the plan.
         */
        internal fun applyCap(result: ExtractResult): List<DetectedHeading> =
            if (result.hitLimit) emptyList() else result.headings
    }
}
