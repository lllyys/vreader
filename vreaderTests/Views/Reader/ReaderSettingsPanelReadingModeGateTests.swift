// Purpose: Regression-guard tests for bug #158 / GH #468 — the
// `ReadingModeSection` is hidden in `ReaderSettingsPanel` when the active
// format does not advertise `.unifiedReflow`. The gate is the user-visible
// half of the cheap-path fix (the other half lives in
// `FormatCapabilities.swift` removing `.unifiedReflow` from TXT). Without
// this gate, TXT users would see a Native/Unified picker that routes them
// into a partial-render dead-end.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
// vreader/Models/FormatCapabilities.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSettingsPanel Reading Mode gate (bug #158 / GH #468)")
struct ReaderSettingsPanelReadingModeGateTests {

    @Test func gate_hidden_whenFormatLacksUnifiedReflow() {
        // TXT lost `.unifiedReflow` in this fix; PDF never had it.
        // Both must hide the picker.
        let txtCaps = FormatCapabilities.capabilities(for: .txt)
        #expect(!ReaderSettingsPanel.shouldShowReadingModeSection(for: txtCaps))

        let pdfCaps = FormatCapabilities.capabilities(for: .pdf)
        #expect(!ReaderSettingsPanel.shouldShowReadingModeSection(for: pdfCaps))
    }

    @Test func gate_visible_whenFormatHasUnifiedReflow() {
        // MD, simple-EPUB, and AZW3 keep `.unifiedReflow` after the fix.
        for format in [BookFormat.md, .epub, .azw3] {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(
                ReaderSettingsPanel.shouldShowReadingModeSection(for: caps),
                "Expected \(format) to show Reading Mode picker"
            )
        }
    }

    @Test func gate_helperSemantics_followComplexEPUBCapability() {
        // Helper-semantics-only check: when caller explicitly supplies
        // a complex-EPUB capability set (`.unifiedReflow` removed), the
        // helper hides the picker. Note this is NOT end-to-end wiring —
        // the production sheet caller in `ReaderContainerView` passes
        // `BookFormat(...).capabilities` (the simple-EPUB default), so
        // a complex EPUB still shows the picker at runtime. Threading
        // an `isComplexEPUB` runtime signal through is feature-class
        // scope (same gap documented in `chineseConversionSupported`).
        let caps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: true)
        #expect(!ReaderSettingsPanel.shouldShowReadingModeSection(for: caps))
    }

    @Test func gate_visible_whenCapabilitiesNotSupplied() {
        // Backward compat: previews / older tests / call sites that
        // don't supply `formatCapabilities` still see the picker.
        // Matches the same default as the bug #156 auto-page-turn gate.
        #expect(ReaderSettingsPanel.shouldShowReadingModeSection(for: nil))
    }

    @Test func gate_visible_whenExplicitUnifiedReflowSupplied() {
        // Sanity check on the option-set membership rule, independent of
        // the per-format factory.
        let caps: FormatCapabilities = [.unifiedReflow]
        #expect(ReaderSettingsPanel.shouldShowReadingModeSection(for: caps))
    }

    @Test func gate_hidden_whenEmptyCapabilities() {
        // An empty capability set must hide the picker — defending
        // against the case where a future format ships with all caps
        // disabled (e.g. read-only preview shell).
        #expect(!ReaderSettingsPanel.shouldShowReadingModeSection(for: []))
    }
}
