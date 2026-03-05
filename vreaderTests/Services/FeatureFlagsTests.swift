// Purpose: Tests for FeatureFlags — defaults per environment, runtime overrides.

import Testing
import Foundation
@testable import vreader

@Suite("FeatureFlags")
struct FeatureFlagsTests {

    // MARK: - Default Values in Prod

    @Test func aiAssistantDefaultOffInProd() {
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.aiAssistant == false)
    }

    @Test func syncDefaultOffInProd() {
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.sync == false)
    }

    @Test func searchIndexingVerboseLogsDefaultOffInProd() {
        let flags = FeatureFlags(environment: .prod)
        #expect(flags.searchIndexingVerboseLogs == false)
    }

    // MARK: - Default Values in Dev

    @Test func aiAssistantDefaultOffInDev() {
        let flags = FeatureFlags(environment: .dev)
        #expect(flags.aiAssistant == false)
    }

    @Test func syncDefaultOffInDev() {
        let flags = FeatureFlags(environment: .dev)
        #expect(flags.sync == false)
    }

    @Test func searchIndexingVerboseLogsDefaultOnInDev() {
        let flags = FeatureFlags(environment: .dev)
        #expect(flags.searchIndexingVerboseLogs == true)
    }

    // MARK: - Default Values in Staging

    @Test func searchIndexingVerboseLogsDefaultOnInStaging() {
        let flags = FeatureFlags(environment: .staging)
        #expect(flags.searchIndexingVerboseLogs == true)
    }

    // MARK: - Runtime Overrides

    @Test func overrideAIAssistantOn() {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)
        #expect(flags.aiAssistant == true)
    }

    @Test func overrideSyncOn() {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.sync, value: true)
        #expect(flags.sync == true)
    }

    @Test func overrideSearchIndexingVerboseLogsOff() {
        var flags = FeatureFlags(environment: .dev)
        flags.setOverride(.searchIndexingVerboseLogs, value: false)
        #expect(flags.searchIndexingVerboseLogs == false)
    }

    @Test func removeOverrideRestoresDefault() {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)
        #expect(flags.aiAssistant == true)
        flags.removeOverride(.aiAssistant)
        #expect(flags.aiAssistant == false)
    }

    @Test func removeOverrideForNonexistentKey() {
        // Should not crash
        var flags = FeatureFlags(environment: .prod)
        flags.removeOverride(.aiAssistant)
        #expect(flags.aiAssistant == false)
    }

    @Test func clearAllOverrides() {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)
        flags.setOverride(.sync, value: true)
        flags.clearAllOverrides()
        #expect(flags.aiAssistant == false)
        #expect(flags.sync == false)
    }

    // MARK: - Multiple Overrides

    @Test func multipleOverridesIndependent() {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)
        flags.setOverride(.sync, value: false)
        #expect(flags.aiAssistant == true)
        #expect(flags.sync == false)
    }

    @Test func overrideCanBeToggled() {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)
        #expect(flags.aiAssistant == true)
        flags.setOverride(.aiAssistant, value: false)
        #expect(flags.aiAssistant == false)
    }

    // MARK: - Sendable

    @Test func featureFlagsIsSendable() {
        let flags: any Sendable = FeatureFlags(environment: .prod)
        #expect(flags is FeatureFlags)
    }

    // MARK: - Flag Enum

    @Test func flagKeysAreExhaustive() {
        #expect(FeatureFlagKey.allCases.count == 3)
        #expect(FeatureFlagKey.allCases.contains(.aiAssistant))
        #expect(FeatureFlagKey.allCases.contains(.sync))
        #expect(FeatureFlagKey.allCases.contains(.searchIndexingVerboseLogs))
    }
}
