// Purpose: Feature #56 WI-2.5 — the Markdown `ChapterTextProviding` adapter.
// The translation unit is the `MDHeading`-bounded chapter (plan Decision 2.7):
// the rendered Markdown text is split into spans, each running from one ATX
// heading to the next. A non-empty preamble before the first heading forms
// unit 0; a document with no headings is a single unit.
//
// Key decisions:
// - A `Sendable` `struct` holding only value state: the rendered plain text
//   (`MDDocumentInfo.renderedText`) and the heading list
//   (`MDDocumentInfo.headings`). Chapter boundaries are pure UTF-16 offset
//   arithmetic — no I/O at call time.
// - `MDHeading.charOffsetUTF16` is the offset *into the rendered text* (the
//   heading text is plain in the render). Chapter N spans
//   `[boundary[N], boundary[N+1])`.
// - A leading span before the first heading becomes unit 0 only when it is
//   non-empty; when the document opens with a heading, unit 0 is that
//   heading's chapter.
// - `unit(containing:)` maps a `charOffsetUTF16` locator to its chapter,
//   clamping a past-the-end offset to the last chapter.
//
// @coordinates-with: ChapterTextProviding.swift, MDTypes.swift,
//   MDChapterStartScanner.swift

import Foundation

/// Supplies per-chapter source text for an open Markdown book.
struct MDChapterTextProvider: ChapterTextProviding {

    /// Fingerprint of the open book (carried for parity with the other
    /// adapters; not needed for slicing).
    private let fingerprint: DocumentFingerprint

    /// The rendered plain text — sliced per chapter on demand.
    private let renderedText: String

    /// Inclusive-start UTF-16 boundary offsets for each chapter, in order.
    /// Always begins at 0 when the text is non-empty.
    private let boundaries: [Int]

    init(fingerprint: DocumentFingerprint, renderedText: String, headings: [MDHeading]) {
        self.fingerprint = fingerprint
        self.renderedText = renderedText
        self.boundaries = Self.chapterBoundaries(
            textLength: (renderedText as NSString).length, headings: headings
        )
    }

    func translationUnits() async throws -> [TranslationUnitID] {
        boundaries.indices.map {
            TranslationUnitID(kind: .mdChapterIndex, value: String($0))
        }
    }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        guard unit.kind == .mdChapterIndex, let index = Int(unit.value),
              index >= 0, index < boundaries.count else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        let ns = renderedText as NSString
        let start = boundaries[index]
        let end = index + 1 < boundaries.count ? boundaries[index + 1] : ns.length
        let length = max(0, min(end, ns.length) - start)
        return length > 0
            ? ns.substring(with: NSRange(location: start, length: length))
            : ""
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? {
        guard !boundaries.isEmpty else { return nil }
        // A locator with no offset (e.g. start of book) resolves to unit 0; a
        // negative offset predates the book's first unit and resolves to nil.
        guard let offset = locator.charOffsetUTF16 else {
            return TranslationUnitID(kind: .mdChapterIndex, value: "0")
        }
        guard offset >= 0 else { return nil }
        // Last chapter whose boundary is at or before the offset — clamps a
        // past-the-end offset to the final chapter.
        var matchIndex = 0
        for (index, boundary) in boundaries.enumerated() where boundary <= offset {
            matchIndex = index
        }
        return TranslationUnitID(kind: .mdChapterIndex, value: String(matchIndex))
    }

    func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
        guard unit.kind == .mdChapterIndex, let index = Int(unit.value),
              index >= 0, index + 1 < boundaries.count else {
            return nil
        }
        return TranslationUnitID(kind: .mdChapterIndex, value: String(index + 1))
    }

    // MARK: - Boundary derivation

    /// Computes the ordered inclusive-start chapter boundaries. An empty
    /// document yields `[]`; a document with no headings yields `[0]`; a
    /// non-empty preamble before the first heading yields a leading `0`.
    private static func chapterBoundaries(textLength: Int, headings: [MDHeading]) -> [Int] {
        guard textLength > 0 else { return [] }
        // Sorted, de-duplicated heading offsets within text bounds.
        let headingOffsets = headings
            .map(\.charOffsetUTF16)
            .filter { $0 >= 0 && $0 < textLength }
            .sorted()
        var result: [Int] = []
        // A preamble exists when the first heading is past offset 0 (or there
        // are no headings at all).
        if headingOffsets.first != 0 {
            result.append(0)
        }
        for offset in headingOffsets where !result.contains(offset) {
            result.append(offset)
        }
        return result
    }
}
