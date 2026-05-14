// Purpose: Tests for WebDAVServerProfile value type (feature #52 WI-1).
// Verifies Codable round-trip, displayName fallback, keychain account
// string format, UUID identity, Equatable/Hashable.

import Testing
import Foundation
@testable import vreader

@Suite("WebDAVServerProfile")
struct WebDAVServerProfileTests {

    // MARK: - Codable round-trip

    @Test func codableRoundTrip_preservesAllFields() throws {
        let id = UUID()
        let original = WebDAVServerProfile(
            id: id,
            name: "Home Nextcloud",
            serverURL: "https://nextcloud.example.com/remote.php/dav/files/me/",
            username: "alice"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebDAVServerProfile.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.name == "Home Nextcloud")
        #expect(decoded.serverURL == "https://nextcloud.example.com/remote.php/dav/files/me/")
        #expect(decoded.username == "alice")
    }

    @Test func codableRoundTrip_emptyStringsPreserved() throws {
        let original = WebDAVServerProfile(
            id: UUID(),
            name: "",
            serverURL: "",
            username: ""
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebDAVServerProfile.self, from: data)
        #expect(decoded.name == "")
        #expect(decoded.serverURL == "")
        #expect(decoded.username == "")
    }

    // MARK: - displayName fallback

    @Test func displayName_usesNameWhenNonEmpty() {
        let profile = WebDAVServerProfile(
            id: UUID(),
            name: "Work Synology",
            serverURL: "https://synology.example.com/webdav/",
            username: "bob"
        )
        #expect(profile.displayName == "Work Synology")
    }

    @Test func displayName_fallsBackToHostWhenNameEmpty() {
        let profile = WebDAVServerProfile(
            id: UUID(),
            name: "",
            serverURL: "https://nextcloud.example.com/remote.php/dav/",
            username: "alice"
        )
        #expect(profile.displayName == "nextcloud.example.com")
    }

    @Test func displayName_fallsBackToHostWhenNameWhitespaceOnly() {
        let profile = WebDAVServerProfile(
            id: UUID(),
            name: "   \n\t  ",
            serverURL: "https://nas.tailnet.example.ts.net/dav/",
            username: "user"
        )
        #expect(profile.displayName == "nas.tailnet.example.ts.net")
    }

    @Test func displayName_returnsRawURLWhenHostMissing() {
        // URL parsing of a malformed string produces nil for .host
        let profile = WebDAVServerProfile(
            id: UUID(),
            name: "",
            serverURL: "not-a-url",
            username: "user"
        )
        #expect(profile.displayName == "not-a-url")
    }

    // MARK: - keychainPasswordAccount

    @Test func keychainPasswordAccount_includesProfileID() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let account = WebDAVServerProfile.keychainPasswordAccount(for: id)
        #expect(account == "com.vreader.webdav.profile.12345678-1234-1234-1234-123456789ABC.password")
    }

    @Test func keychainPasswordAccount_isUniquePerID() {
        let a = WebDAVServerProfile.keychainPasswordAccount(for: UUID())
        let b = WebDAVServerProfile.keychainPasswordAccount(for: UUID())
        #expect(a != b)
    }

    @Test func keychainPasswordAccount_isStableForSameID() {
        let id = UUID()
        let a = WebDAVServerProfile.keychainPasswordAccount(for: id)
        let b = WebDAVServerProfile.keychainPasswordAccount(for: id)
        #expect(a == b)
    }

    // MARK: - Hashable / Equatable

    @Test func hashable_sameIDSameFieldsAreEqual() {
        let id = UUID()
        let a = WebDAVServerProfile(id: id, name: "A", serverURL: "https://a.com/", username: "u")
        let b = WebDAVServerProfile(id: id, name: "A", serverURL: "https://a.com/", username: "u")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func hashable_differentIDsAreUnequal() {
        let a = WebDAVServerProfile(id: UUID(), name: "A", serverURL: "https://a.com/", username: "u")
        let b = WebDAVServerProfile(id: UUID(), name: "A", serverURL: "https://a.com/", username: "u")
        #expect(a != b)
    }
}
