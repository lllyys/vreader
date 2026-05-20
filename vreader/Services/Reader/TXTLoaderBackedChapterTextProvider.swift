// Purpose: Feature #56 WI-12b — the chapter-paged-mode TXT chapter text
// provider. Reads each chapter on demand via `TXTChapterContentLoader`
// (the same loader the live reader uses for chapter swap-in), so the
// adapter is independent of whether the TXT VM holds the full book or
// chapter-local text. Re-enables bilingual mode for chapter-paged TXT,
// the mode WI-12a's `makeTextProvider` explicitly disabled (Codex
// Gate-4 round-1 H2 → round-2 follow-up).
//
// Key decisions:
// - **`async` adapter** — `TXTChapterContentLoader` is an actor; the
//   adapter awaits its `loadChapter` call inside `sourceText(for:)`.
//   The prefetch path already runs every `sourceText(...)` on the
//   actor's queue (the prefetch coordinator awaits the boundary).
// - **`unit(containing:)` derives chapter from the *document-global*
//   `charOffsetUTF16`** — the same convention `TXTChapterTextProvider`
//   uses. The VM passes a position `Locator` whose `charOffsetUTF16`
//   is the source-text-domain offset (NOT the display-domain offset),
//   regardless of bilingual on/off — bilingual state never leaks into
//   the position-update notification.
// - **Chapter list is pre-populated** — by the time the host calls
//   this adapter, `TXTChapterIndex` has populated `globalStartUTF16` /
//   `textLengthUTF16` for every chapter (via the offset-translator
//   pass after open). The adapter does NOT defend against unpopulated
//   offsets — its caller (`ensureBilingualViewModel`) already guards
//   on `chapterIndex?.count > 0`.
//
// @coordinates-with: TXTChapterTextProvider.swift,
//   TXTChapterContentLoader.swift, ChapterTextProviding.swift,
//   TXTReaderContainerView+Bilingual.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Foundation

/// `ChapterTextProviding` adapter that reads chapter text on demand
/// via `TXTChapterContentLoader` — the chapter-paged-mode counterpart
/// to `TXTChapterTextProvider`'s full-book-slicing approach.
struct TXTLoaderBackedChapterTextProvider: ChapterTextProviding {

    /// Fingerprint of the open book (carried for parity with the other
    /// adapters; not needed for slicing).
    private let fingerprint: DocumentFingerprint

    /// Chapters in document order, with UTF-16 offsets populated.
    private let chapters: [TXTChapter]

    /// Actor that decodes + caches chapter text.
    private let loader: TXTChapterContentLoader

    init(fingerprint: DocumentFingerprint, chapters: [TXTChapter], loader: TXTChapterContentLoader) {
        self.fingerprint = fingerprint
        self.chapters = chapters
        self.loader = loader
    }

    func translationUnits() async throws -> [TranslationUnitID] {
        chapters.map { TranslationUnitID(kind: .txtChapterIndex, value: String($0.index)) }
    }

    func sourceText(for unit: TranslationUnitID) async throws -> String {
        guard unit.kind == .txtChapterIndex, let index = Int(unit.value),
              let chapter = chapters.first(where: { $0.index == index }) else {
            throw ChapterTextProviderError.unknownUnit(unit)
        }
        do {
            return try await loader.loadChapter(chapter)
        } catch {
            throw ChapterTextProviderError.sourceUnavailable(unit)
        }
    }

    func unit(containing locator: Locator) async -> TranslationUnitID? {
        guard !chapters.isEmpty else { return nil }
        guard let offset = locator.charOffsetUTF16 else {
            return TranslationUnitID(kind: .txtChapterIndex, value: String(chapters[0].index))
        }
        guard offset >= 0 else { return nil }
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
