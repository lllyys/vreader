// Purpose: The format-agnostic boundary that turns a matched chunk + a located occurrence into a
// JUMPABLE canonical position — feature #133 WI-4. The in-book search repository (WI-6) dispatches to a
// per-format implementation: TXT/MD via [TxtMdInBookHitResolver] (this WI — re-derives the offset from
// TxtDocument, the FTS index is chunk-level + location-less), EPUB via the Readium engine (WI-5 — Readium
// returns navigable Locators directly, no offset math). Keeping the seam narrow (chunk index + raw
// occurrence -> canonical Locator?) lets both tracks fit the same dispatch without leaking either engine's
// coordinate model into the repository.
//
// Key decisions:
// - The resolver returns ONLY the jumpable canonical position ([vreader.contracts.Locator]); the snippet /
//   section label / match ranges the hit-row UI needs are assembled by the repository (WI-6), which already
//   holds the matched SearchSectionEntity text + the matcher's raw spans. This keeps the resolver a pure
//   position mapper with no UI-DTO coupling.
// - A `null` return means the resolution did not produce a VALID locator (validatedOrNull rejected it — a
//   corrupt/out-of-range occurrence) and the hit should be SKIPPED, never jumped to a bogus position.
package com.vreader.app.search

import vreader.contracts.Locator

/**
 * Maps a matched chunk (its [sectionIndex]) plus a located [RawOccurrence] to a jumpable canonical
 * [Locator], or `null` when the resolution fails validation and the hit should be skipped.
 *
 * Format-agnostic: the TXT/MD implementation re-derives `charOffsetUTF16` from `TxtDocument`; a future
 * EPUB implementation (WI-5) backs the same seam with Readium's navigable locators.
 */
interface InBookSearchHitResolver {
    /**
     * Resolve the [occurrence] within the chunk at [sectionIndex] to a jumpable canonical [Locator],
     * or `null` if the resulting locator is invalid (out-of-range / corrupt) and the hit must be dropped.
     */
    fun resolve(sectionIndex: Int, occurrence: RawOccurrence): Locator?
}
