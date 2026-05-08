// Purpose: Tests for `TestSeeder.clearKnownPreferences(in:)` — bug #152
// (GH #426). Verifies that the explicitly-listed UserDefaults keys
// are removed when the helper is invoked, and that unrelated keys
// in the same store are left intact.

import Testing
import Foundation
@testable import vreader

@Suite("TestSeeder.clearKnownPreferences")
struct TestSeederPreferencesTests {

    /// A purpose-built `UserDefaults` suite that doesn't touch the
    /// host's real preferences.
    private func makeSuite(_ name: String = "vreader.tests.\(UUID().uuidString)") -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        // Defensive: a previous run might have left state if the
        // suite name collided. Wipe before populating.
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        return defaults
    }

    @Test func clearsOPDSSavedCatalogs() {
        let defaults = makeSuite()
        defaults.set(Data([0xFF, 0xAA]), forKey: "opds.savedCatalogs")
        #expect(defaults.data(forKey: "opds.savedCatalogs") != nil)

        TestSeeder.clearKnownPreferences(in: defaults)

        #expect(defaults.data(forKey: "opds.savedCatalogs") == nil)
    }

    @Test func clearsLibraryPreferences() {
        let defaults = makeSuite()
        defaults.set("title", forKey: "library.sortOrder")
        defaults.set("grid", forKey: "library.viewMode")

        TestSeeder.clearKnownPreferences(in: defaults)

        #expect(defaults.string(forKey: "library.sortOrder") == nil)
        #expect(defaults.string(forKey: "library.viewMode") == nil)
    }

    @Test func clearsReaderSettings() {
        let defaults = makeSuite()
        defaults.set("dark", forKey: "readerTheme")
        defaults.set("paged", forKey: "readerEPUBLayout")
        defaults.set(true, forKey: "readerAutoPageTurn")
        defaults.set(0.42, forKey: "readerBackgroundOpacity")
        defaults.set(Data([0x01]), forKey: "readerTapZoneConfig")

        TestSeeder.clearKnownPreferences(in: defaults)

        #expect(defaults.string(forKey: "readerTheme") == nil)
        #expect(defaults.string(forKey: "readerEPUBLayout") == nil)
        #expect(defaults.object(forKey: "readerAutoPageTurn") == nil)
        #expect(defaults.object(forKey: "readerBackgroundOpacity") == nil)
        #expect(defaults.data(forKey: "readerTapZoneConfig") == nil)
    }

    @Test func clearsAIKeys() {
        let defaults = makeSuite()
        defaults.set(Data([0x01]), forKey: "com.vreader.ai.configuration")
        defaults.set(true, forKey: "com.vreader.ai.consentGranted")
        defaults.set(Date(), forKey: "com.vreader.ai.consentDate")

        TestSeeder.clearKnownPreferences(in: defaults)

        #expect(defaults.data(forKey: "com.vreader.ai.configuration") == nil)
        #expect(defaults.object(forKey: "com.vreader.ai.consentGranted") == nil)
        #expect(defaults.object(forKey: "com.vreader.ai.consentDate") == nil)
    }

    @Test func clearsWebDAVAndHTTPTTSKeys() {
        let defaults = makeSuite()
        defaults.set(true, forKey: "com.vreader.webdav.wifiOnly")
        defaults.set(Data([0xCC]), forKey: "httpTTSConfig")

        TestSeeder.clearKnownPreferences(in: defaults)

        #expect(defaults.object(forKey: "com.vreader.webdav.wifiOnly") == nil)
        #expect(defaults.data(forKey: "httpTTSConfig") == nil)
    }

    @Test func leavesUnrelatedKeysUntouched() {
        let defaults = makeSuite()
        // Production keys (should be cleared)
        defaults.set("dark", forKey: "readerTheme")
        // Out-of-list keys (should survive — feature flags, sync change
        // tokens, anything not in the explicit list).
        defaults.set("preserve-me", forKey: "com.vreader.featureFlags.aiChat")
        defaults.set("preserve-me-too", forKey: "ck_changeToken_books")
        defaults.set("user-data", forKey: "com.unrelated.app.setting")

        TestSeeder.clearKnownPreferences(in: defaults)

        #expect(defaults.string(forKey: "readerTheme") == nil)
        #expect(defaults.string(forKey: "com.vreader.featureFlags.aiChat") == "preserve-me")
        #expect(defaults.string(forKey: "ck_changeToken_books") == "preserve-me-too")
        #expect(defaults.string(forKey: "com.unrelated.app.setting") == "user-data")
    }

    @Test func isIdempotent() {
        let defaults = makeSuite()
        defaults.set("dark", forKey: "readerTheme")

        TestSeeder.clearKnownPreferences(in: defaults)
        TestSeeder.clearKnownPreferences(in: defaults)  // second call should be a no-op

        #expect(defaults.string(forKey: "readerTheme") == nil)
    }

    @Test func keysListCoversBackupSettingsKeys() {
        // Production code's `BackupSettingsKeys.all` enumerates the
        // reader-side keys covered by backup. The test seeder's wipe
        // list should be a superset — missing a backup key here would
        // mean restoring from backup loses an override that the wipe
        // didn't reset before the test set it. Catch drift.
        let knownSet = Set(TestSeeder.knownPreferenceKeys)
        for key in BackupSettingsKeys.all {
            #expect(
                knownSet.contains(key),
                "TestSeeder.knownPreferenceKeys missing backup key: \(key)"
            )
        }
    }
}
