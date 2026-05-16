// Purpose: Tests for PerBookSettings — per-book override storage, resolution logic,
// partial override inheritance, and filesystem persistence.

import Testing
import Foundation
@testable import vreader

@Suite("PerBookSettings")
struct PerBookSettingsTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerBookSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func cleanUp(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Default / No Settings

    @Test func perBookSettings_defaultsToNil() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let result = PerBookSettingsStore.settings(for: "epub:abc123:1024", baseURL: dir)
        #expect(result == nil)
    }

    // MARK: - Save and Restore

    @Test func perBookSettings_savesAndRestores() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let key = "epub:aabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb:5000"
        let override = PerBookSettingsOverride(
            fontSize: 24, fontName: "Georgia", lineSpacing: 1.8,
            letterSpacing: 0.05, themeName: "sepia", readingMode: "native"
        )
        try PerBookSettingsStore.save(override, for: key, baseURL: dir)
        let restored = PerBookSettingsStore.settings(for: key, baseURL: dir)
        #expect(restored != nil)
        #expect(restored == override)
    }

    // MARK: - Different Books Independent

    @Test func perBookSettings_differentBooks_independent() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let keyA = "epub:aaaa000000000000000000000000000000000000000000000000000000000000:100"
        let keyB = "txt:bbbb000000000000000000000000000000000000000000000000000000000000:200"
        let overrideA = PerBookSettingsOverride(fontSize: 20)
        let overrideB = PerBookSettingsOverride(fontSize: 28, themeName: "dark")
        try PerBookSettingsStore.save(overrideA, for: keyA, baseURL: dir)
        try PerBookSettingsStore.save(overrideB, for: keyB, baseURL: dir)
        let restoredA = PerBookSettingsStore.settings(for: keyA, baseURL: dir)
        let restoredB = PerBookSettingsStore.settings(for: keyB, baseURL: dir)
        #expect(restoredA?.fontSize == 20)
        #expect(restoredA?.themeName == nil)
        #expect(restoredB?.fontSize == 28)
        #expect(restoredB?.themeName == "dark")
    }

    // MARK: - Delete Removes

    @Test func perBookSettings_deleteRemoves() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let key = "epub:cccc000000000000000000000000000000000000000000000000000000000000:300"
        let override = PerBookSettingsOverride(fontSize: 22)
        try PerBookSettingsStore.save(override, for: key, baseURL: dir)
        #expect(PerBookSettingsStore.settings(for: key, baseURL: dir) != nil)
        PerBookSettingsStore.delete(for: key, baseURL: dir)
        #expect(PerBookSettingsStore.settings(for: key, baseURL: dir) == nil)
    }

    // MARK: - Codable Round-Trip

    @Test func perBookSettings_codable_roundTrip() throws {
        let original = PerBookSettingsOverride(
            fontSize: 26, fontName: "Menlo", lineSpacing: 1.6,
            letterSpacing: 0.03, themeName: "dark", readingMode: "unified"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PerBookSettingsOverride.self, from: data)
        #expect(decoded == original)
    }

    @Test func perBookSettings_codable_roundTrip_allNils() throws {
        let original = PerBookSettingsOverride()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PerBookSettingsOverride.self, from: data)
        #expect(decoded == original)
        #expect(decoded.fontSize == nil)
        #expect(decoded.fontName == nil)
    }

    // MARK: - Resolution Logic

    @Test @MainActor func resolvedSettings_usesPerBook_whenSet() {
        let global = makeGlobalStore()
        global.typography.fontSize = 18
        global.theme = .paper
        let perBook = PerBookSettingsOverride(fontSize: 26, themeName: "dark")
        let resolved = PerBookSettingsStore.resolve(perBook: perBook, global: global)
        #expect(resolved.fontSize == 26)
        #expect(resolved.themeName == "dark")
    }

    @Test @MainActor func resolvedSettings_usesGlobal_whenNoPerBook() {
        let global = makeGlobalStore()
        global.typography.fontSize = 20
        global.theme = .sepia
        global.typography.lineSpacing = 1.6
        global.typography.fontFamily = .serif
        let resolved = PerBookSettingsStore.resolve(perBook: nil, global: global)
        #expect(resolved.fontSize == 20)
        #expect(resolved.themeName == "sepia")
        #expect(resolved.lineSpacing == 1.6)
        #expect(resolved.fontName == "serif")
    }

    @Test @MainActor func perBookSettings_partialOverride() {
        let global = makeGlobalStore()
        global.typography.fontSize = 18
        global.typography.lineSpacing = 1.4
        global.typography.fontFamily = .system
        global.theme = .paper
        let perBook = PerBookSettingsOverride(fontSize: 28)
        let resolved = PerBookSettingsStore.resolve(perBook: perBook, global: global)
        #expect(resolved.fontSize == 28)
        #expect(resolved.lineSpacing == 1.4)
        #expect(resolved.fontName == "system")
        // Feature #60 WI-11: `global.theme` is `ReaderThemeV2`; its
        // rawValue for `.paper` is "paper".
        #expect(resolved.themeName == "paper")
    }

    @Test @MainActor func resolvedSettings_allFieldsOverridden() {
        let global = makeGlobalStore()
        global.typography.fontSize = 18
        global.typography.lineSpacing = 1.4
        global.typography.fontFamily = .system
        global.theme = .paper
        global.readingMode = .native
        let perBook = PerBookSettingsOverride(
            fontSize: 30, fontName: "serif", lineSpacing: 2.0,
            letterSpacing: 0.1, themeName: "dark", readingMode: "unified"
        )
        let resolved = PerBookSettingsStore.resolve(perBook: perBook, global: global)
        #expect(resolved.fontSize == 30)
        #expect(resolved.fontName == "serif")
        #expect(resolved.lineSpacing == 2.0)
        #expect(resolved.letterSpacing == 0.1)
        #expect(resolved.themeName == "dark")
        #expect(resolved.readingMode == "unified")
    }

    // MARK: - Edge Cases

    @Test func perBookSettings_emptyFingerprintKey() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let override = PerBookSettingsOverride(fontSize: 14)
        try PerBookSettingsStore.save(override, for: "", baseURL: dir)
        let restored = PerBookSettingsStore.settings(for: "", baseURL: dir)
        #expect(restored?.fontSize == 14)
    }

    @Test func perBookSettings_deleteNonexistent_noError() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        PerBookSettingsStore.delete(for: "nonexistent-key", baseURL: dir)
    }

    @Test func perBookSettings_directoryCreatedOnSave() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerBookSettingsTests-autocreate-\(UUID().uuidString)")
        defer { cleanUp(dir) }
        let key = "txt:dddd000000000000000000000000000000000000000000000000000000000000:400"
        let override = PerBookSettingsOverride(fontSize: 16)
        try PerBookSettingsStore.save(override, for: key, baseURL: dir)
        let restored = PerBookSettingsStore.settings(for: key, baseURL: dir)
        #expect(restored?.fontSize == 16)
    }

    @Test func perBookSettings_specialCharsInKey() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let key = "epub:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef:999"
        let override = PerBookSettingsOverride(themeName: "sepia")
        try PerBookSettingsStore.save(override, for: key, baseURL: dir)
        let restored = PerBookSettingsStore.settings(for: key, baseURL: dir)
        #expect(restored?.themeName == "sepia")
    }

    @Test func perBookSettings_overwriteExisting() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let key = "epub:eeee000000000000000000000000000000000000000000000000000000000000:500"
        let v1 = PerBookSettingsOverride(fontSize: 18)
        try PerBookSettingsStore.save(v1, for: key, baseURL: dir)
        let v2 = PerBookSettingsOverride(fontSize: 24, themeName: "dark")
        try PerBookSettingsStore.save(v2, for: key, baseURL: dir)
        let restored = PerBookSettingsStore.settings(for: key, baseURL: dir)
        #expect(restored?.fontSize == 24)
        #expect(restored?.themeName == "dark")
    }

    // MARK: - Apply Resolved Settings (Bug #84)

    @Test @MainActor func applyResolvedSettings_overridesStoreFields() {
        let store = makeGlobalStore()
        store.typography.fontSize = 18
        store.typography.lineSpacing = 1.4
        store.typography.fontFamily = .system
        store.theme = .paper
        store.readingMode = .native

        let resolved = ResolvedSettings(
            fontSize: 26, fontName: "serif", lineSpacing: 2.0,
            letterSpacing: 0.1, themeName: "dark", readingMode: "unified"
        )
        store.applyResolvedSettings(resolved)

        #expect(store.typography.fontSize == 26)
        #expect(store.typography.fontFamily == .serif)
        #expect(store.typography.lineSpacing == 2.0)
        #expect(store.theme == .dark)
        #expect(store.readingMode == .unified)
    }

    @Test @MainActor func applyResolvedSettings_doesNotPollutedUserDefaults() {
        let suiteName = "PerBookApplyPollutionTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ReaderSettingsStore(defaults: defaults)
        store.typography.fontSize = 18
        store.theme = .paper
        // Explicit set: ReaderSettingsStore only writes a key to UserDefaults
        // when the property is explicitly assigned. The defaults assertion
        // below ("readingMode is 'native' after apply") only makes sense if
        // the test first writes "native" — otherwise the lookup returns nil
        // and the assertion is meaningless.
        store.readingMode = .native

        // Verify global defaults are set to 18/light
        #expect(defaults.double(forKey: ReaderSettingsStore.typographyKey) != 0 || defaults.data(forKey: ReaderSettingsStore.typographyKey) != nil)

        let resolved = ResolvedSettings(
            fontSize: 30, fontName: "serif", lineSpacing: 2.0,
            letterSpacing: 0, themeName: "dark", readingMode: "unified"
        )
        store.applyResolvedSettings(resolved)

        // Store should have the per-book values
        #expect(store.typography.fontSize == 30)
        #expect(store.theme == .dark)

        // But UserDefaults should still have the original global values.
        // Feature #60 WI-11: the global theme was set to `.paper`
        // (ReaderThemeV2), so the persisted rawValue is "paper".
        #expect(defaults.string(forKey: ReaderSettingsStore.themeKey) == "paper")
        #expect(defaults.string(forKey: ReaderSettingsStore.readingModeKey) == "native")
    }

    @Test @MainActor func applyResolvedSettings_noopWhenAlreadyMatching() {
        let store = makeGlobalStore()
        store.typography.fontSize = 20
        store.theme = .sepia
        store.readingMode = .native

        let resolved = ResolvedSettings(
            fontSize: 20, fontName: "system", lineSpacing: store.typography.lineSpacing,
            letterSpacing: 0, themeName: "sepia", readingMode: "native"
        )
        store.applyResolvedSettings(resolved)

        #expect(store.typography.fontSize == 20)
        #expect(store.theme == .sepia)
    }

    // MARK: - Feature #60 WI-11: per-book themeName round-trip

    /// A per-book `themeName` carrying any of the 5 `ReaderThemeV2`
    /// rawValues — including OLED and Photo — must apply onto the
    /// store. WI-11 makes those themes user-selectable, so a per-book
    /// override can legitimately carry them.
    @Test @MainActor func applyResolvedSettings_allFiveV2Themes() {
        for theme in ReaderThemeV2.allCases {
            let store = makeGlobalStore()
            store.theme = .paper
            let resolved = ResolvedSettings(
                fontSize: store.typography.fontSize,
                fontName: store.typography.fontFamily.rawValue,
                lineSpacing: store.typography.lineSpacing,
                letterSpacing: 0,
                themeName: theme.rawValue, readingMode: store.readingMode.rawValue
            )
            store.applyResolvedSettings(resolved)
            #expect(store.theme == theme,
                    "per-book themeName '\(theme.rawValue)' must apply onto the store")
        }
    }

    /// A per-book override written before WI-11 carries a legacy
    /// `ReaderTheme` rawValue ("light" / "sepia" / "dark"). Resolving
    /// it must migrate "light" → `.paper` and preserve sepia / dark.
    @Test @MainActor func applyResolvedSettings_legacyThemeNamesMigrate() {
        let cases: [(legacy: String, expected: ReaderThemeV2)] = [
            ("light", .paper), ("sepia", .sepia), ("dark", .dark),
        ]
        for c in cases {
            let store = makeGlobalStore()
            store.theme = .oled  // start somewhere distinct
            let resolved = ResolvedSettings(
                fontSize: store.typography.fontSize,
                fontName: store.typography.fontFamily.rawValue,
                lineSpacing: store.typography.lineSpacing,
                letterSpacing: 0,
                themeName: c.legacy, readingMode: store.readingMode.rawValue
            )
            store.applyResolvedSettings(resolved)
            #expect(store.theme == c.expected,
                    "legacy per-book themeName '\(c.legacy)' must migrate to \(c.expected.rawValue)")
        }
    }

    /// An unknown / corrupt per-book `themeName` leaves the store's
    /// current theme untouched — `applyResolvedSettings` only assigns
    /// on a confident decode (no silent reset to default).
    @Test @MainActor func applyResolvedSettings_unknownThemeName_leavesThemeUntouched() {
        let store = makeGlobalStore()
        store.theme = .dark
        let resolved = ResolvedSettings(
            fontSize: store.typography.fontSize,
            fontName: store.typography.fontFamily.rawValue,
            lineSpacing: store.typography.lineSpacing,
            letterSpacing: 0,
            themeName: "chartreuse", readingMode: store.readingMode.rawValue
        )
        store.applyResolvedSettings(resolved)
        #expect(store.theme == .dark,
                "an unknown per-book themeName must not clobber the live theme")
    }

    /// End-to-end: save a per-book override carrying a V2-only theme
    /// (Photo), read it back, resolve it onto a global store.
    @Test @MainActor func perBookSettings_photoTheme_savesResolvesEndToEnd() throws {
        let dir = try makeTempDir()
        defer { cleanUp(dir) }
        let key = "epub:ffff000000000000000000000000000000000000000000000000000000000000:777"
        let override = PerBookSettingsOverride(themeName: ReaderThemeV2.photo.rawValue)
        try PerBookSettingsStore.save(override, for: key, baseURL: dir)
        let restored = try #require(PerBookSettingsStore.settings(for: key, baseURL: dir))
        #expect(restored.themeName == "photo")

        let global = makeGlobalStore()
        global.theme = .paper
        let resolved = PerBookSettingsStore.resolve(perBook: restored, global: global)
        #expect(resolved.themeName == "photo")
        global.applyResolvedSettings(resolved)
        #expect(global.theme == .photo)
    }

    // MARK: - Helpers

    @MainActor
    private func makeGlobalStore() -> ReaderSettingsStore {
        let suiteName = "PerBookSettingsTests-global-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail")
        }
        return ReaderSettingsStore(defaults: defaults)
    }
}
