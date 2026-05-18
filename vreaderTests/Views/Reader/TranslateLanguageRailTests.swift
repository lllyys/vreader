// Purpose: Feature #65 WI-3 — composition + tap-behaviour tests for
// the re-skinned Translate target-language pill rail
// (`TranslateLanguageRail`). The v2 re-skin replaces the native menu
// `Picker` + a separate `.borderedProminent` "Translate" button with a
// horizontally-scrolling pill rail whose pill tap fires translation
// directly.
//
// `TranslateLanguageRail` is a pure presentational view. Its honest
// unit-testable surface is two layers (the `AIChatMessageRow.form(for:)`
// / `AISummaryTabView.section(for:)` precedent):
//
//  1. Tap behaviour — `TranslateLanguageRail.tapAction(for:onSelect:)`
//     is the pure builder every pill's `Button(action:)` is wired to.
//     The design has NO separate Translate button, so a pill tap is the
//     only way to request a language. The Gate-2 audit (finding #3)
//     established that an `.onChange`-only rail has a first-use bug:
//     `targetLanguage` defaults to a preselected language, so that
//     default would be unrequestable. These tests pin that the tap
//     action fires `onSelect` with the tapped language on EVERY tap —
//     including a re-tap of the already-`selected` language — by
//     building the action identically for selected and unselected
//     pills and invoking it.
//
//  2. Composition — SwiftUI is forced to materialise `body` for
//     representative language lists across every `ReaderThemeV2` case
//     so a re-skin regression that traps the rail under a particular
//     theme/input is caught without a render pass.
//
// @coordinates-with: TranslateLanguageRail.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("Translate language rail re-skin — feature #65 WI-3")
@MainActor
struct TranslateLanguageRailTests {

    // MARK: - Fixtures

    /// The production language set (mirrors
    /// `AITranslationViewModel.supportedLanguages`).
    private static let languages: [String] = [
        "Chinese", "Japanese", "Korean", "Spanish", "French",
        "German", "Portuguese", "Russian", "Arabic",
    ]

    // MARK: - Tap behaviour — fire on every tap (Gate-2 finding #3)

    @Test("Tapping an unselected language fires onSelect with that language")
    func tappingUnselectedLanguageFiresOnSelect() {
        // A pill for a language other than `selected` must request it.
        var requested: [String] = []
        let action = TranslateLanguageRail.tapAction(for: "Japanese") {
            requested.append($0)
        }
        action()
        #expect(requested == ["Japanese"])
    }

    @Test("Tapping the ALREADY-SELECTED language STILL fires onSelect")
    func tappingSelectedLanguageStillFiresOnSelect() {
        // Gate-2 finding #3: `targetLanguage` defaults to a preselected
        // language ("Chinese"). The design has no separate Translate
        // button, so if a re-tap of the selected pill did nothing, the
        // default language would be unrequestable on first open. The
        // tap action is built identically regardless of selection, so
        // re-tapping `selected` must still fire `onSelect`.
        let selected = "Chinese"
        var requested: [String] = []
        // The body wires EVERY pill — including the `selected` one —
        // to `tapAction(for:onSelect:)`. Build the action for the
        // selected language exactly as the body does for that pill.
        let action = TranslateLanguageRail.tapAction(for: selected) {
            requested.append($0)
        }
        action()
        #expect(requested == [selected],
                "Re-tapping the preselected language must still request it")
    }

    @Test("Each language's tap action requests exactly that language")
    func eachLanguageTapActionRequestsThatLanguage() {
        // The rail builds one pill per language. Pin that the per-pill
        // tap action carries the correct language for every entry —
        // a re-skin that captured a shared loop variable by reference
        // would fail this.
        for language in Self.languages {
            var requested: String?
            let action = TranslateLanguageRail.tapAction(for: language) {
                requested = $0
            }
            action()
            #expect(requested == language)
        }
    }

    @Test("Repeated taps on the same pill fire onSelect each time")
    func repeatedTapsFireEachTime() {
        // The rail fires translation on every tap (no debounce in the
        // view) — `AITranslationViewModel.translate`'s in-flight
        // cancellation handles overlap. Pin that the action is not a
        // one-shot.
        var count = 0
        let action = TranslateLanguageRail.tapAction(for: "French") { _ in
            count += 1
        }
        action()
        action()
        action()
        #expect(count == 3)
    }

    // MARK: - Composition across themes (layout-trap regression guard)

    @Test(
        "The rail body builds for the full language list across every theme",
        arguments: ReaderThemeV2.allCases
    )
    func railBodyBuildsForEveryTheme(_ theme: ReaderThemeV2) {
        // A re-skin regression that traps the rail under a specific
        // theme (a token that traps, a selected-pill highlight that
        // crashes) surfaces here. All five themes must materialise
        // `body` without trapping — once with a `selected` that is in
        // the list and once with one that is not (defensive).
        let railSelected = TranslateLanguageRail(
            languages: Self.languages,
            selected: "Chinese",
            theme: theme,
            onSelect: { _ in }
        )
        _ = railSelected.body

        let railUnknownSelection = TranslateLanguageRail(
            languages: Self.languages,
            selected: "Esperanto",
            theme: theme,
            onSelect: { _ in }
        )
        _ = railUnknownSelection.body
    }

    @Test("The rail body builds for a single-language list")
    func railBodyBuildsForSingleLanguage() {
        // Defensive boundary: a one-pill rail where the only pill is the
        // selected one must still compose.
        let rail = TranslateLanguageRail(
            languages: ["Chinese"],
            selected: "Chinese",
            theme: .paper,
            onSelect: { _ in }
        )
        _ = rail.body
    }

    @Test("The rail body builds for an empty language list")
    func railBodyBuildsForEmptyList() {
        // Defensive boundary: the production list is never empty, but an
        // empty rail must compose around zero pills rather than trap.
        let rail = TranslateLanguageRail(
            languages: [],
            selected: "Chinese",
            theme: .dark,
            onSelect: { _ in }
        )
        _ = rail.body
    }

    @Test("The rail body builds for CJK language labels")
    func railBodyBuildsForCJKLabels() {
        // The rail's pills must lay out CJK label text (no inter-word
        // spaces) without trapping under a dark theme.
        let rail = TranslateLanguageRail(
            languages: ["中文", "日本語", "한국어"],
            selected: "中文",
            theme: .oled,
            onSelect: { _ in }
        )
        _ = rail.body
    }

    @Test("The rail body builds when selected is not in the language list")
    func railBodyBuildsWhenSelectedAbsent() {
        // Defensive: `selected` may be a value absent from `languages`.
        // No pill is highlighted; the rail must still compose.
        let rail = TranslateLanguageRail(
            languages: Self.languages,
            selected: "Klingon",
            theme: .photo,
            onSelect: { _ in }
        )
        _ = rail.body
    }
}
