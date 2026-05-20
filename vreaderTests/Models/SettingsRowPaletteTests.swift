// Purpose: Tests for SettingsRowPalette — the design data pinning each
// Settings-sheet row's brand color + SF Symbol against the committed
// design bundle (`vreader-panels.jsx` `SettingsSheet` `Row`). Feature
// #67 WI-2 introduced the six core-group specs; WI-5 adds the AI
// group's `aiProvider` row (the only AI row depicted in the design).

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("SettingsRowPalette")
struct SettingsRowPaletteTests {

    /// The six core-group specs WI-2 declares (Cloud & Sync / Reading /
    /// About rows). WI-5 adds the AI-group specs later.
    private var coreSpecs: [SettingsRowSpec] {
        [
            SettingsRowPalette.webDAVBackup,
            SettingsRowPalette.bookSources,
            SettingsRowPalette.replacementRules,
            SettingsRowPalette.httpTTS,
            SettingsRowPalette.helpFeedback,
            SettingsRowPalette.version
        ]
    }

    @Test func everySpecHasANonEmptySymbolName() {
        for spec in coreSpecs {
            #expect(!spec.symbolName.isEmpty, "symbolName for \(spec.paletteKey)")
        }
    }

    @Test func everySymbolNameResolvesToARealSFSymbol() {
        for spec in coreSpecs {
            #expect(
                UIImage(systemName: spec.symbolName) != nil,
                "\(spec.symbolName) is a real SF Symbol"
            )
        }
    }

    @Test func everySpecHasAUniquePaletteKey() {
        let keys = coreSpecs.map(\.paletteKey)
        #expect(Set(keys).count == keys.count, "no duplicate palette keys")
    }

    @Test func allSpecsArePairwiseDistinct() {
        // No accidental copy-paste duplicate spec.
        for i in coreSpecs.indices {
            for j in coreSpecs.indices where j > i {
                #expect(coreSpecs[i] != coreSpecs[j], "specs \(i) and \(j) differ")
            }
        }
    }

    // MARK: - Design-symbol pins (vreader-panels.jsx `SettingsSheet`)

    @Test func everySpecPinsItsDesignSymbol() {
        // Each row's SF Symbol token must match the design glyph it
        // depicts — a regression here ships a visibly wrong icon.
        #expect(SettingsRowPalette.webDAVBackup.symbolName == "cloud")          // Icons.Cloud
        #expect(SettingsRowPalette.bookSources.symbolName == "books.vertical")  // Icons.Library
        #expect(SettingsRowPalette.replacementRules.symbolName == "note.text")  // Icons.Note
        #expect(SettingsRowPalette.httpTTS.symbolName == "speaker.wave.2")      // Icons.Volume
        #expect(SettingsRowPalette.helpFeedback.symbolName == "questionmark")   // literal "?"
        #expect(SettingsRowPalette.version.symbolName == "note.text")           // Icons.Note
    }

    @Test func everySpecPinsItsPaletteKey() {
        #expect(SettingsRowPalette.webDAVBackup.paletteKey == "webDAVBackup")
        #expect(SettingsRowPalette.bookSources.paletteKey == "bookSources")
        #expect(SettingsRowPalette.replacementRules.paletteKey == "replacementRules")
        #expect(SettingsRowPalette.httpTTS.paletteKey == "httpTTS")
        #expect(SettingsRowPalette.helpFeedback.paletteKey == "helpFeedback")
        #expect(SettingsRowPalette.version.paletteKey == "version")
    }

    // MARK: - Design-hex pins (vreader-panels.jsx `SettingsSheet`)

    @Test func webDAVBackupMatchesDesignHex() {
        // Cloud icon, `#3a8ac8`.
        #expect(SettingsRowPalette.webDAVBackup.background == RGBComponents(r: 0x3a, g: 0x8a, b: 0xc8))
    }

    @Test func bookSourcesMatchesDesignHex() {
        // Library icon, `#3a6a5a`.
        #expect(SettingsRowPalette.bookSources.background == RGBComponents(r: 0x3a, g: 0x6a, b: 0x5a))
    }

    @Test func replacementRulesMatchesDesignHex() {
        // Note icon, `#a8804a`.
        #expect(SettingsRowPalette.replacementRules.background == RGBComponents(r: 0xa8, g: 0x80, b: 0x4a))
    }

    @Test func httpTTSMatchesDesignHex() {
        // Volume icon, `#3a3a8c` (the design's "Text-to-speech" row color).
        #expect(SettingsRowPalette.httpTTS.background == RGBComponents(r: 0x3a, g: 0x3a, b: 0x8c))
    }

    @Test func helpFeedbackMatchesDesignHex() {
        // "?" glyph, `#5a5a5a`.
        #expect(SettingsRowPalette.helpFeedback.background == RGBComponents(r: 0x5a, g: 0x5a, b: 0x5a))
    }

    @Test func versionMatchesDesignHex() {
        // Note icon, `#999` → `#999999`.
        #expect(SettingsRowPalette.version.background == RGBComponents(r: 0x99, g: 0x99, b: 0x99))
    }

    // MARK: - RGBComponents

    @Test func rgbComponentsAreEquatableByValue() {
        #expect(RGBComponents(r: 1, g: 2, b: 3) == RGBComponents(r: 1, g: 2, b: 3))
        #expect(RGBComponents(r: 1, g: 2, b: 3) != RGBComponents(r: 1, g: 2, b: 4))
    }

    @Test func rgbComponentsClampToByteRange() {
        // Out-of-range inputs clamp into 0...255 so a fractional color
        // channel can never exceed 1.0.
        let high = RGBComponents(r: 999, g: -5, b: 256)
        #expect(high.r == 255)
        #expect(high.g == 0)
        #expect(high.b == 255)
    }

    // MARK: - AI group (WI-5)

    /// The AI rows WI-5 adds. Currently only one — `aiProvider` —
    /// because the design bundle (`vreader-panels.jsx` line 869) only
    /// depicts the AI provider row. The AI Assistant + Data & Privacy
    /// toggle rows are not in the palette: per rule 51 their visual
    /// treatment must come from a committed design, not an invented one.
    private var aiSpecs: [SettingsRowSpec] {
        [SettingsRowPalette.aiProvider]
    }

    @Test func aiProvider_hasNonEmptySymbolName_andResolves() {
        for spec in aiSpecs {
            #expect(!spec.symbolName.isEmpty, "symbolName for \(spec.paletteKey)")
            #expect(UIImage(systemName: spec.symbolName) != nil,
                    "\(spec.symbolName) is a real SF Symbol")
        }
    }

    @Test func aiProvider_paletteKey_isPinned() {
        #expect(SettingsRowPalette.aiProvider.paletteKey == "aiProvider")
    }

    @Test func aiProvider_pinsItsDesignSymbol_andHex() {
        // `vreader-panels.jsx:869` — `Icons.Sparkle` `#8c2f2f`.
        #expect(SettingsRowPalette.aiProvider.symbolName == "sparkles")
        #expect(SettingsRowPalette.aiProvider.background ==
                RGBComponents(r: 0x8c, g: 0x2f, b: 0x2f))
    }

    @Test func aiProvider_isDistinct_fromEveryCoreSpec() {
        for core in coreSpecs {
            #expect(SettingsRowPalette.aiProvider != core,
                    "aiProvider must not collide with \(core.paletteKey)")
            #expect(SettingsRowPalette.aiProvider.paletteKey != core.paletteKey,
                    "no palette-key collision with \(core.paletteKey)")
        }
    }
}
