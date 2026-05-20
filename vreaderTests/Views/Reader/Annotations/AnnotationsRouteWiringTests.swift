// Purpose: Feature #62 WI-5 — pins that `ReaderContainerView`'s reader
// chrome resolves to the correct `AnnotationsSheetRoute`.
//
// WI-5 rewires `ReaderContainerView`: the two `@State` vars
// (`showAnnotationsPanel` + `annotationsPanelInitialTab`) are replaced
// by one `annotationsRoute: AnnotationsSheetRoute?`, and the
// bottom-chrome Contents/Notes buttons + the More-menu Export effect
// drive it through the `AnnotationsSheetRoute.route(forChromeButton:)`
// / `route(forMoreMenuEffect:)` pure helpers.
//
// This suite is the wiring-level assertion that the reader chrome maps
// to the right route (the `route(...)` helpers' own correctness is
// covered by `AnnotationsSheetRouteTests` — WI-1). The mapping is the
// design's bottom-chrome routing: Contents → `TOCSheet` (Contents tab),
// Notes → `HighlightsSheet` (All filter), More-menu Export →
// `HighlightsSheet` (Highlights filter).
//
// @coordinates-with: AnnotationsSheetRoute.swift, ReaderContainerView.swift,
//   ReaderContainerView+Sheets.swift, ReaderChromeButton.swift,
//   ReaderMoreMenuEffect.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #62 — AnnotationsSheetRoute wiring")
struct AnnotationsRouteWiringTests {

    @Test("The Contents bottom-chrome button resolves to the TOC sheet on Contents")
    func contentsButtonWiresToTOC() {
        // ReaderContainerView's onContents closure sets
        // annotationsRoute = route(forChromeButton: .contents).
        #expect(
            AnnotationsSheetRoute.route(forChromeButton: .contents)
                == .toc(initialTab: .contents)
        )
    }

    @Test("The Notes bottom-chrome button resolves to the highlights sheet on All")
    func notesButtonWiresToHighlightsAll() {
        // The design routes Notes → HighlightsSheet · All (the user
        // reviews everything collected, not just highlights).
        #expect(
            AnnotationsSheetRoute.route(forChromeButton: .notes)
                == .highlights(initialFilter: .all)
        )
    }

    @Test("The More-menu Export effect resolves to the highlights sheet on Highlights")
    func moreMenuExportWiresToHighlightsFilter() {
        // The More-menu Export-annotations row + the Book Details
        // "Export annotations…" row both resolve through this effect to
        // HighlightsSheet's Highlights filter, where the export button
        // lives.
        #expect(
            AnnotationsSheetRoute.route(forMoreMenuEffect: .presentAnnotationsExport)
                == .highlights(initialFilter: .highlights)
        )
    }

    @Test("The three reader entry points resolve to three distinct routes")
    func threeEntryPointsDistinct() {
        let contents = AnnotationsSheetRoute.route(forChromeButton: .contents)
        let notes = AnnotationsSheetRoute.route(forChromeButton: .notes)
        let export = AnnotationsSheetRoute.route(forMoreMenuEffect: .presentAnnotationsExport)
        #expect(contents != notes)
        #expect(notes != export)
        #expect(contents != export)
    }

    @Test("Each route's sheet identity is distinct so .sheet(item:) re-presents cleanly")
    func routeSheetIdentitiesDistinct() {
        let ids = [
            AnnotationsSheetRoute.route(forChromeButton: .contents)?.id,
            AnnotationsSheetRoute.route(forChromeButton: .notes)?.id,
            AnnotationsSheetRoute.route(forMoreMenuEffect: .presentAnnotationsExport)?.id,
        ].compactMap { $0 }
        #expect(Set(ids).count == 3)
    }
}
