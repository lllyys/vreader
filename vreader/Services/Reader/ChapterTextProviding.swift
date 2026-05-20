// Purpose: Feature #56 bilingual reading — the format-agnostic chapter-text
// source boundary (plan Decision 2.6). There is no shared API in the codebase
// that supplies "the plain text of chapter N" across the five reader formats:
// `ReaderAICoordinator` extracts a windowed ~2500-char slice, the TXT/MD
// `ReflowableTextSource` adapters are whole-document, and the Foliate live
// extraction seam is whole-book. Both chapter bilingual mode (translate the
// current chapter) and global translate (translate every chapter) need
// per-unit text plus a `Locator -> unit` resolution.
//
// This boundary carries both contracts: the ordered-unit / per-unit-text
// contract and the `Locator -> unit` resolution the bilingual view model's
// prefetch trigger needs (Gate-2 round-2 N6).
//
// Key decisions:
// - The translation *unit* is the format's natural rendering segment — the
//   spine document (EPUB/Foliate), the `TXTChapterIndex` chapter (TXT), the
//   `MDHeading`-bounded chapter (MD), the PDF page range (PDF) — not the
//   logical TOC chapter (plan Decision 2.7). Global-translate progress counts
//   are then exact (one unit = one tick).
// - `Sendable` so `ChapterTranslationService` / `BookTranslationCoordinator`
//   can hold an `any ChapterTextProviding` across actor hops. The EPUB/TXT/MD/
//   PDF adapters are `struct`s holding only value state; the Foliate adapter
//   (WI-11) is an `actor` because it bridges the `@MainActor` Foliate
//   coordinator.
// - `unit(containing:)` returns `nil` only when the locator predates the
//   book's units (an empty book, or a locator before unit 0). A position past
//   the last unit clamps to the last unit — it is still *inside* a unit.
//
// @coordinates-with: TranslationUnitID.swift, EPUBChapterTextProvider.swift,
//   TXTChapterTextProvider.swift, MDChapterTextProvider.swift,
//   PDFChapterTextProvider.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-2.5, Decision 2.6)

import Foundation

/// Errors thrown by the chapter-text source boundary.
enum ChapterTextProviderError: Error, Sendable, Equatable {
    /// The requested unit is not part of the open book.
    case unknownUnit(TranslationUnitID)
    /// The unit's source text could not be read (I/O, decode failure).
    case sourceUnavailable(TranslationUnitID)
}

/// Supplies the plain source text of an open book's translation units in a
/// format-agnostic way, plus the `Locator -> unit` resolution the bilingual
/// prefetch trigger needs (plan Decision 2.6).
protocol ChapterTextProviding: Sendable {

    /// Ordered translation units for the open book, in reading order.
    /// An empty book returns `[]`.
    func translationUnits() async throws -> [TranslationUnitID]

    /// The plain source text of one unit, already HTML-stripped for
    /// EPUB/Foliate. Throws `ChapterTextProviderError.unknownUnit` for a unit
    /// the book does not contain.
    func sourceText(for unit: TranslationUnitID) async throws -> String

    /// The unit containing a given reading position. Returns `nil` only when
    /// the locator predates the book's first unit (e.g. an empty book). A
    /// position past the last unit clamps to the last unit.
    func unit(containing locator: Locator) async -> TranslationUnitID?

    /// The unit immediately after `unit` in reading order, or `nil` at the end
    /// of the book — used by the prefetch trigger to fetch current + next.
    func unit(after unit: TranslationUnitID) async -> TranslationUnitID?
}
