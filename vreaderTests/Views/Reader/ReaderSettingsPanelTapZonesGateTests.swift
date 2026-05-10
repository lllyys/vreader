// Purpose: Regression-guard tests for bug #162 / GH #482 — the Tap Zones
// section is hidden in `ReaderSettingsPanel` when the configured zones
// would silently no-op. The gate combines (a) format capability
// (`.unifiedReflow`), (b) the user's current `readingMode`, and
// (c) whether the dispatch switch in `ReaderUnifiedDispatch` actually
// installs `.tapZoneOverlay` for that format. `TapZoneOverlay` lives
// only on the unified render path; native renderers post
// `.readerContentTapped` unconditionally and ignore `TapZoneConfig`.
// AZW3's unified path falls to `UnifiedPlaceholderView` (no overlay),
// and PDF is excluded from the unified switch entirely — so capability
// + mode alone is too loose. Without this gate, users on the dominant
// native code path (and on AZW3 / PDF in unified mode) saw a configurable
// picker whose selections did nothing.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
// vreader/Views/Reader/TapZoneOverlay.swift,
// vreader/Views/Reader/ReaderUnifiedDispatch.swift,
// vreader/Models/FormatCapabilities.swift,
// vreader/Models/ReadingMode.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSettingsPanel Tap Zones gate (bug #162 / GH #482)")
struct ReaderSettingsPanelTapZonesGateTests {

    // MARK: - Capability check

    @Test func gate_hidden_whenFormatLacksUnifiedReflow_evenInUnifiedMode() {
        // PDF and TXT lack `.unifiedReflow` (PDF never had it; bug #158
        // moved TXT off the unified preset). The capability check alone
        // hides the section in either reading mode for these formats.
        for format in [BookFormat.txt, .pdf] {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(
                !ReaderSettingsPanel.shouldShowTapZonesSection(
                    for: caps, format: format, currentMode: .unified
                ),
                "Expected \(format) to hide Tap Zones in Unified mode"
            )
            #expect(
                !ReaderSettingsPanel.shouldShowTapZonesSection(
                    for: caps, format: format, currentMode: .native
                ),
                "Expected \(format) to hide Tap Zones in Native mode"
            )
        }
    }

    // MARK: - Mode check

    @Test func gate_hidden_whenInNativeMode_evenForUnifiedReflowFormats() {
        // The core no-op trap: simple-EPUB / MD / AZW3 are Unified-capable,
        // but the user might still be on Native mode (the default for most
        // formats). In Native mode `TapZoneOverlay` isn't on the render
        // path, so the picker would silently no-op. Hide it.
        for format in [BookFormat.md, .epub, .azw3] {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(
                !ReaderSettingsPanel.shouldShowTapZonesSection(
                    for: caps, format: format, currentMode: .native
                ),
                "Expected \(format) to hide Tap Zones while in Native mode"
            )
        }
    }

    // MARK: - Dispatch-switch parity

    @Test func gate_hidden_forAZW3_evenInUnifiedMode_dueToPlaceholderDispatch() {
        // AZW3 is `.unifiedReflow`-capable, so `shouldShowReadingMode` shows
        // the Native/Unified picker. But AZW3's unified-mode dispatch falls
        // to `UnifiedPlaceholderView` in `ReaderUnifiedDispatch.swift:81-83`
        // — `.tapZoneOverlay(...)` is NEVER installed for AZW3, so any
        // configured zone would no-op even when the user picks Unified.
        // The gate must hide the section.
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(
            !ReaderSettingsPanel.shouldShowTapZonesSection(
                for: caps, format: .azw3, currentMode: .unified
            ),
            "AZW3 unified path is a placeholder; hide Tap Zones to avoid no-op picker"
        )
    }

    @Test func gate_visible_forTxtMdEpub_inUnifiedMode_whichInstallOverlay() {
        // The three formats whose unified-dispatch case actually attaches
        // `.tapZoneOverlay(config:)` per `ReaderUnifiedDispatch.swift:29,44,71`.
        // Show the picker for these — selections take real effect.
        // (TXT here is the dispatcher's TXT case; bug #158 hides Reading
        // Mode picker for TXT so users can't normally land here, but the
        // dispatch path remains and the gate must be self-consistent.)
        for format in [BookFormat.txt, .md, .epub] {
            let caps: FormatCapabilities = [.unifiedReflow]  // synthetic — TXT lacks this in factory but dispatcher would install
            #expect(
                ReaderSettingsPanel.shouldShowTapZonesSection(
                    for: caps, format: format, currentMode: .unified
                ),
                "Expected \(format) to show Tap Zones in Unified mode (dispatcher installs overlay)"
            )
        }
    }

    @Test func gate_visible_forMdAndEpub_realFactoryCaps_inUnifiedMode() {
        // End-to-end with real factory capabilities: MD and simple-EPUB
        // both have `.unifiedReflow` AND their dispatch installs the
        // overlay. Show.
        for format in [BookFormat.md, .epub] {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(
                ReaderSettingsPanel.shouldShowTapZonesSection(
                    for: caps, format: format, currentMode: .unified
                ),
                "Expected \(format) to show Tap Zones in Unified mode"
            )
        }
    }

    @Test func gate_helperSemantics_complexEPUBStillShowsAtRuntime() {
        // Same caveat as `chineseConversionSupported`: production sheet
        // caller in `ReaderContainerView` passes the simple-EPUB default
        // capability set, so a complex EPUB at runtime still shows the
        // picker even though the unified pipeline falls back to native
        // (no overlay). The helper itself respects whatever caps it gets;
        // the runtime gap is documented in the row body.
        let complexCaps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: true)
        #expect(
            !ReaderSettingsPanel.shouldShowTapZonesSection(
                for: complexCaps, format: .epub, currentMode: .unified
            ),
            "Helper hides section when complex-EPUB caps are explicitly supplied"
        )
    }

    // MARK: - Backward compat

    @Test func gate_visible_whenCapabilitiesNotSupplied() {
        // Backward compat: previews / older tests / call sites that
        // don't supply `formatCapabilities` still see the section.
        // Same default as the bug #156 / #158 gates.
        #expect(ReaderSettingsPanel.shouldShowTapZonesSection(
            for: nil, format: nil, currentMode: .native
        ))
        #expect(ReaderSettingsPanel.shouldShowTapZonesSection(
            for: nil, format: .txt, currentMode: .unified
        ))
    }

    @Test func gate_visible_whenCapabilitiesSuppliedButFormatIsNil() {
        // When format is nil but capabilities are supplied (e.g. legacy
        // test that pre-dates the format parameter), trust the caps +
        // mode signal alone and assume the dispatch installs the overlay.
        let caps: FormatCapabilities = [.unifiedReflow]
        #expect(ReaderSettingsPanel.shouldShowTapZonesSection(
            for: caps, format: nil, currentMode: .unified
        ))
        #expect(!ReaderSettingsPanel.shouldShowTapZonesSection(
            for: caps, format: nil, currentMode: .native
        ))
    }

    @Test func gate_hidden_whenEmptyCapabilities() {
        // An empty capability set must hide the section in both modes —
        // defending against a future format that ships with all caps
        // disabled (e.g. read-only preview shell).
        #expect(!ReaderSettingsPanel.shouldShowTapZonesSection(
            for: [], format: .epub, currentMode: .unified
        ))
        #expect(!ReaderSettingsPanel.shouldShowTapZonesSection(
            for: [], format: .epub, currentMode: .native
        ))
    }
}
