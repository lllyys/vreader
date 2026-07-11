// Purpose: The host-agnostic table-of-contents source seam for the reader Contents
// sheet (feature #132 WI-1). A [ReadiumTocProvider] supplies the flattened TOC for
// EPUB; [EmptyTocProvider] is the no-TOC provider for TXT/MD/PDF/AZW3 hosts.
package com.vreader.app.reader.nav

/** Supplies a book's flattened table of contents as [TocEntry] rows. */
fun interface TocProvider {
    /** The flattened TOC (top-to-bottom, depth-tagged), or an empty list when none. */
    suspend fun toc(): List<TocEntry>
}
