// Purpose: Feature #56 WI-2.5 — the EPUB `ChapterTextProviding` adapter. The
// translation unit is the spine document (plan Decision 2.7): one logical TOC
// chapter can span multiple spine documents and multiple TOC entries can share
// one href, so keying on the spine doc makes global-translate progress counts
// exact and matches what the EPUB renderer injects into.
//
// Key decisions:
// - A `Sendable` `struct` holding only value state — the ordered spine list
//   and an `any EPUBParserProtocol` (itself `Sendable`, actor-isolated in
//   production). No `@MainActor` hop is needed; spine HTML is read off-main.
// - `sourceText` strips HTML via `EPUBTextExtractor.stripHTML` — the same
//   regex-based, non-UIKit stripper EPUB search indexing uses. It runs
//   off-main (unlike `EPUBTextStripper`, which is `@MainActor` for the UIKit
//   HTML importer), so the adapter stays a plain `struct`.
// - `unit(containing:)` matches the locator's spine `href`; an unknown href
//   yields `nil` (the locator predates / is outside the book's units).
//
// @coordinates-with: ChapterTextProviding.swift, EPUBParserProtocol.swift,
//   EPUBTextExtractor.swift, EPUBTypes.swift

import Foundation

/// Supplies per-spine-document source text for an open EPUB.
struct EPUBChapterTextProvider: ChapterTextProviding {

    /// The open EPUB parser. Actor-isolated in production (`EPUBParser`).
    private let parser: any EPUBParserProtocol

    /// Spine documents in reading order — the translation units.
    private let spineItems: [EPUBSpineItem]

    init(parser: any EPUBParserProtocol, spineItems: [EPUBSpineItem]) {
        self.parser = parser
        self.spineItems = spineItems
    }

    func translationUnits() async throws -> [TranslationUnitID] {
        spineItems.map { TranslationUnitID(kind: .epubHref, value: $0.href) }
    }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        guard unit.kind == .epubHref,
              spineItems.contains(where: { $0.href == unit.value }) else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        do {
            let html = try await parser.contentForSpineItem(href: unit.value)
            return EPUBTextExtractor.stripHTML(html)
        } catch {
            throw ChapterTextProviderError.sourceUnavailable(unit)
        }
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? {
        guard let href = locator.href,
              spineItems.contains(where: { $0.href == href }) else {
            return nil
        }
        return TranslationUnitID(kind: .epubHref, value: href)
    }

    func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
        guard let index = spineItems.firstIndex(where: { $0.href == unit.value }),
              index + 1 < spineItems.count else {
            return nil
        }
        return TranslationUnitID(kind: .epubHref, value: spineItems[index + 1].href)
    }
}
