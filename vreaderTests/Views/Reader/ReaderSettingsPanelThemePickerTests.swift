// Purpose: Composition-contract tests for the `ReaderSettingsPanel`
// theme picker — Feature #60 WI-11. WI-11 migrates
// `ReaderSettingsStore.theme` to `ReaderThemeV2` and switches the
// picker to iterate `ReaderThemeV2.allCases` so all 5 themes
// (Paper / Sepia / Dark / OLED / Photo) become user-selectable. The
// pre-WI-11 picker iterated the legacy 3-case `ReaderTheme.allCases`,
// leaving OLED and Photo unreachable — that gap closed acceptance
// criterion (c) of feature #60.
//
// These tests pin the picker's data source via a testable static
// helper (`ReaderSettingsPanel.themePickerThemes`) — the same
// composition-test pattern as `ReaderSettingsPanelReadingModeGateTests`
// (`shouldShowReadingModeSection`). SwiftUI body rendering is not
// pixel-tested; the contract is "the picker offers exactly these 5
// themes, in the design's order".
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
//   vreader/Models/ReaderThemeV2.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderSettingsPanel theme picker (Feature #60 WI-11)")
struct ReaderSettingsPanelThemePickerTests {

    /// The picker must offer all 5 `ReaderThemeV2` cases — including
    /// OLED and Photo, which the legacy 3-case picker could not reach.
    @Test func picker_offersAllFiveThemes() {
        let themes = ReaderSettingsPanel.themePickerThemes
        #expect(themes.count == 5)
        #expect(Set(themes) == Set(ReaderThemeV2.allCases))
    }

    /// OLED and Photo are the two themes WI-11 specifically unblocks —
    /// guard them explicitly so a regression that drops either is loud.
    @Test func picker_includesOLEDAndPhoto() {
        let themes = ReaderSettingsPanel.themePickerThemes
        #expect(themes.contains(.oled))
        #expect(themes.contains(.photo))
    }

    /// Picker order tracks the design bundle's `THEMES` declaration
    /// order (`vreader-themes.jsx`): paper, sepia, dark, oled, photo —
    /// which is exactly `ReaderThemeV2.allCases`.
    @Test func picker_orderMatchesDesignBundle() {
        #expect(
            ReaderSettingsPanel.themePickerThemes
                == [.paper, .sepia, .dark, .oled, .photo]
        )
    }

    /// Every offered theme has a non-empty human label for the swatch
    /// caption (Paper / Sepia / Dark / OLED / Photo per the design).
    @Test func picker_everyThemeHasADisplayName() {
        for theme in ReaderSettingsPanel.themePickerThemes {
            #expect(!ReaderSettingsPanel.themeDisplayName(theme).isEmpty)
        }
    }

    /// The display names match the design bundle's `name` fields.
    @Test func picker_displayNamesMatchDesign() {
        #expect(ReaderSettingsPanel.themeDisplayName(.paper) == "Paper")
        #expect(ReaderSettingsPanel.themeDisplayName(.sepia) == "Sepia")
        #expect(ReaderSettingsPanel.themeDisplayName(.dark) == "Dark")
        #expect(ReaderSettingsPanel.themeDisplayName(.oled) == "OLED")
        #expect(ReaderSettingsPanel.themeDisplayName(.photo) == "Photo")
    }
}
