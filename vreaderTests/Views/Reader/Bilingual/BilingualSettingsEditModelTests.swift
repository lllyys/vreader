// Purpose: Tests for BilingualSettingsEditModel — feature #99 WI-1's pure
// edit-mode decision seam: dirty-kind resolution (language change dominates,
// cache decides new-vs-cached), CTA labels + accent, the two cost-strip
// render slots, and the re-translate banner rule.

import Testing
@testable import vreader

@Suite("BilingualSettingsEditModel (feature #99)")
struct BilingualSettingsEditModelTests {

    private func draft(
        _ lang: String, _ gran: TranslationGranularity
    ) -> BilingualSetupSheetState {
        BilingualSetupSheetState(languageKey: lang, granularity: gran)
    }

    // MARK: - Dirty kind

    @Test func noChangesIsClean() {
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: "Chinese", currentGranularity: .paragraph,
            draft: draft("Chinese", .paragraph), cachedLanguages: ["Chinese"])
        #expect(dirty == .none)
    }

    @Test func newLanguageNotInCache() {
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: "Chinese", currentGranularity: .paragraph,
            draft: draft("Japanese", .paragraph), cachedLanguages: ["Chinese"])
        #expect(dirty == .newLanguage)
    }

    @Test func changedLanguageWithCacheIsCachedSwitch() {
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: "Chinese", currentGranularity: .paragraph,
            draft: draft("French", .paragraph),
            cachedLanguages: ["Chinese", "French"])
        #expect(dirty == .cachedLanguage)
    }

    @Test func cachedLanguagePlusGranularityChangeIsNewLanguage() {
        // Re-translation is owed anyway — CTA "Apply · re-translate as you read".
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: "Chinese", currentGranularity: .paragraph,
            draft: draft("French", .sentence),
            cachedLanguages: ["Chinese", "French"])
        #expect(dirty == .newLanguage)
    }

    @Test func granularityOnlyChange() {
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: "Chinese", currentGranularity: .paragraph,
            draft: draft("Chinese", .sentence), cachedLanguages: ["Chinese"])
        #expect(dirty == .granularityOnly)
    }

    @Test func stalePersistedCurrentKeyDoesNotFakeDirty() {
        // Gate-4 r1 Medium: a persisted language key no longer in the
        // registry canonicalises to the registry default — an untouched
        // sheet (whose draft normalises the same way) must stay .none.
        let registryDefault = BilingualLanguage.all[0].key
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: "Klingon-Removed",
            currentGranularity: .paragraph,
            draft: draft(registryDefault, .paragraph),
            cachedLanguages: [])
        #expect(dirty == .none)
    }

    @Test func currentLanguageCacheStateIsIrrelevantWhenUnchanged() {
        // The selected language equalling the current one is .none even when
        // the cache has no rows for it yet (nothing to apply).
        let dirty = BilingualSettingsEditModel.dirtyKind(
            currentLanguage: "Chinese", currentGranularity: .paragraph,
            draft: draft("Chinese", .paragraph), cachedLanguages: [])
        #expect(dirty == .none)
    }

    // MARK: - CTA

    @Test(arguments: [
        (BilingualSettingsEditModel.DirtyKind.none, "Done"),
        (.cachedLanguage, "Switch to French"),
        (.newLanguage, "Apply \u{B7} re-translate as you read"),
        (.granularityOnly, "Apply \u{B7} re-translate as you read"),
    ] as [(BilingualSettingsEditModel.DirtyKind, String)])
    func ctaLabels(_ dirty: BilingualSettingsEditModel.DirtyKind, _ expected: String) {
        #expect(BilingualSettingsEditModel.ctaLabel(
            dirty: dirty, draftLanguageDisplay: "French") == expected)
    }

    @Test func ctaAccentOnlyWhenDirty() {
        #expect(BilingualSettingsEditModel.ctaIsAccent(dirty: .none) == false)
        #expect(BilingualSettingsEditModel.ctaIsAccent(dirty: .newLanguage))
        #expect(BilingualSettingsEditModel.ctaIsAccent(dirty: .cachedLanguage))
        #expect(BilingualSettingsEditModel.ctaIsAccent(dirty: .granularityOnly))
    }

    // MARK: - Strip slots (the jsx's two render positions)

    @Test func languageSlotShowsForLanguageKindsOnly() {
        #expect(BilingualSettingsEditModel.languageStripKind(dirty: .newLanguage) == .newLanguage)
        #expect(BilingualSettingsEditModel.languageStripKind(dirty: .cachedLanguage) == .cachedLanguage)
        #expect(BilingualSettingsEditModel.languageStripKind(dirty: .granularityOnly) == nil)
        #expect(BilingualSettingsEditModel.languageStripKind(dirty: .none) == nil)
    }

    @Test func granularitySlotShowsForGranularityOnly() {
        #expect(BilingualSettingsEditModel.granularityStripKind(dirty: .granularityOnly) == .granularityOnly)
        #expect(BilingualSettingsEditModel.granularityStripKind(dirty: .newLanguage) == nil)
        #expect(BilingualSettingsEditModel.granularityStripKind(dirty: .cachedLanguage) == nil)
        #expect(BilingualSettingsEditModel.granularityStripKind(dirty: .none) == nil)
    }

    // MARK: - Banner

    @Test func bannerOnlyForNewLanguage() {
        #expect(BilingualSettingsEditModel.shouldShowRetranslateBanner(dirty: .newLanguage))
        #expect(!BilingualSettingsEditModel.shouldShowRetranslateBanner(dirty: .cachedLanguage))
        #expect(!BilingualSettingsEditModel.shouldShowRetranslateBanner(dirty: .granularityOnly))
        #expect(!BilingualSettingsEditModel.shouldShowRetranslateBanner(dirty: .none))
    }
}
