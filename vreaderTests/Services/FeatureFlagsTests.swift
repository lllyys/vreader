// Purpose: Tests for FeatureFlags — defaults per environment, runtime overrides,
// shared singleton behavior, UserDefaults persistence.

import Testing
import Foundation
@testable import vreader

@Suite("FeatureFlags")
struct FeatureFlagsTests {

    // MARK: - Default Values in Prod

    @Test func aiAssistantDefaultOffInProd() {
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.isEnabled(.aiAssistant) == false)
    }

    @Test func syncDefaultOffInProd() {
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.isEnabled(.sync) == false)
    }

    // Feature #42 Phase 2 WI-4a: convert-on-import ships dark (default OFF).
    @Test func kindleConvertOnImportDefaultOff() {
        for env in [AppEnvironment.prod, .staging, .dev] {
            #expect(FeatureFlags(environment: env).isEnabled(.kindleConvertOnImport) == false)
        }
    }

    @Test func kindleConvertOnImportHonorsOverride() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .kindleConvertOnImport)
        #expect(flags.isEnabled(.kindleConvertOnImport) == true)
    }

    @Test func searchIndexingVerboseLogsDefaultOffInProd() {
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.isEnabled(.searchIndexingVerboseLogs) == false)
    }

    @Test func bilingualReadingDefaultOffInProd() {
        // Ships dark (like aiAssistant) so it can be enabled progressively.
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.isEnabled(.bilingualReading) == false)
        #expect(flags.bilingualReading == false)
    }

    @Test func bilingualReadingDefaultOffInDevAndStaging() {
        #expect(FeatureFlags(environment: .dev).bilingualReading == false)
        #expect(FeatureFlags(environment: .staging).bilingualReading == false)
    }

    @Test func bilingualReadingHonorsRuntimeOverride() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .bilingualReading)
        #expect(flags.bilingualReading == true)
        flags.removeOverride(for: .bilingualReading)
        #expect(flags.bilingualReading == false)
    }

    // MARK: - Default Values in Dev

    @Test func aiAssistantDefaultOffInDev() {
        let flags = FeatureFlags(environment: .dev)
        #expect(flags.isEnabled(.aiAssistant) == false)
    }

    @Test func syncDefaultOffInDev() {
        let flags = FeatureFlags(environment: .dev)
        #expect(flags.isEnabled(.sync) == false)
    }

    @Test func searchIndexingVerboseLogsDefaultOnInDev() {
        let flags = FeatureFlags(environment: .dev)
        #expect(flags.isEnabled(.searchIndexingVerboseLogs) == true)
    }

    // MARK: - Default Values in Staging

    @Test func searchIndexingVerboseLogsDefaultOnInStaging() {
        let flags = FeatureFlags(environment: .staging)
        #expect(flags.isEnabled(.searchIndexingVerboseLogs) == true)
    }

    // MARK: - Runtime Overrides

    @Test func overrideAIAssistantOn() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        #expect(flags.isEnabled(.aiAssistant) == true)
    }

    @Test func overrideSyncOn() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .sync)
        #expect(flags.isEnabled(.sync) == true)
    }

    @Test func overrideSearchIndexingVerboseLogsOff() {
        let flags = FeatureFlags(environment: .dev)
        flags.setOverride(false, for: .searchIndexingVerboseLogs)
        #expect(flags.isEnabled(.searchIndexingVerboseLogs) == false)
    }

    @Test func removeOverrideRestoresDefault() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        #expect(flags.isEnabled(.aiAssistant) == true)
        flags.removeOverride(for: .aiAssistant)
        #expect(flags.isEnabled(.aiAssistant) == false)
    }

    @Test func removeOverrideForNonexistentKey() {
        // Should not crash
        let flags = FeatureFlags(environment: .prod)
        flags.removeOverride(for: .aiAssistant)
        #expect(flags.isEnabled(.aiAssistant) == false)
    }

    @Test func clearAllOverrides() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        flags.setOverride(true, for: .sync)
        flags.clearAllOverrides()
        #expect(flags.isEnabled(.aiAssistant) == false)
        #expect(flags.isEnabled(.sync) == false)
    }

    // MARK: - Multiple Overrides

    @Test func multipleOverridesIndependent() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        flags.setOverride(false, for: .sync)
        #expect(flags.isEnabled(.aiAssistant) == true)
        #expect(flags.isEnabled(.sync) == false)
    }

    @Test func overrideCanBeToggled() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        #expect(flags.isEnabled(.aiAssistant) == true)
        flags.setOverride(false, for: .aiAssistant)
        #expect(flags.isEnabled(.aiAssistant) == false)
    }

    // MARK: - Sendable

    @Test func featureFlagsIsSendable() {
        let flags: any Sendable = FeatureFlags(environment: .prod)
        #expect(flags is FeatureFlags)
    }

    // MARK: - Flag Enum

    @Test func flagKeysAreExhaustive() {
        #expect(FeatureFlagKey.allCases.count == 7)
        #expect(FeatureFlagKey.allCases.contains(.aiAssistant))
        #expect(FeatureFlagKey.allCases.contains(.sync))
        #expect(FeatureFlagKey.allCases.contains(.searchIndexingVerboseLogs))
        #expect(FeatureFlagKey.allCases.contains(.bilingualReading))
        #expect(FeatureFlagKey.allCases.contains(.epubContinuousScroll))
        #expect(FeatureFlagKey.allCases.contains(.readiumEPUBEngine))
        #expect(FeatureFlagKey.allCases.contains(.kindleConvertOnImport))
    }

    // MARK: - Feature #42: readiumEPUBEngine

    @Test func readiumEPUBEngineDefaultsOnInAllEnvironments() {
        // Feature #42 WI-14 (human-gated G2, 2026-06-01): default ON everywhere —
        // the Readium navigator is now the default reflowable EPUB engine. The
        // pre-flip default was OFF (EPUBWebViewBridge); the G2 sign-off moved it.
        for env in AppEnvironment.allCases {
            let flags = FeatureFlags(environment: env)
            #expect(flags.readiumEPUBEngine == true)
            #expect(flags.isEnabled(.readiumEPUBEngine) == true)
        }
    }

    @Test func readiumEPUBEngineOverrideCanDisable() {
        // Post-WI-14 the default is ON; a user can still revert to the legacy
        // `EPUBWebViewBridge` by setting the persisted override OFF. Removing the
        // override restores the default (now ON).
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(false, for: .readiumEPUBEngine)
        #expect(flags.readiumEPUBEngine == false)
        flags.removeOverride(for: .readiumEPUBEngine)
        #expect(flags.readiumEPUBEngine == true)
    }

    @Test func readiumEPUBEngineOverridePersists() {
        // WI-14 (Codex audit Low): the persisted OFF override must survive a
        // reload, beating the new ON default — this is the path a user who
        // reverts to the legacy `EPUBWebViewBridge` relies on. Persist `false`
        // (NOT the ON default) so the reload assertion is discriminating: a
        // regression dropping `.readiumEPUBEngine` from `persistedFlags` would
        // make the reload read the ON default and fail this test.
        let suiteName = "test.readiumEPUBEngine.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let flags = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        flags.setOverride(false, for: .readiumEPUBEngine)
        #expect(defaults.bool(forKey: "com.vreader.featureFlags.readiumEPUBEngine") == false)

        // A fresh instance over the same defaults reads the persisted OFF
        // override, beating the new ON default.
        let reloaded = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        #expect(reloaded.readiumEPUBEngine == false)
        // Removing the persisted override restores the new ON default.
        reloaded.removeOverride(for: .readiumEPUBEngine)
        #expect(reloaded.readiumEPUBEngine == true)
    }

    // MARK: - Feature #71: epubContinuousScroll

    @Test func epubContinuousScrollDefaultsOnInAllEnvironments() {
        // Feature #71's terminal WI flipped the default ON (2026-05-28): after
        // real-touch-scroll device verification confirmed the rAF observer fires
        // and the cross-chapter materialize/evict works end-to-end, continuous
        // scroll became the default EPUB scroll-mode reading experience.
        for env in AppEnvironment.allCases {
            let flags = FeatureFlags(environment: env)
            #expect(flags.epubContinuousScroll == true)
            #expect(flags.isEnabled(.epubContinuousScroll) == true)
        }
    }

    @Test func epubContinuousScrollOverrideCanDisable() {
        // Now that the default is ON, a user/debug override can still turn it OFF;
        // removing the override restores the new default (ON).
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(false, for: .epubContinuousScroll)
        #expect(flags.epubContinuousScroll == false)
        flags.removeOverride(for: .epubContinuousScroll)
        #expect(flags.epubContinuousScroll == true)
    }

    @Test func epubContinuousScrollOverridePersists() {
        // Persisted (aiAssistant pattern) so a `defaults write` override survives
        // across launches — the device-verification recipe relies on this.
        // Persist `false` (NOT the new ON default) so the reload assertion is
        // discriminating: a `true` here would now match the default and pass even
        // if init ignored persisted values (Codex Gate-4 Low). A persisted `false`
        // surviving a reload proves the persisted-override load path works.
        let suiteName = "test.epubContinuousScroll.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let flags = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        flags.setOverride(false, for: .epubContinuousScroll)
        #expect(defaults.bool(forKey: "com.vreader.featureFlags.epubContinuousScroll") == false)

        // A fresh instance over the same defaults reads the persisted OFF override,
        // beating the new ON default.
        let reloaded = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        #expect(reloaded.epubContinuousScroll == false)
        // Removing the persisted override restores the new ON default.
        reloaded.removeOverride(for: .epubContinuousScroll)
        #expect(reloaded.epubContinuousScroll == true)
    }

    // MARK: - Shared Singleton (Issue 1)

    @Test func sharedInstanceReflectsOverride() {
        // Configure shared for test
        FeatureFlags.shared.configure(environment: .prod)
        FeatureFlags.shared.clearAllOverrides()

        // Set override on shared
        FeatureFlags.shared.setOverride(true, for: .aiAssistant)

        // Read from the same shared — should see the change
        #expect(FeatureFlags.shared.isEnabled(.aiAssistant) == true)

        // Clean up
        FeatureFlags.shared.clearAllOverrides()
    }

    @Test func defaultValuesPreserved() {
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.isEnabled(.aiAssistant) == false)
        #expect(flags.isEnabled(.sync) == false)
        #expect(flags.isEnabled(.searchIndexingVerboseLogs) == false)

        let devFlags = FeatureFlags(environment: .dev)
        #expect(devFlags.isEnabled(.searchIndexingVerboseLogs) == true)
    }

    @Test func aiAssistantOverridePersistsToUserDefaults() {
        let suiteName = "com.vreader.test.featureflags.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let flags = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        flags.setOverride(true, for: .aiAssistant)

        // Check that UserDefaults has the value
        #expect(defaults.bool(forKey: "com.vreader.featureFlags.aiAssistant") == true)

        // Another instance with same defaults should see the persisted value
        let flags2 = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        #expect(flags2.isEnabled(.aiAssistant) == true)

        // Clean up
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func nonPersistedFlagDoesNotWriteToDefaults() {
        let suiteName = "com.vreader.test.featureflags.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let flags = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        flags.setOverride(true, for: .sync)

        // sync flag should NOT be persisted to UserDefaults
        #expect(defaults.object(forKey: "com.vreader.featureFlags.sync") == nil)

        // Clean up
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Convenience Accessors

    @Test func convenienceAccessorsMatchIsEnabled() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        flags.setOverride(true, for: .sync)
        #expect(flags.aiAssistant == flags.isEnabled(.aiAssistant))
        #expect(flags.sync == flags.isEnabled(.sync))
        #expect(flags.searchIndexingVerboseLogs == flags.isEnabled(.searchIndexingVerboseLogs))
    }
}
