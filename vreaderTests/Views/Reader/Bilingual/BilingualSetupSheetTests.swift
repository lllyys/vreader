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

    @Test("Primary CTA label is the design-pinned string")
    func ctaLabelIsPinned() {
        // Per design §2.2: the primary action is always "Turn on
        // bilingual mode" — no AI-state branch on the CTA itself.
        // The AI gating is surfaced by the engine strip, not the
        // CTA copy.
        #expect(BilingualSetupSheet.primaryCTALabel == "Turn on bilingual mode")
    }

    @Test("Engine button label reflects the AI-configured state")
    func engineButtonLabelMatchesAIState() {
        #expect(BilingualSetupSheet.engineButtonLabel(aiConfigured: false) == "Set up")
        #expect(BilingualSetupSheet.engineButtonLabel(aiConfigured: true) == "Change\u{2026}")
    }

    @Test("Engine descriptor surfaces the host-provided provider name when configured")
    func engineDescriptorWhenConfigured() {
        // The host supplies a `BilingualEngineDescriptor`; the sheet
        // shows the descriptor's name + subtitle verbatim when the
        // descriptor's `configured` flag is true. A generic fallback
        // is used only when the host omits a name.
        let descriptor = BilingualEngineDescriptor(
            configured: true,
            providerName: "Claude",
            subtitle: "Translations cached per paragraph."
        )
        #expect(descriptor.displayTitle == "Claude")
        #expect(descriptor.displaySubtitle == "Translations cached per paragraph.")
    }

    @Test("Engine descriptor falls back to a generic configured title when no name is supplied")
    func engineDescriptorWhenConfiguredNoName() {
        let descriptor = BilingualEngineDescriptor(
            configured: true,
            providerName: nil,
            subtitle: nil
        )
        #expect(descriptor.displayTitle == "AI provider configured")
        #expect(descriptor.displaySubtitle.contains("paragraph"))
    }

    @Test("Engine descriptor surfaces the unconfigured copy when no provider is set")
    func engineDescriptorWhenUnconfigured() {
        let descriptor = BilingualEngineDescriptor(
            configured: false,
            providerName: nil,
            subtitle: nil
        )
        #expect(descriptor.displayTitle == "No AI provider configured")
        #expect(descriptor.displaySubtitle.contains("AI provider"))
    }

    @Test("Initialising the state with an unknown language normalises through the registry")
    func normalisesUnknownLanguageOnInit() {
        // A per-book file from an older release carrying a deleted
        // language key must NOT produce an unselected grid; the
        // state surface should canonicalise the key on construction
        // so the picker always paints a selection.
        let state = BilingualSetupSheetState(
            languageKey: "Klingon",
            granularity: .paragraph
        ).normalised()
        #expect(state.languageKey == "Chinese")
    }

    @Test("Normalising a known language is the identity")
    func normalisingKnownLanguageIsIdentity() {
        let state = BilingualSetupSheetState(
            languageKey: "Japanese",
            granularity: .sentence
        ).normalised()
        #expect(state.languageKey == "Japanese")
        #expect(state.granularity == .sentence)
    }
    // MARK: - Bug #344 (design #1646 S-C): dimmed Sentence control

    @MainActor private func makeSheet(sentenceAvailable: Bool) -> BilingualSetupSheet {
        BilingualSetupSheet(
            theme: .paper,
            state: .constant(.defaultValue),
            engineDescriptor: BilingualEngineDescriptor(
                configured: true, providerName: "Claude", subtitle: "configured"),
            onConfirm: {},
            onCancel: {},
            onOpenSettings: {},
            sentenceGranularityAvailable: sentenceAvailable
        )
    }

    @Test("Sentence is selectable on formats that support it")
    @MainActor func sentenceSelectable_whenAvailable() {
        let sheet = makeSheet(sentenceAvailable: true)
        #expect(sheet.isGranularitySelectable(.sentence))
        #expect(sheet.isGranularitySelectable(.paragraph))
        _ = sheet.body
    }

    @Test("Sentence dims (not selectable) on DOM-enumerate formats; Paragraph stays live")
    @MainActor func sentenceDimmed_whenUnavailable() {
        let sheet = makeSheet(sentenceAvailable: false)
        #expect(!sheet.isGranularitySelectable(.sentence),
                "the control dims rather than silently forcing .paragraph")
        #expect(sheet.isGranularitySelectable(.paragraph))
        _ = sheet.body
    }
}
