// Purpose: The host-agnostic table-of-contents source seam for the reader Contents
// sheet (feature #132 WI-1). Three implementations supply real rows —
// [ReadiumTocProvider] (EPUB), [TxtMdTocProvider] (TXT/MD, feature #139) and
// [FoliateTocProvider] (AZW3/MOBI/KF8, feature #140) — and [EmptyTocProvider] is the
// no-TOC provider for PDF, the one remaining host with no outline.
package com.vreader.app.reader.nav

/** Supplies a book's flattened table of contents as [TocEntry] rows. */
fun interface TocProvider {
    /** The flattened TOC (top-to-bottom, depth-tagged), or an empty list when none. */
    suspend fun toc(): List<TocEntry>
}
