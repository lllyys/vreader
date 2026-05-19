import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader
@Suite("ReaderSettingsStore") @MainActor struct ReaderSettingsStoreTests {
    private func makeStore() -> ReaderSettingsStore {
        ReaderSettingsStore(defaults: UserDefaults(suiteName: "RSS-\(UUID().uuidString)")!)
    }
    // Feature #60 WI-11: `ReaderSettingsStore.theme` is `ReaderThemeV2`.
    // The default theme is `.paper` (was the legacy `ReaderTheme.light`,
    // which the migration alias maps to `.paper`).
    @Test func defaultTheme() { #expect(makeStore().theme == .paper) }
    @Test func defaultTypography() { let s = makeStore(); #expect(s.typography.fontSize == 18) }
    #if canImport(UIKit)
    @Test func uiFontForSystemFamily() { #expect(makeStore().uiFont.pointSize == 18) }
    @Test func uiBackgroundColorMatchesTheme() {
        var s = makeStore(); s.theme = .dark; var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        s.uiBackgroundColor.getRed(&r, green: &g, blue: &b, alpha: &a); #expect(r < 0.2)
    }
    @Test func lineSpacingPoints() {
        var s = makeStore(); s.typography.fontSize = 20; s.typography.lineSpacing = 1.6
        #expect(abs(s.lineSpacingPoints - 12.0) < 0.01)
    }
    @Test func mdRenderConfigReflectsSettings() {
        var s = makeStore(); s.typography.fontSize = 22; s.typography.lineSpacing = 1.6
        #expect(s.mdRenderConfig.fontSize == 22)
    }
    @Test func txtViewConfigReflectsSettings() {
        var s = makeStore(); s.typography.fontSize = 24; #expect(s.txtViewConfig.fontSize == 24)
    }
    @Test func cjkLetterSpacingWhenEnabled() { var s = makeStore(); s.typography.cjkSpacing = true; #expect(s.cjkLetterSpacing > 0) }
    @Test func cjkLetterSpacingWhenDisabled() { var s = makeStore(); s.typography.cjkSpacing = false; #expect(s.cjkLetterSpacing == 0) }
    #endif
    @Test func themeChangeUpdatesColors() {
        var s = makeStore(); s.theme = .paper
        #if canImport(UIKit)
        let l = s.uiBackgroundColor; s.theme = .dark; #expect(l != s.uiBackgroundColor)
        #endif
    }
    @Test func invalidThemeRawValueFallsBackToDefault() {
        let n = "RSS-c-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        d.set("neon", forKey: ReaderSettingsStore.themeKey)
        #expect(ReaderSettingsStore(defaults: d).theme == .paper); d.removePersistentDomain(forName: n)
    }
    // Feature #60 WI-11: existing users have `readerTheme` persisted as
    // a legacy `ReaderTheme` rawValue. The store must decode those.
    @Test func legacyLightRawValueDecodesToPaper() {
        let n = "RSS-leg-l-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        d.set("light", forKey: ReaderSettingsStore.themeKey)
        #expect(ReaderSettingsStore(defaults: d).theme == .paper); d.removePersistentDomain(forName: n)
    }
    @Test func legacySepiaRawValueDecodesToSepia() {
        let n = "RSS-leg-s-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        d.set("sepia", forKey: ReaderSettingsStore.themeKey)
        #expect(ReaderSettingsStore(defaults: d).theme == .sepia); d.removePersistentDomain(forName: n)
    }
    @Test func legacyDarkRawValueDecodesToDark() {
        let n = "RSS-leg-d-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        d.set("dark", forKey: ReaderSettingsStore.themeKey)
        #expect(ReaderSettingsStore(defaults: d).theme == .dark); d.removePersistentDomain(forName: n)
    }
    // Feature #60 WI-11: all 5 ReaderThemeV2 cases round-trip through
    // UserDefaults — OLED and Photo are now user-selectable.
    @Test func allFiveThemesRoundTripThroughUserDefaults() {
        for theme in ReaderThemeV2.allCases {
            let n = "RSS-5-\(theme.rawValue)-\(UUID().uuidString)"
            let d = UserDefaults(suiteName: n)!
            var s1 = ReaderSettingsStore(defaults: d); s1.theme = theme
            #expect(d.string(forKey: ReaderSettingsStore.themeKey) == theme.rawValue)
            #expect(ReaderSettingsStore(defaults: d).theme == theme,
                    "theme \(theme.rawValue) must survive a persistence round-trip")
            d.removePersistentDomain(forName: n)
        }
    }
    @Test func settingsStore_defaultsToDisabled() { #expect(makeStore().useCustomBackground == false) }
    @Test func settingsStore_defaultBackgroundOpacity() { #expect(abs(makeStore().backgroundOpacity - 0.15) < 0.001) }
    @Test func settingsStore_persistsBackgroundEnabled() {
        let n = "RSS-bg-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        var s1 = ReaderSettingsStore(defaults: d); s1.useCustomBackground = true
        #expect(ReaderSettingsStore(defaults: d).useCustomBackground == true); d.removePersistentDomain(forName: n)
    }
    @Test func settingsStore_persistsBackgroundOpacity() {
        let n = "RSS-bo-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        var s1 = ReaderSettingsStore(defaults: d); s1.backgroundOpacity = 0.5
        #expect(abs(ReaderSettingsStore(defaults: d).backgroundOpacity - 0.5) < 0.001); d.removePersistentDomain(forName: n)
    }
    @Test func settingsStore_clampsBackgroundOpacity() {
        var s = makeStore(); s.backgroundOpacity = -0.5; #expect(s.backgroundOpacity >= 0.0)
        s.backgroundOpacity = 1.5; #expect(s.backgroundOpacity <= 1.0)
    }

    // MARK: - Bug #222: autoPageTurnInterval must not recurse

    /// Bug #222 / GH #882: a post-init assignment of an already in-range value
    /// to `autoPageTurnInterval`. Pre-fix the property was a stored property
    /// whose `didSet` re-assigned itself to clamp — under `@Observable` that
    /// re-enters the synthesized setter unboundedly → stack overflow. This
    /// test simply mutating the property post-init reproduces the crash
    /// (post-init because Swift suppresses observers during `init`). Post-fix
    /// the property is a `get`/`set` computed pair that clamps without
    /// observer re-entry, so the assignment completes.
    @Test func settingsStore_autoPageTurnInterval_inRangeAssignmentDoesNotRecurse() {
        var s = makeStore()
        s.autoPageTurnInterval = 10.0
        #expect(s.autoPageTurnInterval == 10.0)
        // A same-value re-assignment is the tightest recursion repro — pre-fix
        // `max(1,min(60,10)) == 10` still re-fired the setter forever.
        s.autoPageTurnInterval = 10.0
        #expect(s.autoPageTurnInterval == 10.0)
    }

    @Test func settingsStore_clampsAutoPageTurnInterval() {
        var s = makeStore()
        s.autoPageTurnInterval = 0.5
        #expect(s.autoPageTurnInterval == 1.0)
        s.autoPageTurnInterval = 999.0
        #expect(s.autoPageTurnInterval == 60.0)
    }

    @Test func settingsStore_persistsAutoPageTurnInterval() {
        let n = "RSS-apti-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        var s1 = ReaderSettingsStore(defaults: d); s1.autoPageTurnInterval = 12.0
        #expect(ReaderSettingsStore(defaults: d).autoPageTurnInterval == 12.0)
        d.removePersistentDomain(forName: n)
    }
    @Test func persistenceRoundTrip() {
        let n = "RSS-p-\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!
        var s1 = ReaderSettingsStore(defaults: d); s1.theme = .sepia; s1.typography.fontSize = 24
        let s2 = ReaderSettingsStore(defaults: d); #expect(s2.theme == .sepia); #expect(s2.typography.fontSize == 24)
        d.removePersistentDomain(forName: n)
    }

    // MARK: - Bug #147: reconcileFromDefaults

    @Test @MainActor func reconcileFromDefaults_resetsThemeFromGlobalAfterPerBookDisable() {
        // Bug #147 scenario:
        // 1. User has global theme=dark in UserDefaults.
        // 2. Per-book override sets theme=light during the active session.
        //    Mimic this with applyResolvedSettings, which suppresses
        //    persistence (defaults stay dark, live store goes light).
        // 3. User disables per-book; file deleted, live store still light.
        // 4. reconcileFromDefaults pulls back the global dark.
        let n = "RSS-rec-theme-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        d.set("dark", forKey: ReaderSettingsStore.themeKey)
        let s = ReaderSettingsStore(defaults: d)
        #expect(s.theme == .dark)

        // Per-book-active session mutates live store via the resolver
        // (which suppresses persistence so defaults stays at "dark").
        // Feature #60 WI-11: a per-book override carrying the LEGACY
        // themeName "light" still resolves — it migrates to `.paper`.
        let resolvedAsLight = ResolvedSettings(
            fontSize: s.typography.fontSize, fontName: s.typography.fontFamily.rawValue,
            lineSpacing: s.typography.lineSpacing,
            letterSpacing: s.typography.cjkSpacing ? s.typography.fontSize * 0.05 : 0,
            themeName: "light"
        )
        s.applyResolvedSettings(resolvedAsLight)
        #expect(s.theme == .paper, "legacy per-book themeName 'light' migrates to .paper")

        // Per-book disable: file deleted, then reconcile.
        s.reconcileFromDefaults()
        #expect(s.theme == .dark, "reconcile should mirror the global default back")
        d.removePersistentDomain(forName: n)
    }

    @Test func reconcileFromDefaults_isIdempotent() {
        // No external writes: reconcile should be a no-op (no value
        // changes, no persistence churn).
        let s = makeStore()
        let snapshotTheme = s.theme
        let snapshotFontSize = s.typography.fontSize
        s.reconcileFromDefaults()
        #expect(s.theme == snapshotTheme)
        #expect(s.typography.fontSize == snapshotFontSize)
    }

    @Test @MainActor func reconcileFromDefaults_resetsToDefaultTypographyWhenDefaultsHasNoEntry() {
        // Codex round-1 finding: the previous reconcile only assigned
        // typography when defaults had a decodable entry, leaving live
        // per-book typography in place when no global entry existed.
        // After the round-2 refactor, reconcile resets to TypographySettings()
        // (the init's fallback) when defaults has no `readerTypography`.
        let n = "RSS-rec-empty-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        // Defaults has nothing — fresh suite.
        let s = ReaderSettingsStore(defaults: d)
        let defaultTypography = s.typography  // = TypographySettings()

        // Simulate per-book-active: set typography to a different size.
        let resolved = ResolvedSettings(
            fontSize: defaultTypography.fontSize + 8,
            fontName: defaultTypography.fontFamily.rawValue,
            lineSpacing: defaultTypography.lineSpacing,
            letterSpacing: 0,
            themeName: s.theme.rawValue
        )
        s.applyResolvedSettings(resolved)
        #expect(s.typography.fontSize == defaultTypography.fontSize + 8)

        // Reconcile while defaults still has no `readerTypography` entry.
        // Must reset to TypographySettings() — NOT keep the live value.
        s.reconcileFromDefaults()
        #expect(s.typography == defaultTypography,
                "reconcile must reset typography to default when defaults has no entry")
        d.removePersistentDomain(forName: n)
    }

    @Test @MainActor func reconcileFromDefaults_resetsFontSizeFromGlobalAfterPerBookDisable() {
        let n = "RSS-rec-font-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        let s = ReaderSettingsStore(defaults: d)
        let globalSize = s.typography.fontSize

        // Per-book-active: applyResolvedSettings to a different size
        // (suppresses persistence — defaults stays at globalSize).
        let resolved = ResolvedSettings(
            fontSize: globalSize + 6, fontName: s.typography.fontFamily.rawValue,
            lineSpacing: s.typography.lineSpacing,
            letterSpacing: 0,
            themeName: s.theme.rawValue
        )
        s.applyResolvedSettings(resolved)
        #expect(s.typography.fontSize == globalSize + 6)

        // Per-book disable + reconcile: store back to global.
        s.reconcileFromDefaults()
        #expect(s.typography.fontSize == globalSize, "reconcile should reset font size to global")
        d.removePersistentDomain(forName: n)
    }
}
