// Purpose: Feature #56 WI-12b — pin the chapter-paged TXT chapter text
// provider that reads each chapter on demand via `TXTChapterContentLoader`
// (rather than slicing a single full-book string). Lets bilingual mode
// activate in chapter-paged TXT, the mode WI-12a's `makeTextProvider`
// explicitly disabled (Codex Gate-4 round-1 H2 → round-2 follow-up).
//
// @coordinates-with: TXTLoaderBackedChapterTextProvider.swift,
//   TXTChapterContentLoader.swift, TXTChapterTextProvider.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #56 WI-12b — TXTLoaderBackedChapterTextProvider")
struct TXTLoaderBackedChapterTextProviderTests {

    @Test("translationUnits returns one unit per chapter in order")
    func translationUnitsOrdered() async throws {
        let provider = try makeProvider(chapterTexts: ["First.", "Second.", "Third."])
        let units = try await provider.translationUnits()
        #expect(units.count == 3)
        #expect(units[0] == TranslationUnitID(kind: .txtChapterIndex, value: "0"))
        #expect(units[1] == TranslationUnitID(kind: .txtChapterIndex, value: "1"))
        #expect(units[2] == TranslationUnitID(kind: .txtChapterIndex, value: "2"))
    }

    @Test("sourceText resolves chapter text via loader")
    func sourceTextResolvesViaLoader() async throws {
        let provider = try makeProvider(chapterTexts: ["First chapter.", "Second chapter."])
        let unit0 = TranslationUnitID(kind: .txtChapterIndex, value: "0")
        let unit1 = TranslationUnitID(kind: .txtChapterIndex, value: "1")
        let text0 = try await provider.sourceText(for: unit0)
        let text1 = try await provider.sourceText(for: unit1)
        #expect(text0 == "First chapter.")
        #expect(text1 == "Second chapter.")
    }

    @Test("sourceText throws unknownUnit for non-txt kind")
    func unknownKindThrows() async throws {
        let provider = try makeProvider(chapterTexts: ["First."])
        let unit = TranslationUnitID(kind: .epubHref, value: "0")
        await #expect(throws: ChapterTextProviderError.self) {
            _ = try await provider.sourceText(for: unit)
        }
    }

    @Test("sourceText throws unknownUnit for out-of-range index")
    func outOfRangeThrows() async throws {
        let provider = try makeProvider(chapterTexts: ["First."])
        let unit = TranslationUnitID(kind: .txtChapterIndex, value: "99")
        await #expect(throws: ChapterTextProviderError.self) {
            _ = try await provider.sourceText(for: unit)
        }
    }

    @Test("unit(containing:) maps a chapter-global offset to the right chapter")
    func unitContaining() async throws {
        // "First." (6) | "\n\n" (2) | "Second." (7) | "\n\n" (2) | "Third." (6).
        // Chapter starts at: 0, 8, 17.
        let provider = try makeProvider(chapterTexts: ["First.", "Second.", "Third."])
        let fp = makeFingerprint()
        let p1 = Locator.validated(bookFingerprint: fp, charOffsetUTF16: 0)!
        let p2 = Locator.validated(bookFingerprint: fp, charOffsetUTF16: 10)!  // mid-Ch1
        let p3 = Locator.validated(bookFingerprint: fp, charOffsetUTF16: 19)!  // mid-Ch2
        let u1 = await provider.unit(containing: p1)
        let u2 = await provider.unit(containing: p2)
        let u3 = await provider.unit(containing: p3)
        #expect(u1 == TranslationUnitID(kind: .txtChapterIndex, value: "0"))
        #expect(u2 == TranslationUnitID(kind: .txtChapterIndex, value: "1"))
        #expect(u3 == TranslationUnitID(kind: .txtChapterIndex, value: "2"))
    }

    @Test("unit(after:) returns next chapter or nil at the last")
    func unitAfter() async throws {
        let provider = try makeProvider(chapterTexts: ["A.", "B.", "C."])
        let u0 = TranslationUnitID(kind: .txtChapterIndex, value: "0")
        let u2 = TranslationUnitID(kind: .txtChapterIndex, value: "2")
        let next0 = await provider.unit(after: u0)
        let next2 = await provider.unit(after: u2)
        #expect(next0 == TranslationUnitID(kind: .txtChapterIndex, value: "1"))
        #expect(next2 == nil)
    }

    // MARK: - helpers

    private func makeProvider(chapterTexts: [String]) throws -> TXTLoaderBackedChapterTextProvider {
        // Concatenate with "\n\n" between chapters; build TXTChapter rows
        // with globalStartUTF16 + textLengthUTF16 populated.
        var combined = ""
        var chapters: [TXTChapter] = []
        for (idx, body) in chapterTexts.enumerated() {
            let startUTF16 = combined.utf16.count
            let chapter = TXTChapter(
                index: idx,
                title: "Chapter \(idx)",
                startByte: 0,
                endByte: 0,
                globalStartUTF16: startUTF16,
                textLengthUTF16: body.utf16.count
            )
            chapters.append(chapter)
            combined += body
            if idx + 1 < chapterTexts.count { combined += "\n\n" }
        }

        // Use UTF-8 — the loader decodes via the supplied encoding.
        let fileData = combined.data(using: .utf8)!
        let loader = TXTChapterContentLoader(fileData: fileData, encoding: .utf8)
        return TXTLoaderBackedChapterTextProvider(
            fingerprint: makeFingerprint(),
            chapters: chapters,
            loader: loader
        )
    }

    private func makeFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1024,
            format: .txt
        )
    }
}
