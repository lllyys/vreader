// Purpose: Feature #56 WI-13 — pin `PDFBilingualPanel`'s public
// contract. The panel is a pure SwiftUI sub-view; its render path
// stays untested here (no pixel snapshotting), but the inputs it
// consumes + accessibility identifiers it exposes + lang-glyph
// resolution are the contract XCUITest harnesses bind to.
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-pdf-translation.jsx`
//   — `PDFTranslationPanel` (variant A).
//
// @coordinates-with: PDFBilingualPanel.swift,
//   PDFBilingualPanelState.swift, BilingualPill.swift,
//   BilingualLanguage.swift, ReaderThemeV2.swift

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #56 WI-13 — PDFBilingualPanel")
struct PDFBilingualPanelTests {

    // MARK: - Accessibility identifiers

    @Test func panelExposesRootIdentifier() {
        #expect(PDFBilingualPanel.accessibilityIdentifier == "pdfBilingualPanel")
    }

    @Test func panelExposesPerStateIdentifiers() {
        // Per-state suffixes the XCUITest harness uses to wait on a
        // specific state — design canvas §C side-by-side comparison.
        #expect(PDFBilingualPanel.identifier(forState: .off) == "pdfBilingualPanel.off")
        #expect(PDFBilingualPanel.identifier(forState: .loading) == "pdfBilingualPanel.loading")
        #expect(
            PDFBilingualPanel.identifier(forState: .translated(segments: ["x"]))
                == "pdfBilingualPanel.translated")
        #expect(PDFBilingualPanel.identifier(forState: .offline) == "pdfBilingualPanel.offline")
        #expect(PDFBilingualPanel.identifier(forState: .empty) == "pdfBilingualPanel.empty")
    }

    @Test func panelExposesRetryAndOpenAIIdentifiers() {
        // The .offline state has two CTAs — retry + open-AI-tab —
        // identified individually so a XCUITest can tap either.
        #expect(PDFBilingualPanel.retryButtonIdentifier == "pdfBilingualPanelRetryButton")
        #expect(PDFBilingualPanel.openAITabButtonIdentifier == "pdfBilingualPanelOpenAITabButton")
    }

    @Test func panelExposesChevronIdentifier() {
        // The chevron toggle's identifier is fixed; the rotation
        // direction is implicit in the rendered SVG, not in the id.
        #expect(PDFBilingualPanel.chevronButtonIdentifier == "pdfBilingualPanelChevron")
    }

    // MARK: - Language glyph resolution

    @Test func languageGlyph_resolvesChinese() {
        #expect(PDFBilingualPanel.glyph(forLanguage: "Chinese") == "中")
    }

    @Test func languageGlyph_resolvesJapanese() {
        #expect(PDFBilingualPanel.glyph(forLanguage: "Japanese") == "日")
    }

    @Test func languageGlyph_resolvesSpanish() {
        // Design canvas: `(lang === 'Chinese') ? '中' : (lang === 'Japanese' ? '日' : 'Es')`.
        // Spanish + every other "Latin alphabet" target falls back to "Es".
        #expect(PDFBilingualPanel.glyph(forLanguage: "Spanish") == "Es")
    }

    @Test func languageGlyph_unknownFallsBackToChinese() {
        // Per-design fallback to the first language entry when the
        // user's prior choice was deleted (mirrors BilingualPill).
        #expect(PDFBilingualPanel.glyph(forLanguage: "Klingon") == "中")
    }

    // MARK: - Status suffix

    @Test func statusSuffix_default_isEmpty() {
        // The header "Page 42 · translating…" suffix is empty for the
        // default state (just "Page 42").
        let suffix = PDFBilingualPanel.statusSuffix(forState: .translated(segments: ["x"]))
        #expect(suffix == nil)
    }

    @Test func statusSuffix_loading_isTranslating() {
        let suffix = PDFBilingualPanel.statusSuffix(forState: .loading)
        #expect(suffix == "translating…")
    }

    @Test func statusSuffix_offline_isOffline() {
        let suffix = PDFBilingualPanel.statusSuffix(forState: .offline)
        #expect(suffix == "offline")
    }

    @Test func statusSuffix_empty_isNoTextOnPage() {
        let suffix = PDFBilingualPanel.statusSuffix(forState: .empty)
        #expect(suffix == "no text on page")
    }

    // MARK: - Heights (per-design)

    @Test func expandedHeight_matchesDesign() {
        // Design canvas: `splitPanelH = 260` when not collapsed.
        #expect(PDFBilingualPanel.expandedHeight == 260)
    }

    @Test func collapsedHeight_matchesDesign() {
        // Design canvas: `headerH = 38` when collapsed (header only).
        #expect(PDFBilingualPanel.collapsedHeight == 38)
    }
}
