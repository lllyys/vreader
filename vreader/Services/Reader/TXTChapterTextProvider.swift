// Purpose: Feature #56 WI-2.5 — the TXT `ChapterTextProviding` adapter. The
// translation unit is the `TXTChapterIndex` chapter (plan Decision 2.7). The
// chapter index exists independent of render mode, so continuous-mode TXT
// still has units — bilingual mode keys on the chapter index regardless of how
// the renderer lays the text out.
//
// Key decisions:
// - A `Sendable` `struct` holding only value state: the full decoded book
//   text and the chapter list (with UTF-16 offsets already populated by
//   `TXTOffsetTranslator.populateUTF16Offsets`). No I/O at call time —
//   slicing is pure string work.
// - `sourceText` slices the full text by the chapter's `globalStartUTF16` /
//   `textLengthUTF16` UTF-16 bounds, the same way `TXTChapterContentLoader`
//   does, so this adapter and the live reader always agree on chapter text.
// - `unit(containing:)` maps a `charOffsetUTF16` locator to its chapter; a
//   position past the last chapter clamps to the last chapter (it is still
//   inside a unit). A locator with no `charOffsetUTF16` resolves to unit 0.
//
// @coordinates-with: ChapterTextProviding.swift, TXTChapterIndex.swift,
//   TXTOffsetTranslator.swift, TXTChapterContentLoader.swift

import Foundation

/// Supplies per-chapter source text for an open TXT book.
struct TXTChapterTextProvider: ChapterTextProviding {

    /// Fingerprint of the open book (carried for parity with the other
    /// adapters; not needed for slicing).
    private let fingerprint: DocumentFingerprint

    /// The full decoded book text — sliced per chapter on demand.
    private let fullText: String

    /// Chapters in document order, with UTF-16 offsets populated.
    private let chapters: [TXTChapter]

    init(fingerprint: DocumentFingerprint, fullText: String, chapters: [TXTChapter]) {
        self.fingerprint = fingerprint
        self.fullText = fullText
        self.chapters = chapters
    }

    func translationUnits() async throws -> [TranslationUnitID] {
        chapters.map { TranslationUnitID(kind: .txtChapterIndex, value: String($0.index)) }
    }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        guard unit.kind == .txtChapterIndex, let index = Int(unit.value),
              let chapter = chapters.first(where: { $0.index == index }) else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        let ns = fullText as NSString
        let start = chapter.globalStartUTF16
        let length = chapter.textLengthUTF16
        guard start >= 0, length >= 0, start <= ns.length else {
            throw ChapterTextProviderError.sourceUnavailable(unit)
        }
        let safeLength = min(length, ns.length - start)
        return safeLength > 0
            ? ns.substring(with: NSRange(location: start, length: safeLength))
            : ""
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? {
        guard !chapters.isEmpty else { return nil }
        // A locator with no offset (e.g. start of book) resolves to unit 0; a
        // negative offset predates the book's first unit and resolves to nil.
        guard let offset = locator.charOffsetUTF16 else {
            return TranslationUnitID(kind: .txtChapterIndex, value: String(chapters[0].index))
        }
        guard offset >= 0 else { return nil }
        // Find the last chapter whose start is at or before the offset —
        // clamps a past-the-end offset to the final chapter.
        var match = chapters[0]
        for chapter in chapters where chapter.globalStartUTF16 <= offset {
            match = chapter
        }
        return TranslationUnitID(kind: .txtChapterIndex, value: String(match.index))
    }

    func unit(after unit: TranslationUnitID) async -> TranslationUnitID? {
        guard unit.kind == .txtChapterIndex, let index = Int(unit.value),
              let position = chapters.firstIndex(where: { $0.index == index }),
              position + 1 < chapters.count else {
            return nil
        }
        return TranslationUnitID(
            kind: .txtChapterIndex, value: String(chapters[position + 1].index)
        )
    }
}
