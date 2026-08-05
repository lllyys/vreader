// Purpose: The no-TOC provider for reader hosts without a bridged outline — feature
// #132 WI-1. That is PDF alone now: TXT/MD gained [TxtMdTocProvider] (feature #139)
// and AZW3/MOBI/KF8 gained [FoliateTocProvider] (feature #140). Its Contents sheet
// renders the empty state.
package com.vreader.app.reader.nav

/** A [TocProvider] that always yields an empty table of contents. */
object EmptyTocProvider : TocProvider {
    override suspend fun toc(): List<TocEntry> = emptyList()
}
