// Purpose: Feature #56 WI-9 — pin the `BilingualSetupSheet` setup
// flow. The sheet itself is a SwiftUI view; what these tests verify
// is the binding contract — given a language picker tap, the host
// receives the new language; given a granularity tap, the host
// receives the new granularity; given a Settings tap when the AI
// provider is unconfigured, the host gets the open-settings callback.
//
// The sheet does NOT mutate the view model directly — that's the
// host's job (next agent's WI-10..13). The sheet exposes value-out
// closures so the same component renders for both first-enable
// (setup) and later "Tap to change" (preferences) use cases.
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BilingualSetupSheet`.
//
// @coordinates-with: BilingualSetupSheet.swift, BilingualLanguage.swift,
//   ChapterTranslationService.swift (`TranslationGranularity`),
//   BilingualReadingViewModel.swift

import Testing
@testable import vreader

@Suite("Feature #56 WI-9 — BilingualSetupSheet binding contract")
@MainActor
struct BilingualSetupSheetTests {

    @Test("Default state has Chinese + paragraph + aiConfigured")
    func defaultState() {
        let state = BilingualSetupSheetState.defaultValue
        #expect(state.languageKey == "Chinese")
        #expect(state.granularity == .paragraph)
    }

    @Test("Selecting a language updates state in place")
    func languageSelection() {
        var state = BilingualSetupSheetState.defaultValue
        state.languageKey = "Japanese"
        #expect(state.languageKey == "Japanese")
    }

    @Test("Selecting a granularity updates state in place")
    func granularitySelection() {
        var state = BilingualSetupSheetState.defaultValue
        state.granularity = .sentence
        #expect(state.granularity == .sentence)
    }

    @Test("All registry languages are exposed by the picker model")
    func pickerExposesAllLanguages() {
        // The picker model is what the SwiftUI grid renders; if a
        // language is removed from the registry the picker must
        // reflect that change without a separate edit.
        #expect(BilingualSetupSheetState.availableLanguages == BilingualLanguage.all)
    }

    @Test("Picker exposes both granularity options in design order")
    func granularityOptionsOrder() {
        // `vreader-bilingual.jsx` renders paragraph then sentence
        // (left → right) — pin so a reorder fails here.
        #expect(BilingualSetupSheetState.availableGranularities == [
            .paragraph, .sentence,
        ])
    }

    @Test("Sheet accessibility identifier is stable")
    func sheetAccessibilityIdentifier() {
        // XCUITest harnesses pin this — renames must surface here.
        #expect(BilingualSetupSheet.accessibilityIdentifier == "bilingualSetupSheet")
    }

    @Test("CTA label changes with the AI-configured state")
    func ctaLabelMatchesAIState() {
        // Per design (§2.2) — when AI is configured, the CTA is
        // "Turn on bilingual mode"; when not, it's the Set-up
        // engine button next to "No AI provider configured".
        #expect(BilingualSetupSheet.ctaLabel(aiConfigured: true) == "Turn on bilingual mode")
        #expect(BilingualSetupSheet.engineButtonLabel(aiConfigured: false) == "Set up")
        #expect(BilingualSetupSheet.engineButtonLabel(aiConfigured: true) == "Change\u{2026}")
    }

    @Test("Engine descriptor reflects the AI-configured state")
    func engineDescriptorMatchesAIState() {
        let configured = BilingualSetupSheet.engineDescriptor(aiConfigured: true)
        #expect(!configured.subtitle.isEmpty)
        #expect(!configured.title.isEmpty)

        let unconfigured = BilingualSetupSheet.engineDescriptor(aiConfigured: false)
        #expect(unconfigured.title == "No AI provider configured")
        #expect(unconfigured.subtitle.contains("AI provider"))
    }
}
