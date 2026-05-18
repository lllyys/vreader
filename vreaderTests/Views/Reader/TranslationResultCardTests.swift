// Purpose: Feature #65 WI-3 — composition tests for the re-skinned
// Translate result card (`TranslationResultCard`). The v2 re-skin
// replaces the plain-text `BilingualView` (system-font side-by-side /
// stacked panels) with the design's stacked cards: an "English
// (Original)" card with a serif body, and an accent-tinted translation
// card labelled with the target language.
//
// `TranslationResultCard` is a pure presentational view. Its honest
// unit-testable surface is two layers (the `AIChatMessageRow.form(for:)`
// precedent):
//
//  1. Behaviour — `translationFontFamily(for:)` is the pure
//     per-language serif-stack switch (CJK → the CJK-capable system
//     stack, everything else → the Latin serif), and `originalCardLabel`
//     pins the honest "Original" label decision (the source language
//     is unknown — plan §2.2). Both are asserted directly.
//
//  2. Composition — SwiftUI is forced to materialise `body` for
//     representative original / translated / target-language inputs
//     (empty, long, CJK, RTL) across every `ReaderThemeV2` case so a
//     re-skin regression that traps the card under a particular theme
//     or input is caught without a render pass.
//
// Per plan §2.2 the design's "Speak" button and "Notes on the
// translation" card are OMITTED — the card's public surface carries no
// speak / notes hook, which the compile-shaped test below pins.
//
// @coordinates-with: TranslationResultCard.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("Translate result card re-skin — feature #65 WI-3")
@MainActor
struct TranslationResultCardTests {

    // MARK: - Fixtures

    /// Representative text inputs the card must lay out: an empty string
    /// (no result yet rendered into the card), a long multi-sentence
    /// string, CJK text (no inter-word spaces — exercises the serif
    /// body's wrapping path), and an RTL Arabic string (bidi text
    /// through both cards).
    private static let textInputs: [String] = [
        "",
        String(repeating: "It is a truth universally acknowledged that a "
            + "single man in possession of a good fortune must be in want "
            + "of a wife. ", count: 16),
        "凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。",
        "إنها حقيقة معترف بها عالميًا أن الرجل الأعزب الذي يمتلك ثروة جيدة "
            + "لا بد أنه في حاجة إلى زوجة.",
    ]

    /// Target-language labels the accent translation card must render —
    /// including CJK labels (the design tints the translation card and
    /// labels it with the target language).
    private static let targetLanguages: [String] = [
        "Chinese", "Japanese", "Korean", "Spanish", "Arabic", "中文",
    ]

    // MARK: - Composition across themes (layout-trap regression guard)

    @Test(
        "The card body builds for representative inputs across every theme",
        arguments: ReaderThemeV2.allCases
    )
    func cardBodyBuildsForEveryThemeAndInput(_ theme: ReaderThemeV2) {
        // A re-skin regression that traps the card under a specific
        // theme/input combination (a token that traps, a layout that
        // crashes on empty text, a CJK/RTL wrapping fault) surfaces
        // here. All five themes must materialise `body` for every
        // original × translated × target-language combination without
        // trapping.
        for original in Self.textInputs {
            for translated in Self.textInputs {
                let card = TranslationResultCard(
                    originalText: original,
                    translatedText: translated,
                    targetLanguage: "Chinese",
                    theme: theme
                )
                _ = card.body
            }
        }
    }

    @Test("The card body builds for every target-language label")
    func cardBodyBuildsForEveryTargetLanguage() {
        // The accent translation card is labelled with the target
        // language. Pin that every label — including a CJK label —
        // composes without trapping.
        for language in Self.targetLanguages {
            let card = TranslationResultCard(
                originalText: "Original sentence.",
                translatedText: "Translated sentence.",
                targetLanguage: language,
                theme: .paper
            )
            _ = card.body
        }
    }

    @Test("The card body builds for an empty translated string")
    func cardBodyBuildsForEmptyTranslation() {
        // Defensive: a translation is never rendered into this card
        // before the result lands (the panel shows the loading view
        // instead), but the accent card must still compose around an
        // empty string rather than trap.
        let card = TranslationResultCard(
            originalText: "Original text waiting for a translation.",
            translatedText: "",
            targetLanguage: "Japanese",
            theme: .dark
        )
        _ = card.body
    }

    @Test("The card body builds for an empty original string")
    func cardBodyBuildsForEmptyOriginal() {
        // Defensive boundary: the original card must compose around an
        // empty string.
        let card = TranslationResultCard(
            originalText: "",
            translatedText: "翻译后的文本。",
            targetLanguage: "Chinese",
            theme: .sepia
        )
        _ = card.body
    }

