// Purpose: Format-agnostic translation-unit identity for feature #56 bilingual
// reading. A single `chapterHref` string cannot key the translation cache
// across all five reader formats — TXT's chapter href is synthetic and
// chapter-mode-gated, MD has no href, PDF is page-based (Gate-2 round-1 C1).
// This value type tags each unit with its origin so the disk cache, the
// bilingual view model, and the translation coordinators share one identity.
//
// Key decisions:
// - `Kind.rawValue` is persisted (folded into `storageKey` ->
//   ChapterTranslation.unitStorageKey). A rename is a data-format break.
// - The translation *unit* is the format's natural rendering segment — the
//   spine document (EPUB/Foliate), the TXTChapterIndex chapter (TXT), the
//   MDChapterStartScanner chapter (MD) — not the logical TOC chapter
//   (Decision 2.7), so global-translate progress counts are exact.
//
// @coordinates-with: ChapterTranslation.swift, ChapterTranslationRecord.swift,
//   ChapterTextProviding.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-1, Decision 2.5)

import Foundation

/// Identifies one translatable unit of an open book in a format-agnostic way.
struct TranslationUnitID: Sendable, Equatable, Hashable, Codable {

    /// The origin format that produced this unit identity.
    enum Kind: String, Sendable, Codable, CaseIterable {
        /// EPUB spine-document href.
        case epubHref
        /// AZW3/MOBI Foliate section href / index.
        case foliateHref
        /// TXT chapter index (stringified `TXTChapterIndex` ordinal).
        case txtChapterIndex
        /// MD chapter index (stringified `MDChapterStartScanner` ordinal).
        case mdChapterIndex
        /// PDF page range translated as one unit (`"start-end"`).
        case pdfPageRange
    }

    /// The format that produced this identity.
    let kind: Kind

    /// The kind-specific value: a spine href, a chapter index, or a page range.
    let value: String

    /// Stable persisted key — `"<kind>:<value>"`. Goes into
    /// `ChapterTranslation.unitStorageKey` (Decision 2.5).
    var storageKey: String { "\(kind.rawValue):\(value)" }
}
