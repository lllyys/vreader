// Purpose: Feature #62 WI-1 — the routing type the reader uses to
// decide which annotations sheet (`TOCSheet` / `HighlightsSheet`) it
// presents.
//
// The unified `AnnotationsPanelView` is split into two sheets by
// job-to-be-done: `TOCSheet` (Contents + Bookmarks — "leave the
// current page") and `HighlightsSheet` (the All/Highlights/Notes/
// Bookmarks review surface — "revisit reading"). `ReaderContainerView`
// previously tracked sheet presentation with two `@State` vars
// (`showAnnotationsPanel` + `annotationsPanelInitialTab`); this one
// optional route replaces both — the two sheets are mutually exclusive,
// so a single `AnnotationsSheetRoute?` makes that a type invariant and
// carries the initial tab/filter inline.
//
// Foundation-only — no SwiftUI — so the routing decision is
// unit-testable without a render path, the same pattern
// `ReaderMoreMenuEffect` (feature #61) uses. `id` is the FULL payload
// so a `.sheet(item:)` re-presents cleanly even for "same kind,
// different initial tab".
//
// @coordinates-with: TOCSheet.swift, HighlightsSheet.swift,
//   ReaderContainerView.swift, ReaderContainerView+Sheets.swift,
//   ReaderChromeButton.swift, ReaderMoreMenuEffect.swift,
//   AnnotationsSheetRouteTests.swift

import Foundation

/// Which tab `TOCSheet`'s 2-tab segmented control presents.
enum TOCSheetTab: String, CaseIterable, Identifiable, Sendable {
    case contents = "Contents"
    case bookmarks = "Bookmarks"

    var id: String { rawValue }

    /// SF Symbol drawn in the segment / empty-state — pinned to the
    /// `TOCSheetV2` design.
    var systemImage: String {
        switch self {
        case .contents:  return "list.bullet"
        case .bookmarks: return "bookmark"
        }
    }
}

/// Which filter chip `HighlightsSheet`'s scrolling chip row presents.
/// Order + raw values are pinned to `ReaderSheetKind.annotations.sections`
/// (the #60 design contract).
enum HighlightsSheetFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case highlights = "Highlights"
    case notes = "Notes"
    case bookmarks = "Bookmarks"

    var id: String { rawValue }
}

/// The annotations sheet the reader presents, plus the initial tab /
/// filter it opens on. Drives `ReaderContainerView`'s `.sheet(item:)`.
enum AnnotationsSheetRoute: Equatable, Hashable, Identifiable, Sendable {
    /// The navigation sheet — Contents + Bookmarks.
    case toc(initialTab: TOCSheetTab)
    /// The review sheet — All / Highlights / Notes / Bookmarks.
    case highlights(initialFilter: HighlightsSheetFilter)

    /// Full-payload identity so `.sheet(item:)` re-presents cleanly
    /// even for "same kind, different initial tab" (Gate-2 round-1
    /// finding 1). A kind-only id ("toc") would suppress the
    /// re-presentation of the same sheet on a different initial tab.
    var id: String {
        switch self {
        case .toc(let tab):           return "toc:\(tab.rawValue)"
        case .highlights(let filter): return "highlights:\(filter.rawValue)"
        }
    }

    // MARK: - Routing

    /// Resolves the route for a tapped bottom-chrome button. The design's
    /// bottom-chrome routing table (`feature-60-followups.md` §3):
    /// Contents → `TOCSheet` (Contents tab); Notes → `HighlightsSheet`
    /// (**All** filter — the user reviews everything they collected, not
    /// just highlights).
    ///
    /// Only the two annotations-related buttons resolve to a route;
    /// `.display` / `.ai` open their own surfaces and return `nil`.
    static func route(forChromeButton button: ReaderBottomChromeButton) -> AnnotationsSheetRoute? {
        switch button {
        case .contents: return .toc(initialTab: .contents)
        case .notes:    return .highlights(initialFilter: .all)
        case .display, .ai: return nil
        }
    }

    /// Resolves the route for a reader More-menu host effect. The
    /// Export-annotations row reaches the export button in
    /// `HighlightsSheet`'s trailing slot; it opens the sheet on the
    /// Highlights filter.
    ///
    /// Only `.presentAnnotationsExport` resolves to a route; the other
    /// More-menu effects are handled elsewhere and return `nil`.
    static func route(forMoreMenuEffect effect: ReaderMoreMenuEffect) -> AnnotationsSheetRoute? {
        switch effect {
        case .presentAnnotationsExport:
            return .highlights(initialFilter: .highlights)
        case .toggleReadAloud, .toggleAutoPageTurn,
             .toggleBilingual, .presentTranslationSettings,
             .presentReTranslatePicker,
             .presentBookDetails, .presentShareSheet:
            // Feature #56 WI-8: bilingual and re-translate effects
            // are owned by the per-format containers (the bilingual
            // VM lives there); neither maps to the annotations sheet.
            return nil
        }
    }
}
