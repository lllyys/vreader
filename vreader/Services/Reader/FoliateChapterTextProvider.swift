// Purpose: Feature #56 WI-11 — the AZW3/MOBI `ChapterTextProviding`
// adapter. The translation unit is the Foliate section (plan
// Decision 2.7), matching what the bilingual interlinear renderer
// injects into.
//
// Key decisions:
// - **`actor`, not `struct`.** The other four adapters
//   (EPUB/TXT/MD/PDF) are `struct`s holding value state, but the
//   live Foliate extraction seam (`FoliateSpikeView.Coordinator` +
//   `WKWebView`) is `@MainActor`. The provider therefore stores a
//   class-bound `any FoliateSectionExtracting` and reaches it via
//   `await`. An `actor` is `Sendable` by construction, so it
//   satisfies `ChapterTextProviding: Sendable` without
//   `nonisolated(unsafe)`.
// - **Cached unit list.** `translationUnits()` is called every
//   time the bilingual VM resolves a locator to a unit, so the
//   first call latches the extractor's ordered section list. A
//   book reopen / format-host swap rebuilds the provider from
//   scratch, so the cache never goes stale within one open book.
// - **`unit(containing:)` keys on `Locator.href`.** Foliate
//   exposes section identity via `sectionIndex` (relocate event)
//   and `href`. The plan and `TranslationUnitID.Kind.foliateHref`
//   say the value is the section's href / index string. The VM
//   threads `Locator.href` through `makeCurrentLocator()` for the
//   AZW3/MOBI host.
//
// @coordinates-with: FoliateSectionExtracting.swift,
//   ChapterTextProviding.swift, TranslationUnitID.swift,
//   FoliateSpikeView.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Foundation

/// Live AZW3/MOBI `ChapterTextProviding` adapter. Bridges the
/// `@MainActor`-isolated Foliate extractor facade into the
/// `Sendable` chapter-text-provider boundary via an `actor`.
actor FoliateChapterTextProvider: ChapterTextProviding {

    /// The live Foliate extractor (the `FoliateSpikeView.Coordinator`
    /// in production; an in-memory mock in tests).
    private let extractor: any FoliateSectionExtracting

    /// Cached ordered section list — populated on the first
    /// `translationUnits()` call. Re-fetched on `nil`. A book
    /// reopen builds a fresh provider, so this never goes stale.
    private var cachedUnits: [TranslationUnitID]?

    init(extractor: any FoliateSectionExtracting) {
        self.extractor = extractor
    }

    func translationUnits() async throws -> [TranslationUnitID] {
        if let cached = cachedUnits, !cached.isEmpty { return cached }
        let units = await extractor.extractSections()
        // Gate-4 audit finding M1: never cache `[]`. The live
        // extractor returns `[]` before the book has rendered
        // (`Coordinator.isBookReady == false`); caching an empty
        // result would permanently poison the provider for the rest
        // of the reader session. Only cache a populated list — a
        // pre-ready call is retried on the next lookup.
        if !units.isEmpty {
            cachedUnits = units
        }
        return units
    }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        guard unit.kind == .foliateHref else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        // Ensure the section list is loaded so we can validate the
        // unit before asking the extractor for its text.
        let units = try await translationUnits()
        guard units.contains(unit) else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        return await extractor.extractSectionText(unit)
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? {
        guard let href = locator.href else { return nil }
        let units = (try? await translationUnits()) ?? []
        let candidate = TranslationUnitID(kind: .foliateHref, value: href)
        return units.contains(candidate) ? candidate : nil
    }

    func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
        guard unit.kind == .foliateHref else { return nil }
        let units = (try? await translationUnits()) ?? []
        guard let index = units.firstIndex(of: unit),
              index + 1 < units.count else {
            return nil
        }
        return units[index + 1]
    }
}
