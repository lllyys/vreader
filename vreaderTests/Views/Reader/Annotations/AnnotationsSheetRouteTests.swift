// Purpose: Feature #62 WI-1 — pins the annotations-sheet routing type.
//
// `AnnotationsSheetRoute` is the pure decision type the reader's
// bottom-chrome + More-menu resolve to: it names which annotations
// sheet (`TOCSheet` / `HighlightsSheet`) the reader presents, decoupled
// from the `@State` mutation so the routing decision is unit-testable
// without a SwiftUI render path — the same pattern `ReaderMoreMenuEffect`
// (feature #61) uses.
//
// The contract these tests guard: the `id` is the FULL payload so a
// `.sheet(item:)` re-presents cleanly even for "same kind, different
// initial tab" (Gate-2 round-1 finding 1); the `route(forChromeButton:)`
// / `route(forMoreMenuEffect:)` mappings match the committed design's
// bottom-chrome routing table.
//
// @coordinates-with: AnnotationsSheetRoute.swift, ReaderChromeButton.swift,
//   ReaderMoreMenuEffect.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #62 — AnnotationsSheetRoute")
struct AnnotationsSheetRouteTests {

    // MARK: - Equatable

    @Test("Same case + same payload routes are equal")
    func sameCaseSamePayloadEqual() {
        #expect(
            AnnotationsSheetRoute.toc(initialTab: .contents)
                == AnnotationsSheetRoute.toc(initialTab: .contents)
        )
        #expect(
            AnnotationsSheetRoute.highlights(initialFilter: .all)
                == AnnotationsSheetRoute.highlights(initialFilter: .all)
        )
    }

    @Test("Same case + different payload routes are unequal")
    func sameCaseDifferentPayloadUnequal() {
        #expect(
            AnnotationsSheetRoute.toc(initialTab: .contents)
                != AnnotationsSheetRoute.toc(initialTab: .bookmarks)
        )
        #expect(
            AnnotationsSheetRoute.highlights(initialFilter: .all)
                != AnnotationsSheetRoute.highlights(initialFilter: .highlights)
        )
    }

    @Test("Different-case routes are unequal")
    func differentCaseUnequal() {
        #expect(
            AnnotationsSheetRoute.toc(initialTab: .contents)
                != AnnotationsSheetRoute.highlights(initialFilter: .all)
        )
    }

    // MARK: - id is the full payload (round-1 finding 1)

    @Test("toc id carries the initial tab — distinct per tab")
    func tocIdCarriesInitialTab() {
        // A kind-only id ("toc") would not re-present "same kind,
        // different initial tab" through .sheet(item:). The id must be
        // the full payload so each distinct route is a distinct sheet
        // identity.
        #expect(AnnotationsSheetRoute.toc(initialTab: .contents).id == "toc:Contents")
        #expect(AnnotationsSheetRoute.toc(initialTab: .bookmarks).id == "toc:Bookmarks")
        #expect(
            AnnotationsSheetRoute.toc(initialTab: .contents).id
                != AnnotationsSheetRoute.toc(initialTab: .bookmarks).id
        )
    }

    @Test("highlights id carries the initial filter — distinct per filter")
    func highlightsIdCarriesInitialFilter() {
        #expect(AnnotationsSheetRoute.highlights(initialFilter: .all).id == "highlights:All")
        #expect(
            AnnotationsSheetRoute.highlights(initialFilter: .highlights).id
                == "highlights:Highlights"
        )
        #expect(
            AnnotationsSheetRoute.highlights(initialFilter: .all).id
                != AnnotationsSheetRoute.highlights(initialFilter: .highlights).id
        )
    }

    @Test("toc and highlights ids never collide")
    func tocAndHighlightsIdsDistinct() {
        #expect(
            AnnotationsSheetRoute.toc(initialTab: .contents).id
                != AnnotationsSheetRoute.highlights(initialFilter: .all).id
        )
    }

    // MARK: - TOCSheetTab

    @Test("TOCSheetTab.allCases is exactly [.contents, .bookmarks]")
    func tocSheetTabAllCases() {
        #expect(TOCSheetTab.allCases == [.contents, .bookmarks])
    }

    @Test("TOCSheetTab raw values match the design contract")
    func tocSheetTabRawValues() {
        #expect(TOCSheetTab.contents.rawValue == "Contents")
        #expect(TOCSheetTab.bookmarks.rawValue == "Bookmarks")
        // The ordered raw-value list must equal the #60 design contract.
        #expect(
            TOCSheetTab.allCases.map(\.rawValue)
                == ReaderSheetKind.tableOfContents.sections
        )
    }

    @Test("TOCSheetTab systemImage names the design glyphs")
    func tocSheetTabSystemImage() {
        #expect(TOCSheetTab.contents.systemImage == "list.bullet")
        #expect(TOCSheetTab.bookmarks.systemImage == "bookmark")
    }

    @Test("TOCSheetTab id equals its raw value")
    func tocSheetTabIdEqualsRawValue() {
        for tab in TOCSheetTab.allCases {
            #expect(tab.id == tab.rawValue)
        }
    }

    // MARK: - HighlightsSheetFilter

    @Test("HighlightsSheetFilter.allCases is exactly [.all, .highlights, .notes, .bookmarks]")
    func highlightsSheetFilterAllCases() {
        #expect(HighlightsSheetFilter.allCases == [.all, .highlights, .notes, .bookmarks])
    }

    @Test("HighlightsSheetFilter raw values match the #60 design contract")
    func highlightsSheetFilterRawValues() {
        #expect(HighlightsSheetFilter.all.rawValue == "All")
        #expect(HighlightsSheetFilter.highlights.rawValue == "Highlights")
        #expect(HighlightsSheetFilter.notes.rawValue == "Notes")
        #expect(HighlightsSheetFilter.bookmarks.rawValue == "Bookmarks")
        // The ordered raw-value list must equal `ReaderSheetKind.annotations
        // .sections` — the split must not drift from the design contract.
        #expect(
            HighlightsSheetFilter.allCases.map(\.rawValue)
                == ReaderSheetKind.annotations.sections
        )
    }

    @Test("HighlightsSheetFilter id equals its raw value")
    func highlightsSheetFilterIdEqualsRawValue() {
        for filter in HighlightsSheetFilter.allCases {
            #expect(filter.id == filter.rawValue)
        }
    }

    // MARK: - route(forChromeButton:)

    @Test("Contents chrome button routes to the TOC sheet on the Contents tab")
    func contentsButtonRoutesToTOC() {
        #expect(
            AnnotationsSheetRoute.route(forChromeButton: .contents)
                == .toc(initialTab: .contents)
        )
    }

    @Test("Notes chrome button routes to the highlights sheet on the All filter")
    func notesButtonRoutesToHighlightsAll() {
        // The design's bottom-chrome routing: Notes → HighlightsSheet ·
        // All filter (NOT Highlights — the user reviews everything they
        // collected).
        #expect(
            AnnotationsSheetRoute.route(forChromeButton: .notes)
                == .highlights(initialFilter: .all)
        )
    }

    // MARK: - route(forMoreMenuEffect:)

    @Test("More-menu Export effect routes to the highlights sheet on the Highlights filter")
    func moreMenuExportRoutesToHighlightsFilter() {
        // The More-menu Export-annotations row reaches the export button
        // in `HighlightsSheet`'s trailing slot; it opens the sheet on the
        // Highlights filter.
        #expect(
            AnnotationsSheetRoute.route(forMoreMenuEffect: .presentAnnotationsExport)
                == .highlights(initialFilter: .highlights)
        )
    }

    // MARK: - Negative routes — non-annotations buttons / effects yield nil

    @Test("Display and AI chrome buttons do not route to an annotations sheet")
    func displayAndAIButtonsYieldNil() {
        // Only Contents + Notes open an annotations sheet; Display / AI
        // open their own surfaces. Pinned so future branch drift fails.
        #expect(AnnotationsSheetRoute.route(forChromeButton: .display) == nil)
        #expect(AnnotationsSheetRoute.route(forChromeButton: .ai) == nil)
    }

    @Test("Non-export More-menu effects do not route to an annotations sheet")
    func nonExportMoreMenuEffectsYieldNil() {
        #expect(AnnotationsSheetRoute.route(forMoreMenuEffect: .toggleReadAloud) == nil)
        #expect(AnnotationsSheetRoute.route(forMoreMenuEffect: .toggleAutoPageTurn) == nil)
        #expect(AnnotationsSheetRoute.route(forMoreMenuEffect: .presentBookDetails) == nil)
        #expect(AnnotationsSheetRoute.route(forMoreMenuEffect: .presentShareSheet) == nil)
    }
}
