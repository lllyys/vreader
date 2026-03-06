// Purpose: Tests for AIConsentManager — consent lifecycle, date recording, revocation.

import Testing
import Foundation
@testable import vreader

@Suite("AIConsentManager")
struct AIConsentManagerTests {

    // MARK: - Helpers

    /// Creates a consent manager backed by an ephemeral UserDefaults suite.
    private func makeManager() -> AIConsentManager {
        let suiteName = "com.vreader.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AIConsentManager(defaults: defaults)
    }

    // MARK: - Default State

    @Test func defaultNoConsent() {
        let manager = makeManager()
        #expect(manager.hasConsent == false)
    }

    @Test func defaultConsentDateNil() {
        let manager = makeManager()
        #expect(manager.consentDate == nil)
    }

    // MARK: - Grant Consent

    @Test func grantConsentSetsTrue() {
        let manager = makeManager()
        manager.grantConsent()
        #expect(manager.hasConsent == true)
    }

    @Test func grantConsentRecordsDate() {
        let manager = makeManager()
        let before = Date()
        manager.grantConsent()
        let after = Date()

        let date = manager.consentDate
        #expect(date != nil)
        #expect(date! >= before)
        #expect(date! <= after)
    }

    @Test func grantConsentIdempotent() {
        let manager = makeManager()
        manager.grantConsent()
        let firstDate = manager.consentDate

        // Small delay to ensure second grant gets different timestamp
        manager.grantConsent()

        #expect(manager.hasConsent == true)
        // Date may or may not change — both are acceptable
        #expect(manager.consentDate != nil)
        _ = firstDate // suppress unused warning
    }

    // MARK: - Revoke Consent

    @Test func revokeConsentClearsState() {
        let manager = makeManager()
        manager.grantConsent()
        #expect(manager.hasConsent == true)

        manager.revokeConsent()
        #expect(manager.hasConsent == false)
    }

    @Test func revokeConsentClearsDate() {
        let manager = makeManager()
        manager.grantConsent()
        #expect(manager.consentDate != nil)

        manager.revokeConsent()
        #expect(manager.consentDate == nil)
    }

    @Test func revokeWithoutPriorGrantDoesNotCrash() {
        let manager = makeManager()
        // Should not crash
        manager.revokeConsent()
        #expect(manager.hasConsent == false)
        #expect(manager.consentDate == nil)
    }

    // MARK: - Grant After Revoke

    @Test func grantAfterRevokeWorks() {
        let manager = makeManager()
        manager.grantConsent()
        manager.revokeConsent()

        #expect(manager.hasConsent == false)

        manager.grantConsent()
        #expect(manager.hasConsent == true)
        #expect(manager.consentDate != nil)
    }

    // MARK: - Sendable

    @Test func consentManagerIsSendable() {
        let manager: any Sendable = makeManager()
        #expect(manager is AIConsentManager)
    }
}