    @Test("The card body builds for a long original + translation pair")
    func cardBodyBuildsForLongTexts() {
        let long = String(
            repeating: "Netherfield Park is let at last, and the news "
                + "ripples through the neighbourhood as the families "
                + "consider the new arrival. ",
            count: 30
        )
        let card = TranslationResultCard(
            originalText: long,
            translatedText: long,
            targetLanguage: "French",
            theme: .oled
        )
        _ = card.body
    }

    @Test("The card body builds for a CJK translation (no-space wrapping)")
    func cardBodyBuildsForCJKTranslation() {
        // The design renders CJK translations with a CJK serif stack.
        // CJK has no inter-word spaces; the accent card's wrapping must
        // not trap. Pin composition under a photo theme.
        let card = TranslationResultCard(
            originalText: "It is a truth universally acknowledged.",
            translatedText: "凡是有钱的单身汉，总想娶位太太，"
                + "这已经成了一条举世公认的真理。",
            targetLanguage: "Chinese",
            theme: .photo
        )
        _ = card.body
    }

    @Test("The card body builds for an RTL translation")
    func cardBodyBuildsForRTLTranslation() {
        // Bidi text through the accent translation card must not trap.
        let card = TranslationResultCard(
            originalText: "It is a truth universally acknowledged.",
            translatedText: "إنها حقيقة معترف بها عالميًا.",
            targetLanguage: "Arabic",
            theme: .paper
        )
        _ = card.body
    }

    // MARK: - Omitted controls (plan §2.2)

    @Test("TranslationResultCard exposes no Speak / Notes hooks (omitted)")
    func speakAndNotesAreAbsent() {
        // The committed design's `TranslateView` draws a "Speak" button
        // on the accent card and a "Notes on the translation" card.
        // Per plan §2.2 both are unbacked (no TTS-in-AI-sheet path; the
        // translation contract returns one string) and OMITTED. The
        // card's public surface is exactly `originalText` +
        // `translatedText` + `targetLanguage` + `theme` — no `onSpeak`,
        // no `notes`. This compile-time-shaped test pins that the card
        // was not built with the unbacked hooks.
        let card = TranslationResultCard(
            originalText: "x",
            translatedText: "y",
            targetLanguage: "Chinese",
            theme: .paper
        )
        _ = card.body
        // If a Speak/Notes parameter were added without a default the
        // four-arg initialiser above would not compile.
    }

    // MARK: - Translation font-family switch (behavioural)

    @Test("CJK target languages select the CJK-capable system font stack")
    func cjkTargetLanguagesSelectSystemFont() {
        // The translation card switches the serif stack on the target
        // language: Chinese / Japanese / Korean — English or native
        // labels — must render with the CJK-capable `.system` stack.
        for language in ["Chinese", "Japanese", "Korean", "中文", "日本語", "한국어"] {
            #expect(
                TranslationResultCard.translationFontFamily(for: language) == .system,
                "\(language) is CJK — must select the CJK-capable .system stack"
            )
        }
    }

    @Test("Non-CJK target languages select the Latin serif stack")
    func latinTargetLanguagesSelectSerif() {
        for language in ["Spanish", "French", "German", "Portuguese",
                         "Russian", "Arabic", "English"] {
            #expect(
                TranslationResultCard.translationFontFamily(for: language) == .sourceSerif4,
                "\(language) is non-CJK — must select the Latin .sourceSerif4 stack"
            )
        }
    }

    @Test("An unknown or empty target language falls back to the Latin serif")
    func unknownOrEmptyTargetLanguageFallsBackToSerif() {
        // Defensive: the production language list never yields these,
        // but the switch's `default` must not pick the CJK stack.
        #expect(TranslationResultCard.translationFontFamily(for: "") == .sourceSerif4)
        #expect(TranslationResultCard.translationFontFamily(for: "Klingon") == .sourceSerif4)
    }

    // MARK: - Original-card label (design decision pin)

    @Test("The original card is labelled 'Original' — the source language is unknown")
    func originalCardLabelIsHonestOriginal() {
        // The committed design labels this card "English (Original)",
        // but the translation contract carries no source-language
        // field, so the honest label is "Original" (plan §2.2). Pin it
        // so a re-skin cannot regress to a hardcoded source language.
        #expect(TranslationResultCard.originalCardLabel == "Original")
    }
}
