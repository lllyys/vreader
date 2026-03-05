// Purpose: Tests for ReaderSettingsStore — computed UIKit values, settings bridging.

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("ReaderSettingsStore")
@MainActor
struct ReaderSettingsStoreTests {

    /// Creates a fresh store backed by an ephemeral UserDefaults suite.
    private func makeStore() -> ReaderSettingsStore {
        let suiteName = "ReaderSettingsStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults(suiteName:) should not fail for non-nil suite name")
        }
        return ReaderSettingsStore(defaults: defaults)
    }

    // MARK: - Default Values

    @Test func defaultTheme() {
        let store = makeStore()
        #expect(store.theme == .light)
    }

    @Test func defaultTypography() {
        let store = makeStore()
        #expect(store.typography.fontSize == 18)
        #expect(store.typography.lineSpacing == 1.4)
        #expect(store.typography.fontFamily == .system)
        #expect(store.typography.cjkSpacing == false)
    }

    // MARK: - Computed UIKit Values

    #if canImport(UIKit)
    @Test func uiFontForSystemFamily() {
        let store = makeStore()
        let font = store.uiFont
        #expect(font.pointSize == 18)
    }

    @Test func uiFontForSerifFamily() {
        var store = makeStore()
        store.typography.fontFamily = .serif
        let font = store.uiFont
        #expect(font.pointSize == 18)
        // Serif font should contain "Georgia" or similar
        let name = font.fontName.lowercased()
        let isSerif = name.contains("georgia") || name.contains("times") || name.contains("serif")
        #expect(isSerif)
    }

    @Test func uiFontForMonospaceFamily() {
        var store = makeStore()
        store.typography.fontFamily = .monospace
        let font = store.uiFont
        #expect(font.pointSize == 18)
    }

    @Test func uiBackgroundColorMatchesTheme() {
        var store = makeStore()
        store.theme = .dark
        let bg = store.uiBackgroundColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        bg.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r < 0.2)
    }

    @Test func uiTextColorMatchesTheme() {
        var store = makeStore()
        store.theme = .light
        let text = store.uiTextColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        text.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r < 0.2)
    }

    @Test func lineSpacingPoints() {
        var store = makeStore()
        store.typography.fontSize = 20
        store.typography.lineSpacing = 1.6
        // lineSpacingPoints = fontSize * (lineSpacing - 1.0)
        let expected = 20.0 * (1.6 - 1.0)
        #expect(abs(store.lineSpacingPoints - expected) < 0.01)
    }
    #endif

    // MARK: - MDRenderConfig Bridge

    #if canImport(UIKit)
    @Test func mdRenderConfigReflectsSettings() {
        var store = makeStore()
        store.theme = .sepia
        store.typography.fontSize = 22
        store.typography.lineSpacing = 1.6

        let config = store.mdRenderConfig
        #expect(config.fontSize == 22)
        // lineSpacing in MDRenderConfig is absolute points, not multiplier
        let expectedLineSpacing = 22.0 * (1.6 - 1.0)
        #expect(abs(config.lineSpacing - expectedLineSpacing) < 0.01)
        #expect(config.textColor == store.uiTextColor)
    }
    #endif

    // MARK: - TXTViewConfig Bridge

    #if canImport(UIKit)
    @Test func txtViewConfigReflectsSettings() {
        var store = makeStore()
        store.typography.fontSize = 24
        store.typography.lineSpacing = 1.5

        let config = store.txtViewConfig
        #expect(config.fontSize == 24)
        let expectedLineSpacing = 24.0 * (1.5 - 1.0)
        #expect(abs(config.lineSpacing - expectedLineSpacing) < 0.01)
    }
    #endif

    // MARK: - CJK Letter Spacing

    #if canImport(UIKit)
    @Test func cjkLetterSpacingWhenEnabled() {
        var store = makeStore()
        store.typography.cjkSpacing = true
        #expect(store.cjkLetterSpacing > 0)
    }

    @Test func cjkLetterSpacingWhenDisabled() {
        var store = makeStore()
        store.typography.cjkSpacing = false
        #expect(store.cjkLetterSpacing == 0)
    }
    #endif

    // MARK: - Theme Change

    @Test func themeChangeUpdatesColors() {
        var store = makeStore()
        store.theme = .light
        #if canImport(UIKit)
        let lightBg = store.uiBackgroundColor
        #endif

        store.theme = .dark
        #if canImport(UIKit)
        let darkBg = store.uiBackgroundColor
        #expect(lightBg != darkBg)
        #endif
    }

    // MARK: - Corrupt Payload Recovery

    @Test func invalidThemeRawValueFallsBackToDefault() {
        let suiteName = "ReaderSettingsStoreTests-corrupt-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("UserDefaults(suiteName:) returned nil")
            return
        }
        defaults.set("neon", forKey: ReaderSettingsStore.themeKey)
        let store = ReaderSettingsStore(defaults: defaults)
        #expect(store.theme == .light)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func malformedTypographyJSONFallsBackToDefaults() {
        let suiteName = "ReaderSettingsStoreTests-corrupt2-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("UserDefaults(suiteName:) returned nil")
            return
        }
        defaults.set(Data("not json".utf8), forKey: ReaderSettingsStore.typographyKey)
        let store = ReaderSettingsStore(defaults: defaults)
        #expect(store.typography.fontSize == 18)
        #expect(store.typography.fontFamily == .system)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Persistence Round-Trip

    @Test func persistenceRoundTrip() {
        let suiteName = "ReaderSettingsStoreTests-persist-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("UserDefaults(suiteName:) returned nil")
            return
        }

        // Write settings
        var store1 = ReaderSettingsStore(defaults: defaults)
        store1.theme = .sepia
        store1.typography.fontSize = 24
        store1.typography.lineSpacing = 1.8
        store1.typography.fontFamily = .serif
        store1.typography.cjkSpacing = true

        // Create a new store from the same defaults
        let store2 = ReaderSettingsStore(defaults: defaults)
        #expect(store2.theme == .sepia)
        #expect(store2.typography.fontSize == 24)
        #expect(store2.typography.lineSpacing == 1.8)
        #expect(store2.typography.fontFamily == .serif)
        #expect(store2.typography.cjkSpacing == true)

        // Cleanup
        defaults.removePersistentDomain(forName: suiteName)
    }
}
