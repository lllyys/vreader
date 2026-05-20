// Purpose: Feature #67 WI-5 — `AISettingsSection` row-restyle
// composition test. Pins the WI-5 restyle: the AI Provider
// `NavigationLink` row uses the design's colored-icon `SettingsIconRow`
// (`SettingsRowPalette.aiProvider`), while the AI Assistant +
// Data & Privacy toggle rows stay on their existing plain-`Toggle`
// chrome (the design bundle does not depict colored-icon variants for
// those two — per rule 51 they're tracked under a `needs-design`
// follow-up, not invented here).
//
// Asserts the new `rowPaletteKeysForTesting` seam returns the AI
// rows' palette keys in render order across both the `isAIEnabled
// == false` (toggle visible, provider hidden) and `isAIEnabled ==
// true` (all 3 rows visible) states.

import Testing
import SwiftUI
@testable import vreader

@Suite("AISettingsSection restyle — feature #67 WI-5")
@MainActor
struct AISettingsSectionRestyleTests {

    /// Builds an `AISettingsSection` over an inert VM (no Keychain, no
    /// SwiftData) — the section is a thin Section-wrapper, so the
    /// default VM is enough for composition assertions.
    private func makeSection(isAIEnabled: Bool) -> AISettingsSection {
        let vm = AISettingsViewModel()
        vm.isAIEnabled = isAIEnabled
        return AISettingsSection(viewModel: vm)
    }

    // MARK: - Build

    @Test func section_builds_when_AI_disabled() {
        let section = makeSection(isAIEnabled: false)
        _ = section.body
    }

    @Test func section_builds_when_AI_enabled() {
        let section = makeSection(isAIEnabled: true)
        _ = section.body
    }

    // MARK: - rowPaletteKeysForTesting seam

    /// When AI is disabled, only the Enable toggle is visible — no
    /// design-colored row renders, so the palette keys are empty.
    @Test func rowPaletteKeys_whenAIDisabled_areEmpty() {
        let section = makeSection(isAIEnabled: false)
        #expect(section.rowPaletteKeysForTesting == [])
    }

    /// When AI is enabled, the AI Provider `NavigationLink` row
    /// renders the design's colored-icon style (palette key
    /// `aiProvider`). The two toggle rows (`aiToggle` /
    /// `consentToggle`) do NOT have palette entries because the
    /// design does not depict them as colored-icon rows.
    @Test func rowPaletteKeys_whenAIEnabled_includes_aiProvider() {
        let section = makeSection(isAIEnabled: true)
        #expect(section.rowPaletteKeysForTesting ==
                [SettingsRowPalette.aiProvider.paletteKey])
    }

    // MARK: - Restyled row composition

    @Test func providerRow_composition_uses_paletteSpec() {
        let section = makeSection(isAIEnabled: true)
        let row = section.providerRowForTesting
        // The row is built from the `aiProvider` palette spec — its
        // identity is the spec itself, so the test pins the contract.
        #expect(row.specForTesting == SettingsRowPalette.aiProvider)
    }
}
