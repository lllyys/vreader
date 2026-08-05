// Purpose: The [TocProvider] for the foliate-js (AZW3/MOBI/KF8) host — it flattens the nested
// [FoliateTocItem] tree the bundle already ships on every `book-ready` into the Contents sheet's
// [TocEntry] rows (feature #140 WI-2). The Kindle counterpart of [ReadiumTocProvider] (EPUB) and
// [TxtMdTocProvider] (TXT/MD); [EmptyTocProvider] then serves PDF alone.
//
// Pipeline:
//   book-ready.toc ──FoliateTocParser.parse──► List<FoliateTocItem>  (bounded, verbatim)
//                                                     │
//                                                     ▼   depth-first, trim, skip-but-recurse
//                                              List<TocEntry>  ──► TocContentsSheet / goTo
//
// Key decisions:
// - SEMANTICS ARE iOS #38's, ported from FoliateTOCConverter.swift: depth-first with the parent
//   emitted BEFORE its children, `depth` incremented once per nesting level, labels trimmed, and a
//   blank label or blank href SKIPS the row while STILL WALKING its subitems. That last rule is iOS
//   bug #262's round-1 fix — `serializeTOC` writes a missing href as `''`, which would otherwise
//   produce a tappable row whose navigation no-ops, and an unlabelled container parenting real
//   chapters is a common TOC shape. A skipped node still counts as a nesting level, so its children
//   keep the indentation the author intended.
// - THE LOCATOR SHAPE DELIBERATELY DIVERGES FROM iOS: rows carry `progression = null`, never iOS's
//   `0.0` (plan §5.2 defense 2). The value is dead on iOS — `FoliateNavSeek.navigationTarget` is
//   cfi → href → nil with no progression leg — but Android's [FoliateGoToTarget.from] HAS one, so a
//   `0.0` would resolve every chapter tap to `Fraction(0.0)`: a jump to the START of the book that
//   foliate still acks `ok:true`, dismissing the sheet on a completely broken jump. WI-3's
//   cfi → href → progression precedence is the other, INDEPENDENT defense; this one must hold even
//   if that precedence is ever reordered. Pinned by `FoliateTocProviderTest.entryLocator_hasNoProgression`.
// - HREFS ARE OPAQUE AND CARRIED BYTE-FOR-BYTE — no trim, no normalization, no re-encoding. They are
//   foliate's own navigation tokens (an EPUB-relative path the bundle already `decodeURI`d, possibly
//   with a `#fragment`/query/non-ASCII characters; a KF8 `kindle:pos:fid:…:off:…`; a MOBI6
//   `filepos:NNNN`). WI-3 hands the value straight to `readerAPI.goTo` and WI-4 matches
//   `relocate.tocHref` byte-exactly, so tidying one here would break navigation or the
//   current-chapter highlight one WI later. Only BLANKNESS is judged (a whitespace-only href is not
//   navigable); the surviving string is never rewritten.
// - `pageLabel` is null (this host has no page model — Book Details passes `pageCount = null`, and
//   `TocSheetRows` renders `p. N` only when non-null) and `epubReadiumLocator` is null (non-Readium
//   host). The locator's `format` leg READS `book.originalFormat` rather than spelling `"azw3"`, so
//   `.azw`/`.mobi`/`.prc` rows key exactly like the same book's bookmarks.
// - An EMPTY list is the "hide the Contents control" signal, not an error: `ReaderChromeScaffold`
//   derives the control's visibility from `tocEntries.isEmpty()`, so a book with no usable TOC
//   behaves exactly as it did before this feature.
// - THIS type owns the `withContext(dispatcher)` hop on an INJECTED dispatcher (rule 50 §12.1); the
//   host must not wrap the call and nothing here may hardcode Dispatchers.IO/Default.
// - Nothing is persisted: the tree is derived from a message already in flight at book-open.
//
// @coordinates-with: TocProvider.kt, TocEntry.kt, ../foliate/FoliateTocItem.kt,
//                    ../foliate/FoliateTocParser.kt, ../foliate/FoliateBridge.kt (FoliateGoToTarget)
package com.vreader.app.reader.nav

import com.vreader.app.data.Book
import com.vreader.app.reader.foliate.FoliateTocItem
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import vreader.contracts.Locator
import kotlin.coroutines.coroutineContext

/**
 * Builds the Contents rows for a foliate-hosted book (AZW3/MOBI/KF8).
 *
 * @param items      the parsed TOC tree exactly as `book-ready` delivered it —
 *                   `FoliateTocParser.parse`'s output, already bounded in node count and nesting
 *                   depth (`MAX_TOC_ENTRIES` / `MAX_TOC_DEPTH`), which is what keeps this walk's
 *                   recursion shallow. This provider adds no bound of its own: a second, differently
 *                   worded cap would be a second policy.
 * @param book       the identity source for every row's canonical locator.
 * @param dispatcher the background dispatcher this provider hops onto; injected so tests and the
 *                   host control it (rule 50 §12.1 — never a hardcoded dispatcher).
 */
class FoliateTocProvider(
    private val items: List<FoliateTocItem>,
    private val book: Book,
    private val dispatcher: CoroutineDispatcher,
) : TocProvider {

    /**
     * The book's chapter rows in depth-first order, or an empty list when the tree holds no usable
     * node — the documented "hide the Contents control" signal, not an error.
     *
     * @throws kotlinx.coroutines.CancellationException if the calling coroutine is cancelled; the
     *         walk checks before every node, so closing the reader mid-flatten stops promptly.
     */
    override suspend fun toc(): List<TocEntry> = withContext(dispatcher) {
        val rows = ArrayList<TocEntry>()
        flatten(items, depth = 0, into = rows)
        rows
    }

    /**
     * Depth-first walk: emit the node's row (when it has one) BEFORE descending, and descend
     * regardless of whether the row was emitted — a skipped container still parents real chapters,
     * and still counts as a nesting level for them.
     */
    private suspend fun flatten(nodes: List<FoliateTocItem>, depth: Int, into: MutableList<TocEntry>) {
        for (node in nodes) {
            coroutineContext.ensureActive()
            entryFor(node, depth)?.let(into::add)
            if (node.subitems.isNotEmpty()) {
                flatten(node.subitems, depth + 1, into)
            }
        }
    }

    /**
     * One node's row, or null when the node is not itself displayable/navigable: a label that is
     * blank once trimmed, or a blank href (both of which `serializeTOC` can legitimately emit).
     */
    private fun entryFor(node: FoliateTocItem, depth: Int): TocEntry? {
        val title = node.label.trim()
        if (title.isEmpty() || node.href.isBlank()) return null

        // `href` is the ONLY position field: no progression (see the header), no cfi, no page, no
        // offsets — so this locator's only jump target is the href, on every resolution path.
        // `validatedOrNull` is the same construction-site guard the other locator builders use; with
        // no numeric field set it cannot reject today, and it stays so a future field cannot slip an
        // invalid locator into a row unnoticed.
        val locator = Locator(
            contentSHA256 = book.contentSHA256,
            fileByteCount = book.fileByteCount,
            format = book.originalFormat.name,
            href = node.href,
        ).validatedOrNull() ?: return null

        return TocEntry(
            title = title,
            depth = depth,
            pageLabel = null,
            canonicalLocator = locator,
            epubReadiumLocator = null,
        )
    }
}
