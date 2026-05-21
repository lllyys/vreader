// Purpose: Feature #67 WI-5 + WI-6 — `AISettingsSection` row-restyle
// composition test.
//
// WI-5 restyled the AI Provider `NavigationLink` row to the design's
// colored-icon `SettingsIconRow` (`SettingsRowPalette.aiProvider`).
//
// WI-6 (design #1068 `vreader-ai-toggles.jsx`, Variant A — now
// unblocked) restyles the AI Assistant master toggle + the
// Data & Privacy consent toggle to the design's `SettingsToggleRow`
// (colored tile + `PillSwitch`), so the AI group now renders three
// design-colored rows: AI Assistant (always), AI Provider + Allow AI
// data sharing (when AI on).
//
// Asserts the `rowPaletteKeysForTesting` seam returns the AI rows'
// palette keys in render order across both the `isAIEnabled == false`
// (master toggle only) and `isAIEnabled == true` (all 3 rows) states.

import Testing
import SwiftUI
@testable import vreader

@Suite("AISettingsSection restyle — feature #67 WI-5 + WI-6")
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

    /// When AI is disabled, the AI Assistant master toggle is the only
    /// visible row — and WI-6 restyles it to a colored `SettingsToggleRow`,
    /// so its palette key (`aiAssistant`) renders. The provider + consent
    /// rows are hidden.
    @Test func rowPaletteKeys_whenAIDisabled_isMasterToggleOnly() {
        let section = makeSection(isAIEnabled: false)
        #expect(section.rowPaletteKeysForTesting ==
                [SettingsRowPalette.aiAssistant.paletteKey])
    }

    /// When AI is enabled, all three rows render in Variant-A order:
    /// AI Assistant (master toggle) → AI Provider (nav) → Allow AI data
    /// sharing (consent toggle).
    @Test func rowPaletteKeys_whenAIEnabled_areAllThreeInOrder() {
        let section = makeSection(isAIEnabled: true)
        #expect(section.rowPaletteKeysForTesting == [
            SettingsRowPalette.aiAssistant.paletteKey,
            SettingsRowPalette.aiProvider.paletteKey,
            SettingsRowPalette.aiDataSharing.paletteKey
        ])
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
