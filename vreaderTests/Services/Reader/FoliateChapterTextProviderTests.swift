// Purpose: Feature #56 WI-11 — pin the AZW3/MOBI
// `ChapterTextProviding` actor adapter. The Foliate adapter is the
// odd one out — the other four (EPUB / TXT / MD / PDF) are
// `struct`s holding only value state, but the Foliate live
// extraction seam (`FoliateSpikeView.Coordinator` / WKWebView) is
// `@MainActor`. The provider is therefore an `actor` that bridges
// the main-actor facade via `await`.
//
// Tests exercise the protocol contract over a deterministic mock
// `FoliateSectionExtracting` facade — runtime WKWebView interaction
// (the `view.book.sections[].createDocument()` walk) is verified at
// slice-verification time on an AZW3 fixture book.
//
// @coordinates-with: FoliateChapterTextProvider.swift,
//   FoliateSectionExtracting.swift, ChapterTextProviding.swift,
//   TranslationUnitID.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Foundation
import Testing
@testable import vreader

@Suite("Feature #56 WI-11 — FoliateChapterTextProvider")
@MainActor
struct FoliateChapterTextProviderTests {

    /// Deterministic in-memory mock of the `FoliateSectionExtracting`
    /// facade. Holds an ordered `(id, text)` array — extraction is
    /// pure lookup.
    @MainActor
    final class MockExtractor: FoliateSectionExtracting {
        var sections: [(id: TranslationUnitID, text: String)]

        init(sections: [(id: TranslationUnitID, text: String)]) {
            self.sections = sections
        }

        func extractSections() async -> [TranslationUnitID] {
            sections.map(\.id)
        }

        func extractSectionText(_ unit: TranslationUnitID) async -> String {
            sections.first(where: { $0.id == unit })?.text ?? ""
        }
    }

    // MARK: - translationUnits

    @Test("translationUnits returns the ordered section list from the extractor")
    func translationUnitsOrderedFromExtractor() async throws {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha"),
            (TranslationUnitID(kind: .foliateHref, value: "1"), "beta"),
            (TranslationUnitID(kind: .foliateHref, value: "2"), "gamma")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let units = try await provider.translationUnits()
        #expect(units.map(\.value) == ["0", "1", "2"])
        #expect(units.allSatisfy { $0.kind == .foliateHref })
    }

    @Test("translationUnits returns [] for an empty book")
    func translationUnitsEmptyBook() async throws {
        let extractor = MockExtractor(sections: [])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let units = try await provider.translationUnits()
        #expect(units.isEmpty)
    }

    // MARK: - sourceText

    @Test("sourceText returns the extractor's text for a known unit")
    func sourceTextKnownUnit() async throws {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha-content"),
            (TranslationUnitID(kind: .foliateHref, value: "1"), "beta-content")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let text = try await provider.sourceText(
            for: TranslationUnitID(kind: .foliateHref, value: "1")
        )
        #expect(text == "beta-content")
    }

    @Test("sourceText throws unknownUnit for a unit not in the section list")
    func sourceTextUnknownUnit() async {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha-content")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let missing = TranslationUnitID(kind: .foliateHref, value: "99")
        await #expect(throws: ChapterTextProviderError.self) {
            _ = try await provider.sourceText(for: missing)
        }
    }

    @Test("sourceText rejects units of a different Kind")
    func sourceTextWrongKind() async {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let mismatch = TranslationUnitID(kind: .epubHref, value: "0")
        await #expect(throws: ChapterTextProviderError.self) {
            _ = try await provider.sourceText(for: mismatch)
        }
    }

    // MARK: - unit(containing:) / unit(after:)

    @Test("unit(containing:) maps a locator with matching href to the unit")
    func unitContainingByHref() async throws {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha"),
            (TranslationUnitID(kind: .foliateHref, value: "1"), "beta"),
            (TranslationUnitID(kind: .foliateHref, value: "2"), "gamma")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let fingerprint = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1,
            format: .azw3
        )
        let locator = Locator(
            bookFingerprint: fingerprint,
            href: "1",
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
        let unit = await provider.unit(containing: locator)
        #expect(unit == TranslationUnitID(kind: .foliateHref, value: "1"))
    }

    @Test("unit(containing:) returns nil for a locator without a known href")
    func unitContainingUnknown() async throws {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let fingerprint = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1,
            format: .azw3
        )
        let locator = Locator(
            bookFingerprint: fingerprint,
            href: "ghost",
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
        let unit = await provider.unit(containing: locator)
        #expect(unit == nil)
    }

    @Test("unit(after:) returns the next section in order")
    func unitAfterReturnsNext() async throws {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha"),
            (TranslationUnitID(kind: .foliateHref, value: "1"), "beta"),
            (TranslationUnitID(kind: .foliateHref, value: "2"), "gamma")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let next = await provider.unit(
            after: TranslationUnitID(kind: .foliateHref, value: "1")
        )
        #expect(next == TranslationUnitID(kind: .foliateHref, value: "2"))
    }

    @Test("unit(after:) returns nil at the last section")
    func unitAfterReturnsNilAtEnd() async throws {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha"),
            (TranslationUnitID(kind: .foliateHref, value: "1"), "beta")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let next = await provider.unit(
            after: TranslationUnitID(kind: .foliateHref, value: "1")
        )
        #expect(next == nil)
    }

    @Test("unit(after:) returns nil for an unknown unit")
    func unitAfterUnknownReturnsNil() async throws {
        let extractor = MockExtractor(sections: [
            (TranslationUnitID(kind: .foliateHref, value: "0"), "alpha")
        ])
        let provider = FoliateChapterTextProvider(extractor: extractor)
        let next = await provider.unit(
            after: TranslationUnitID(kind: .foliateHref, value: "99")
        )
        #expect(next == nil)
    }
}
