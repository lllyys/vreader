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
        #expect(FeatureFlagKey.allCases.count == 4)
        #expect(FeatureFlagKey.allCases.contains(.aiAssistant))
        #expect(FeatureFlagKey.allCases.contains(.sync))
        #expect(FeatureFlagKey.allCases.contains(.searchIndexingVerboseLogs))
        #expect(FeatureFlagKey.allCases.contains(.bilingualReading))
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
