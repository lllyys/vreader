// Purpose: Feature #99 WI-2 — pins the setup sheet's edit framing
// (design §#1640 `BSSettingsSheet`): title, Cancel leading slot, the
// book-context strip, cached-language tick badges + caption, the cost
// strips' render slots, and the CTA label/fill per dirty kind — while
// first-enable mode stays byte-identical to the pre-#99 sheet.

import Testing
import SwiftUI
@testable import vreader

@Suite("BilingualSetupSheet edit mode (feature #99 WI-2)")
@MainActor
struct BilingualSetupSheetEditModeTests {

    private func makeSheet(
        mode: BilingualSetupSheetMode = .firstEnable,
        state: BilingualSetupSheetState = .defaultValue,
        cachedLanguages: Set<String> = [],
        currentLanguageKey: String? = nil,
        currentGranularity: TranslationGranularity? = nil
    ) -> BilingualSetupSheet {
        BilingualSetupSheet(
            theme: .paper,
            state: .constant(state),
            engineDescriptor: BilingualEngineDescriptor(
                configured: true, providerName: "Claude", subtitle: nil),
            onConfirm: {}, onCancel: {}, onOpenSettings: {},
            mode: mode,
            cachedLanguages: cachedLanguages,
            currentLanguageKey: currentLanguageKey,
            currentGranularity: currentGranularity
        )
    }

    // MARK: - First-enable unchanged

    @Test func firstEnableKeepsTodaysFrame() {
        let sheet = makeSheet()
        #expect(sheet.displayTitle == "Bilingual mode")
        #expect(sheet.resolvedCTALabel == BilingualSetupSheet.primaryCTALabel)
        #expect(sheet.ctaUsesAccentFill)
        #expect(sheet.contextStripText == nil)
        #expect(!sheet.showsCancelButton)
        #expect(!sheet.showsCachedBadge(forLanguageKey: "Chinese"))
        #expect(!sheet.showsCachedCaption)
        #expect(sheet.languageStripKind == nil)
        #expect(sheet.granularityStripKind == nil)
    }

    // MARK: - Edit frame

    @Test func editFrameTitleCancelAndContext() {
        let sheet = makeSheet(
            mode: .edit(bookTitle: "Pride and Prejudice"),
            currentLanguageKey: "Chinese", currentGranularity: .paragraph)
        #expect(sheet.displayTitle == "Translation settings")
        #expect(sheet.showsCancelButton)
        #expect(sheet.contextStripText
            == "Bilingual mode is on \u{B7} Pride and Prejudice")
    }

    @Test func cleanEditShowsQuietDone() {
        let sheet = makeSheet(
            mode: .edit(bookTitle: "B"),
            state: BilingualSetupSheetState(languageKey: "Chinese", granularity: .paragraph),
            currentLanguageKey: "Chinese", currentGranularity: .paragraph)
        #expect(sheet.resolvedCTALabel == "Done")
        #expect(!sheet.ctaUsesAccentFill)
        #expect(sheet.languageStripKind == nil)
    }

    @Test func newLanguagePickShowsAccentApplyAndLanguageStrip() {
        let sheet = makeSheet(
            mode: .edit(bookTitle: "B"),
            state: BilingualSetupSheetState(languageKey: "Japanese", granularity: .paragraph),
            cachedLanguages: ["Chinese"],
            currentLanguageKey: "Chinese", currentGranularity: .paragraph)
        #expect(sheet.resolvedCTALabel == "Apply \u{B7} re-translate as you read")
        #expect(sheet.ctaUsesAccentFill)
        #expect(sheet.languageStripKind == .newLanguage)
        #expect(sheet.granularityStripKind == nil)
    }

    @Test func cachedLanguagePickShowsSwitchCTA() {
        let sheet = makeSheet(
            mode: .edit(bookTitle: "B"),
            state: BilingualSetupSheetState(languageKey: "French", granularity: .paragraph),
            cachedLanguages: ["Chinese", "French"],
            currentLanguageKey: "Chinese", currentGranularity: .paragraph)
        #expect(sheet.resolvedCTALabel == "Switch to French")
        #expect(sheet.languageStripKind == .cachedLanguage)
    }

    @Test func granularityChangeShowsGranularityStrip() {
        let sheet = makeSheet(
            mode: .edit(bookTitle: "B"),
            state: BilingualSetupSheetState(languageKey: "Chinese", granularity: .sentence),
            cachedLanguages: ["Chinese"],
            currentLanguageKey: "Chinese", currentGranularity: .paragraph)
        #expect(sheet.resolvedCTALabel == "Apply \u{B7} re-translate as you read")
        #expect(sheet.languageStripKind == nil)
        #expect(sheet.granularityStripKind == .granularityOnly)
    }

    // MARK: - Badges + caption

    @Test func badgesRenderForCachedLanguagesInEditOnly() {
        let sheet = makeSheet(
            mode: .edit(bookTitle: "B"),
            cachedLanguages: ["Chinese", "French"],
            currentLanguageKey: "Chinese", currentGranularity: .paragraph)
        #expect(sheet.showsCachedBadge(forLanguageKey: "Chinese"))
        #expect(sheet.showsCachedBadge(forLanguageKey: "French"))
        #expect(!sheet.showsCachedBadge(forLanguageKey: "Japanese"))
        #expect(sheet.showsCachedCaption)
    }

    @Test func captionHiddenWithNoCachedLanguages() {
        let sheet = makeSheet(
            mode: .edit(bookTitle: "B"),
            currentLanguageKey: "Chinese", currentGranularity: .paragraph)
        #expect(!sheet.showsCachedCaption)
    }

    // MARK: - Cost strip copy pins

    @Test func costStripCopy() {
        #expect(BilingualCostStrip.head(for: .newLanguage, languageDisplay: "Japanese")
            == "Japanese is new for this book")
        #expect(BilingualCostStrip.sub(for: .newLanguage)
            == "Pages re-translate as you read.")
        #expect(BilingualCostStrip.head(for: .cachedLanguage, languageDisplay: "French")
            == "Cached \u{2014} switches instantly")
        #expect(BilingualCostStrip.sub(for: .cachedLanguage)
            == "This language was translated before. Nothing is re-paid.")
        #expect(BilingualCostStrip.head(for: .granularityOnly, languageDisplay: "x")
            == "Granularity change re-translates")
        #expect(BilingualCostStrip.sub(for: .granularityOnly)
            == "Cached rows are per-granularity \u{B7} starts from this page.")
    }
}
