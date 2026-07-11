// Purpose: The FTS-track boundary that turns a matched chunk + a located occurrence into a JUMPABLE
// canonical position — feature #133 WI-4. This is the seam the in-book search repository (WI-6) dispatches
// to for the FTS-indexed formats (TXT/MD), implemented by [TxtMdInBookHitResolver] (re-derives the offset
// from TxtDocument; the FTS index is chunk-level + location-less, so the true source offset comes from
// here). EPUB does NOT flow through this resolver at all — per the plan §4, Readium's own SearchService
// returns navigable Locators directly (WI-5's EpubInBookSearchEngine), so WI-6 branches on format and only
// the FTS track uses this seam. Keeping the resolver narrow (chunk index + raw occurrence -> canonical
// Locator?) means the repository never leaks the TxtDocument coordinate model.
//
// Key decisions:
// - The resolver returns ONLY the jumpable canonical position ([vreader.contracts.Locator]); the snippet /
//   section label / match ranges the hit-row UI needs are assembled by the repository (WI-6), which already
//   holds the matched SearchSectionEntity text + the matcher's raw spans. This keeps the resolver a pure
//   position mapper with no UI-DTO coupling.
// - A `null` return means the resolution did not produce a VALID, in-bounds locator (an out-of-range
//   sectionIndex/occurrence, or a validatedOrNull rejection) and the hit should be SKIPPED, never jumped
//   to a bogus position.
package com.vreader.app.search

import vreader.contracts.Locator

/**
 * Maps a matched FTS chunk (its [sectionIndex]) plus a located [RawOccurrence] to a jumpable canonical
 * [Locator], or `null` when the input is out of range or the resulting locator fails validation and the
 * hit should be skipped.
 *
 * This is the FTS-track (TXT/MD) resolver seam WI-6 dispatches to; EPUB resolves natively via Readium
 * (WI-5) and does not use this interface. The single implementation ([TxtMdInBookHitResolver]) re-derives
 * `charOffsetUTF16` from `TxtDocument` — no stored offset column.
 */
interface InBookSearchHitResolver {
    /**
     * Resolve the [occurrence] within the chunk at [sectionIndex] to a jumpable canonical [Locator], or
     * `null` if [sectionIndex] / [occurrence] is out of range (an occurrence past the chunk, a section past
     * the document) or the resulting locator fails validation — in which case the hit must be dropped.
     */
    fun resolve(sectionIndex: Int, occurrence: RawOccurrence): Locator?
}
