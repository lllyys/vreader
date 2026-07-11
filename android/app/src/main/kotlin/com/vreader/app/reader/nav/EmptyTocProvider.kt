// Purpose: The no-TOC provider for reader hosts without a bridged outline
// (TXT/MD/PDF/AZW3) — feature #132 WI-1. Its Contents sheet renders the empty state.
package com.vreader.app.reader.nav

/** A [TocProvider] that always yields an empty table of contents. */
object EmptyTocProvider : TocProvider {
    override suspend fun toc(): List<TocEntry> = emptyList()
}
