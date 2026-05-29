// Purpose: Feature #42 Phase 1 WI-9a — the pure, nonisolated vreader-`Locator`
// → Readium-`Locator` mapping that drives search / TOC / bookmark JUMP
// navigation in the Readium EPUB host. The page-turn intents (`.readerNextPage`
// / `.readerPreviousPage`) need no mapping — they call the navigator's
// `goForward` / `goBackward` directly — so only the locator jump translation
// lives here. Counterpart of the legacy `EPUBReaderContainerView`'s
// `.readerNavigateToLocator` handler (which resolves the same vreader `Locator`
// against its OPF spine metadata instead of the Readium publication's
// reading-order hrefs).
//
// Key decisions:
// - Href resolution REUSES `ReadiumDecorationHighlightAdapter.resolveHref(_:against:)`
//   (exact → unique-suffix → unique-basename) — the SAME migration concern WI-8
//   solves for highlight decorations: a vreader `Locator` carries the LEGACY
//   engine's OPF-relative href (e.g. `chapter1.xhtml`), which must resolve to
//   Readium's container-relative reading-order href (e.g. `OEBPS/chapter1.xhtml`)
//   or the navigator can't route the jump. No duplicate resolution logic.
// - Fallback (mirrors the adapter's decoration path): when no safe spine match
//   is found — or no spine list is supplied — keep the RAW stored href so an
//   EPUB whose href already matches Readium's form still navigates, rather than
//   silently dropping the jump.
// - text-quote carry-through: a search result's `textQuote` + before/after
//   context map onto `Locator.Text(after:before:highlight:)` so Readium can
//   emphasise the matched phrase on arrival (the navigator anchors by the quote;
//   `progression` lands the scroll). nil quote → default empty `Text`.
// - nil/empty href → nil (unrenderable jump; the caller no-ops). nil progression
//   → nil `progression` in `Locations` (Readium lands at the resource start).
// - Pure + `nonisolated static` so the mapping unit-tests without a render.
//
// @coordinates-with ReadiumEPUBReaderViewModel.swift, ReadiumEPUBHost.swift,
//   ReadiumDecorationHighlightAdapter.swift, Locator.swift

#if canImport(UIKit)
import Foundation
import ReadiumShared

extension ReadiumEPUBReaderViewModel {

    /// Maps a vreader `Locator` (from a TOC / bookmark / search-result tap) to a
    /// Readium `Locator` the navigator can `go(to:)`. Resolves the locator's
    /// (legacy, OPF-relative) href against the publication's container-relative
    /// reading-order `spineHrefs` via the shared
    /// `ReadiumDecorationHighlightAdapter.resolveHref` (no safe match falls back
    /// to the raw href). Returns nil for a missing/empty href.
    nonisolated static func readiumLocator(
        fromVReader vreaderLocator: Locator,
        spineHrefs: [String]
    ) -> ReadiumShared.Locator? {
        guard let storedHref = vreaderLocator.href, !storedHref.isEmpty else {
            return nil
        }
        let resolved = ReadiumDecorationHighlightAdapter
            .resolveHref(storedHref, against: spineHrefs) ?? storedHref
        guard let relative = RelativeURL(path: resolved) else {
            return nil
        }
        let text = ReadiumShared.Locator.Text(
            after: vreaderLocator.textContextAfter,
            before: vreaderLocator.textContextBefore,
            highlight: vreaderLocator.textQuote
        )
        return ReadiumShared.Locator(
            href: relative,
            mediaType: .xhtml,
            locations: ReadiumShared.Locator.Locations(
                progression: vreaderLocator.progression
            ),
            text: text
        )
    }
}
#endif
