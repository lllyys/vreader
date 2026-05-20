// Purpose: Feature #56 WI-13 — pure state derivation for the PDF
// below-page bilingual panel. Synchronous projection of
// `BilingualReadingViewModel` state onto the panel's 5-state matrix
// (`.off` / `.loading` / `.translated` / `.offline` / `.empty`).
//
// Key decisions:
// - **Derives the current `TranslationUnitID` from `(currentPage,
//   pagesPerUnit, totalPages)` synchronously** — does NOT consult
//   `vm.lastTriggerUnit` (Gate-2 v5 round-1 H1). `lastTriggerUnit`
//   updates only after the async `handlePositionChange` settles, so
//   during a page-turn-in-flight window it would briefly point at
//   the prior page's unit and the panel would flash stale
//   translations.
// - **`.empty` is "no extractable text"**, not "no unit". Keyed on
//   `totalPages <= 0` OR a non-nil-but-EMPTY `translationsByUnit[unit]`
//   (the service returned `[]` for an image-only / scan page —
//   Gate-2 v5 round-1 M1). `PDFChapterTextProvider.unit(containing:)`
//   clamps past-last pages to the last unit, so `unit == nil` is not
//   a useful empty-state signal.
// - **`.off` precedes `.empty`** so a disabled VM on a zero-page
//   document doesn't flash "no text on page" before bilingual is on.
//
// @coordinates-with: PDFBilingualPanel.swift,
//   BilingualReadingViewModel.swift, PDFChapterTextProvider.swift,
//   TranslationUnitID.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-13)

import Foundation

/// The visible state of the PDF below-page bilingual panel — pinned
/// to design canvas §A1..A5 (default / loading / offline / empty /
/// collapsed). `collapsed` is presentational (handled by the host's
/// `@State` and the panel's own collapsed branch), not a content
/// state — it's deliberately absent here.
enum PDFBilingualPanelState: Equatable, Sendable {
    case off
    case loading
    case translated(segments: [String])
    case offline
    case empty
}

extension PDFBilingualPanelState {

    /// Synchronous derivation of the panel's state from the VM + the
    /// PDF host's `(currentPage, pagesPerUnit, totalPages)` triple.
    ///
    /// `viewModel == nil` || `!isEnabled` → `.off`.
    /// `totalPages <= 0`                  → `.empty`.
    /// `vm.translationsByUnit[unit]`
    ///   - non-nil, non-empty             → `.translated(segments)`
    ///   - non-nil, empty                 → `.empty`
    /// `vm.unavailableUnits.contains(unit)`
    ///                                    → `.offline`
    /// `vm.inFlightUnits.contains(unit)`
    ///   || `vm.isFetching`               → `.loading`
    /// else                               → `.loading` (initial paint;
    ///                                       prefetch about to fire).
    @MainActor
    static func panelState(
        viewModel: BilingualReadingViewModel?,
        currentPage: Int,
        pagesPerUnit: Int,
        totalPages: Int
    ) -> PDFBilingualPanelState {
        guard let vm = viewModel, vm.isEnabled else { return .off }
        guard totalPages > 0 else { return .empty }

        let unit = unitID(
            currentPage: currentPage, pagesPerUnit: pagesPerUnit, totalPages: totalPages)

        if let cached = vm.translationsByUnit[unit] {
            return cached.isEmpty ? .empty : .translated(segments: cached)
        }
        if vm.unavailableUnits.contains(unit) { return .offline }
        if vm.inFlightUnits.contains(unit) || vm.isFetching { return .loading }
        return .loading
    }

    /// Synchronous mirror of `PDFChapterTextProvider.pageRanges`'s
    /// page→unit map. Returns the unit the panel's derivation keys on.
    /// Kept here so the unit identity is co-located with the
    /// derivation; the prefetch trigger in the VM uses the provider's
    /// async API which produces the same value.
    static func unitID(
        currentPage: Int, pagesPerUnit: Int, totalPages: Int
    ) -> TranslationUnitID {
        let perUnit = max(1, pagesPerUnit)
        let start = (currentPage / perUnit) * perUnit
        let lastIndex = max(0, totalPages - 1)
        let end = min(start + perUnit - 1, lastIndex)
        return TranslationUnitID(kind: .pdfPageRange, value: "\(start)-\(end)")
    }

    /// "Page N" / "Pages M-N" / "—" — the one-indexed page label the
    /// panel header renders.
    static func pageLabel(
        currentPage: Int, pagesPerUnit: Int, totalPages: Int
    ) -> String {
        guard totalPages > 0 else { return "—" }
        let perUnit = max(1, pagesPerUnit)
        let zeroStart = (currentPage / perUnit) * perUnit
        let lastIndex = totalPages - 1
        let zeroEnd = min(zeroStart + perUnit - 1, lastIndex)
        if zeroStart == zeroEnd {
            return "Page \(zeroStart + 1)"
        }
        return "Pages \(zeroStart + 1)-\(zeroEnd + 1)"
    }
}
