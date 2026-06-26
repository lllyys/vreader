// Purpose: feature #120 WI-3 (#110 Phase 3) — UI state for the OPDS browse screen (design
// `vreader-opds.jsx` `OpdsBrowse` + `OpdsError`): navigation rows (drill into sub-feeds) +
// acquisition entries with a per-entry download state, plus loading / empty / error phases.
// Stateless composables render a pure function of these.
package com.vreader.app.opds.ui

/** Browse phase: a spinner, the feed, an empty shelf, or a one-cause error. */
enum class OpdsBrowsePhase { loading, feed, empty, error }

/** The error variants the design covers, each with one cause + one CTA. */
enum class OpdsBrowseError { offline, auth, notfound, generic }

/** Per-entry download lifecycle (the design's get / downloading-radial / In-Library). */
enum class OpdsItemState { remote, downloading, library, failed }

/** A navigation row — drill into a sub-feed (folder + optional count). */
data class OpdsNavRow(val title: String, val url: String, val count: String? = null)

/** An acquisition entry — a downloadable book. [key] is stable (the entry id, or its first
 *  importable href) so download state survives list rebuilds; [index] maps back to the feed entry. */
data class OpdsEntryRow(
    val key: String,
    val index: Int,
    val title: String,
    val author: String?,
    val format: String,            // "EPUB" / "PDF" / "AZW3"
    val state: OpdsItemState,
    val failMessage: String? = null,
)

/** The browse-screen state. */
data class OpdsBrowseState(
    val title: String,
    val phase: OpdsBrowsePhase = OpdsBrowsePhase.loading,
    val errorKind: OpdsBrowseError? = null,
    val navRows: List<OpdsNavRow> = emptyList(),
    val sectionTitle: String? = null,
    val entries: List<OpdsEntryRow> = emptyList(),
    val canLoadMore: Boolean = false,
    val loadingMore: Boolean = false,
)
