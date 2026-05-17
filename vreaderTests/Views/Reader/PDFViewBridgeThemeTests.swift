// Purpose: Tests for PDFViewBridge's theme-background application — bug #198 / GH #710.
// Confirms PDFView.backgroundColor is set from the reader theme's backgroundColor so
// the page-area gutter flips to dark when the user picks a dark theme (was silently
// no-op before the fix). Tests the static helper, not the full UIViewRepresentable
// construction, so they remain fast and don't need a UIScene environment.
//
// The suite is @MainActor (bug #216 / GH #838): the helper still
// constructs a PDFView (a UIView subclass) and mutates its layer-backed
// backgroundColor, so the tests must run on the main thread. Without it,
// Swift Testing's parallel scheduler dispatches them off-main and every
// PDFView mutation trips UIKit's main-thread-only layer guard
// (_raiseExceptionForBackgroundThreadLayerPropertyModification), which
// crashes the test process intermittently.
//
// Feature #60 WI-11: `PDFViewBridge`'s theme parameter migrated from the legacy
// 3-case `ReaderTheme` to the 5-case `ReaderThemeV2` along with
// `ReaderSettingsStore.theme`. These tests track that — `.paper` replaces the
// legacy `.light`, and the gutter colour now comes from `ReaderThemeV2`'s
// `backgroundColor` token.

#if canImport(UIKit)
import Testing
import PDFKit
import UIKit
@testable import vreader

@Suite("PDFViewBridge — theme background (bug #198)")
@MainActor
struct PDFViewBridgeThemeTests {

    @Test
    func applyThemeBackground_dark_setsDarkBackgroundColor() {
        let pdfView = PDFView()
        pdfView.backgroundColor = .white  // simulates default
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .dark)
        #expect(pdfView.backgroundColor == ReaderThemeV2.dark.backgroundColor,
                "Dark theme must set PDFView.backgroundColor to the dark palette")
    }

    @Test
    func applyThemeBackground_sepia_setsSepiaBackgroundColor() {
        let pdfView = PDFView()
        pdfView.backgroundColor = .white
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .sepia)
        #expect(pdfView.backgroundColor == ReaderThemeV2.sepia.backgroundColor)
    }

    @Test
    func applyThemeBackground_paper_setsPaperBackgroundColor() {
        let pdfView = PDFView()
        pdfView.backgroundColor = .red  // any non-paper color
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .paper)
        #expect(pdfView.backgroundColor == ReaderThemeV2.paper.backgroundColor)
    }

    @Test
    func applyThemeBackground_oled_setsOLEDBackgroundColor() {
        // OLED is one of the two themes WI-11 makes user-selectable —
        // confirm the gutter honours it (pure black surround).
        let pdfView = PDFView()
        pdfView.backgroundColor = .white
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .oled)
        #expect(pdfView.backgroundColor == ReaderThemeV2.oled.backgroundColor)
    }

    @Test
    func applyThemeBackground_photo_setsPhotoBackgroundColor() {
        let pdfView = PDFView()
        pdfView.backgroundColor = .white
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .photo)
        #expect(pdfView.backgroundColor == ReaderThemeV2.photo.backgroundColor)
    }

    @Test
    func applyThemeBackground_dark_thenPaper_flipsBack() {
        // Regression guard: re-applying Paper after Dark must actually flip
        // BACK (no sticky state). Mirrors the user's bug-report flow:
        // Paper → Sepia → Dark should also work in reverse Dark → Paper.
        let pdfView = PDFView()
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .dark)
        #expect(pdfView.backgroundColor == ReaderThemeV2.dark.backgroundColor)
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .paper)
        #expect(pdfView.backgroundColor == ReaderThemeV2.paper.backgroundColor)
    }

    @Test
    func darkThemeBackground_isNotEqualToPaper() {
        // Sanity guard: the bug was Dark looking identical to Light because
        // nothing themed the PDFView. After the fix, the theme colors
        // must each be distinct so the user's eye can tell them apart.
        #expect(ReaderThemeV2.dark.backgroundColor != ReaderThemeV2.paper.backgroundColor)
        #expect(ReaderThemeV2.dark.backgroundColor != ReaderThemeV2.sepia.backgroundColor)
        #expect(ReaderThemeV2.paper.backgroundColor != ReaderThemeV2.sepia.backgroundColor)
    }

    @Test
    func applyThemeIfChanged_drivesProductionGuard() {
        // Drives the SAME helper that PDFViewBridge.makeUIView /
        // updateUIView call (PDFViewBridge.applyThemeIfChanged), so a future
        // regression that weakens the `lastAppliedTheme != theme` guard or
        // breaks the nil-coalescing fails here without needing a SwiftUI
        // host. The pure helper tests above only cover the unconditional
        // assignment; this test covers the gated dispatch and the
        // last-applied threading the bridge actually performs.
        let pdfView = PDFView()
        var lastApplied: ReaderThemeV2?

        // Initial mount with Paper: applied + last-applied advances to Paper.
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .paper, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderThemeV2.paper.backgroundColor)
        #expect(lastApplied == .paper)

        // Redundant update with same theme: short-circuit, no reapply.
        // Sentinel: pre-set a distinct color and confirm it survives.
        pdfView.backgroundColor = .red
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .paper, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == .red,
                "Same-theme update must short-circuit and not reapply")
        #expect(lastApplied == .paper)

        // User switches to Dark mid-session: reapplies.
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .dark, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderThemeV2.dark.backgroundColor)
        #expect(lastApplied == .dark)

        // Switch to OLED — a WI-11-unblocked theme — reapplies.
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .oled, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderThemeV2.oled.backgroundColor)
        #expect(lastApplied == .oled)

        // Switch back to Paper: reapplies (no sticky state across the cycle).
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .paper, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderThemeV2.paper.backgroundColor)
        #expect(lastApplied == .paper)

        // Nil theme on a fresh PDFView (preview / ad-hoc harness): no-op,
        // last-applied stays nil so the bridge keeps PDFKit's default gutter.
        let freshView = PDFView()
        let originalBackground = freshView.backgroundColor
        let result = PDFViewBridge.applyThemeIfChanged(
            pdfView: freshView, theme: nil, lastAppliedTheme: nil
        )
        #expect(freshView.backgroundColor == originalBackground)
        #expect(result == nil)
    }
}
#endif
