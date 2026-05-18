// Purpose: Tests for `TypefacePillToggle` — feature #66 WI-2. The
// custom typeface-preview pill toggle that replaces the native
// segmented `Picker` in `ReaderSettingsPanel`'s font-family section,
// matching the design bundle's segmented pill (`vreader-panels.jsx`,
// "Font" section).
//
// SwiftUI body rendering is not pixel-tested. The contract under test
// is the pill's data model and binding behavior: `TypefacePillToggle`
// re-skins the *current* `fontFamilySection` option set as-is — the
// three historical `ReaderFontFamily` cases the segmented picker
// presents (`.system` / `.serif` / `.monospace`). Per the feature #66
// plan §2 (Gate-2 round-1 High finding 1) it is a behavior-preserving
// re-skin: it does NOT reduce to the design's 2 options (a font-set
// reduction is a separate, out-of-scope behavior change).
//
// @coordinates-with: vreader/Views/Reader/Settings/TypefacePillToggle.swift,
//   vreader/Models/TypographySettings.swift

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("TypefacePillToggle (Feature #66 WI-2)")
struct TypefacePillToggleTests {

    // MARK: - Option set

    /// The pill presents exactly the option set the current
    /// `fontFamilySection` segmented picker presents — the three
    /// historical cases, in the picker's declaration order. NOT the
    /// design's 2 options, NOT all 5 `ReaderFontFamily` cases (plan §2).
    @Test func options_matchCurrentFontFamilyPicker() {
        let families = TypefacePillToggle.options.map(\.family)
        #expect(families == [.system, .serif, .monospace])
    }

    /// The pill is a faithful re-skin of the *current* control — it
    /// must NOT silently reduce to the design's 2-option set.
    @Test func options_doNotReduceToDesignTwoOptions() {
        #expect(TypefacePillToggle.options.count == 3)
        #expect(TypefacePillToggle.options.count != 2)
    }

    /// Every pill option carries a non-empty human label, matching the
    /// segmented picker's titles (System / Serif / Monospace).
    @Test func options_eachHasANonEmptyLabel() {
        for option in TypefacePillToggle.options {
            #expect(!option.label.isEmpty)
        }
    }

    /// The labels match the segmented picker the pill replaces.
    @Test func options_labelsMatchExistingPickerTitles() {
        let labels = TypefacePillToggle.options.map(\.label)
        #expect(labels == ["System", "Serif", "Monospace"])
    }

    // MARK: - Selection → binding

    /// Selecting a pill option writes that family through the binding —
    /// exercised for every option in the set.
    @Test @MainActor func selecting_eachOptionUpdatesTheBinding() {
        for option in TypefacePillToggle.options {
            var typography = TypographySettings(fontFamily: .system)
            let binding = Binding<ReaderFontFamily>(
                get: { typography.fontFamily },
                set: { typography.fontFamily = $0 }
            )
            let toggle = TypefacePillToggle(selection: binding, accessibilityLabel: "Font family")
            toggle.select(option.family)
            #expect(typography.fontFamily == option.family)
        }
    }

    // MARK: - Binding → selection

    /// The bound value pre-selects the matching pill — `isSelected`
    /// is true for exactly the bound family and false for the rest.
    @Test @MainActor func boundValue_preSelectsMatchingPill() {
        var typography = TypographySettings(fontFamily: .serif)
        let binding = Binding<ReaderFontFamily>(
            get: { typography.fontFamily },
            set: { typography.fontFamily = $0 }
        )
        let toggle = TypefacePillToggle(selection: binding, accessibilityLabel: "Font family")
        #expect(toggle.isSelected(.serif))
        #expect(!toggle.isSelected(.system))
        #expect(!toggle.isSelected(.monospace))
    }

    /// Pre-selection tracks a binding change — flipping the bound family
    /// moves which pill reports selected.
    @Test @MainActor func boundValue_preSelectionFollowsBindingChange() {
        var typography = TypographySettings(fontFamily: .system)
        let binding = Binding<ReaderFontFamily>(
            get: { typography.fontFamily },
            set: { typography.fontFamily = $0 }
        )
        let toggle = TypefacePillToggle(selection: binding, accessibilityLabel: "Font family")
        #expect(toggle.isSelected(.system))
        typography.fontFamily = .monospace
        #expect(toggle.isSelected(.monospace))
        #expect(!toggle.isSelected(.system))
    }

    // MARK: - Construction

    /// The toggle stores its accessibility label for the
    /// `.accessibilityRepresentation` Picker.
    @Test @MainActor func init_storesAccessibilityLabel() {
        var typography = TypographySettings()
        let binding = Binding<ReaderFontFamily>(
            get: { typography.fontFamily },
            set: { typography.fontFamily = $0 }
        )
        let toggle = TypefacePillToggle(selection: binding, accessibilityLabel: "Font family")
        #expect(toggle.accessibilityLabel == "Font family")
    }

    /// An out-of-set bound value (e.g. a persisted `.sourceSerif4` from
    /// the 5-case model) leaves every in-set pill unselected rather than
    /// crashing — the re-skin presents only the 3 picker options, but
    /// must tolerate a stored value outside that set.
    @Test @MainActor func boundValue_outOfSetFamilyLeavesAllPillsUnselected() {
        var typography = TypographySettings(fontFamily: .sourceSerif4)
        let binding = Binding<ReaderFontFamily>(
            get: { typography.fontFamily },
            set: { typography.fontFamily = $0 }
        )
        let toggle = TypefacePillToggle(selection: binding, accessibilityLabel: "Font family")
        for option in TypefacePillToggle.options {
            #expect(!toggle.isSelected(option.family))
        }
    }
}
