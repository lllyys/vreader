// Purpose: Tests for KeychainService+ProviderProfile extension (feature #50 WI-1).
// Verifies the per-profile keychain account naming convention and the
// read/save/delete round-trip wrappers compose with the existing
// KeychainService primitives.

import Testing
import Foundation
@testable import vreader

@Suite("KeychainService+ProviderProfile")
struct KeychainProviderProfileExtensionTests {

    /// Use a unique service identifier per test suite run so test items
    /// don't collide with the production keychain or with parallel test runs.
    private static func makeKeychain() -> KeychainService {
        KeychainService(
            serviceIdentifier: "com.vreader.tests.\(UUID().uuidString)"
        )
    }

    @Test func providerAccountFormatIsExact() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let account = KeychainService.providerAccount(for: id)
        #expect(account == "com.vreader.ai.apiKey.11111111-2222-3333-4444-555555555555")
    }

    @Test func providerAccountUsesUppercaseUUID() {
        let id = UUID()
        let account = KeychainService.providerAccount(for: id)
        // UUID().uuidString returns uppercase hex by default; the keychain
        // account string must match that exactly so different reads of the
        // same UUID produce the same account.
        #expect(account == "com.vreader.ai.apiKey.\(id.uuidString)")
    }

    @Test func saveAndReadRoundTrip() throws {
        let keychain = Self.makeKeychain()
        let id = UUID()
        try keychain.saveAPIKey("sk-test-12345", forProfile: id)
        defer { try? keychain.deleteAPIKey(forProfile: id) }

        let read = try keychain.readAPIKey(forProfile: id)
        #expect(read == "sk-test-12345")
    }

    @Test func readMissingReturnsNil() throws {
        let keychain = Self.makeKeychain()
        let result = try keychain.readAPIKey(forProfile: UUID())
        #expect(result == nil)
    }

    @Test func deleteIsIdempotent() throws {
        let keychain = Self.makeKeychain()
        let id = UUID()
        // Delete a key that never existed — must not throw.
        try keychain.deleteAPIKey(forProfile: id)
        // Save then delete twice — neither call must throw.
        try keychain.saveAPIKey("sk-temp", forProfile: id)
        try keychain.deleteAPIKey(forProfile: id)
        try keychain.deleteAPIKey(forProfile: id)
        #expect(try keychain.readAPIKey(forProfile: id) == nil)
    }

    @Test func differentProfilesHaveIndependentStorage() throws {
        let keychain = Self.makeKeychain()
        let idA = UUID()
        let idB = UUID()
        try keychain.saveAPIKey("key-a", forProfile: idA)
        try keychain.saveAPIKey("key-b", forProfile: idB)
        defer {
            try? keychain.deleteAPIKey(forProfile: idA)
            try? keychain.deleteAPIKey(forProfile: idB)
        }

        #expect(try keychain.readAPIKey(forProfile: idA) == "key-a")
        #expect(try keychain.readAPIKey(forProfile: idB) == "key-b")
    }

    @Test func saveOverwritesExisting() throws {
        let keychain = Self.makeKeychain()
        let id = UUID()
        try keychain.saveAPIKey("old", forProfile: id)
        try keychain.saveAPIKey("new", forProfile: id)
        defer { try? keychain.deleteAPIKey(forProfile: id) }

        #expect(try keychain.readAPIKey(forProfile: id) == "new")
    }

    @Test func deletingOneProfileDoesNotAffectOthers() throws {
        let keychain = Self.makeKeychain()
        let idA = UUID()
        let idB = UUID()
        try keychain.saveAPIKey("key-a", forProfile: idA)
        try keychain.saveAPIKey("key-b", forProfile: idB)
        defer {
            try? keychain.deleteAPIKey(forProfile: idA)
            try? keychain.deleteAPIKey(forProfile: idB)
        }

        try keychain.deleteAPIKey(forProfile: idA)

        #expect(try keychain.readAPIKey(forProfile: idA) == nil)
        #expect(try keychain.readAPIKey(forProfile: idB) == "key-b")
    }
}
