// Feature #113 WI-3 — Swift side of the cross-platform backup-format conformance. Decodes every
// section in the SHARED golden vector `contracts/vectors/backup-sections.json` into its iOS DTO
// (BackupSectionDTOs.swift + BackupReadingHistory.swift + BackupAIConversations.swift +
// BackupProvider.swift's BackupMetadata), re-encodes, and asserts the re-encode's PARSED JSON
// equals the vector's — semantic equality (key order / whitespace / JSON-number formatting
// insignificant). The Kotlin conformance (android/identity .../BackupConformanceTest) asserts
// the SAME vector with the Kotlin DTOs; both green ⇒ a backup written by one platform restores
// on the other (contracts/identity/backup-format.md).
//
// The vectors are located relative to THIS source file via `#filePath` (the iOS sim test runs
// as a host process on the Mac), so `contracts/vectors/` stays the single source of truth.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #113 WI-3 — cross-platform backup-format conformance (Swift side)")
struct BackupConformanceTests {

    private static func sections(file: String = #filePath) throws -> [String: Any] {
        let url = URL(fileURLWithPath: file)
            .deletingLastPathComponent()   // Contracts/
            .deletingLastPathComponent()   // vreaderTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("contracts/vectors/backup-sections.json")
        let data = try Data(contentsOf: url)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["sections"] as? [String: Any])
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    /// Decode the named section into [T], re-encode, and assert the parsed JSON matches the vector.
    private func roundTrips<T: Codable>(_ type: T.Type, _ name: String) throws {
        let sections = try Self.sections()
        let sectionObj = try #require(sections[name] as? [String: Any], "missing vector section \(name)")
        let sectionData = try JSONSerialization.data(withJSONObject: sectionObj)
        let dto = try Self.decoder.decode(T.self, from: sectionData)
        let reData = try Self.encoder.encode(dto)
        let reObj = try #require(try JSONSerialization.jsonObject(with: reData))
        // A TYPE-AWARE deep compare (not NSDictionary.isEqual, which treats JSON `true` == `1`).
        // The cross-platform contract needs Bool/Number type parity, matching the Kotlin side's
        // JsonElement equality.
        #expect(jsonEqual(sectionObj as Any, reObj),
                "section '\(name)' did not round-trip to the golden vector")
    }

    /// Recursive JSON equality that keeps JSON `Bool` distinct from numeric `NSNumber`
    /// (Foundation's `NSNumber(true) == NSNumber(1)`, which `NSDictionary.isEqual` inherits).
    private func jsonEqual(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (da as [String: Any], db as [String: Any]):
            guard da.keys.sorted() == db.keys.sorted() else { return false }
            return da.allSatisfy { k, v in db[k].map { jsonEqual(v, $0) } ?? false }
        case let (aa as [Any], ab as [Any]):
            return aa.count == ab.count && zip(aa, ab).allSatisfy { jsonEqual($0, $1) }
        case let (na as NSNumber, nb as NSNumber):
            // Distinguish CFBoolean from a numeric NSNumber, then compare by value.
            let aBool = CFGetTypeID(na) == CFBooleanGetTypeID()
            let bBool = CFGetTypeID(nb) == CFBooleanGetTypeID()
            return aBool == bBool && na == nb
        case let (sa as String, sb as String):
            return sa == sb
        case (is NSNull, is NSNull):
            return true
        default:
            return false
        }
    }

    @Test func annotations() throws { try roundTrips(BackupAnnotationsEnvelope.self, "annotations") }
    @Test func positions() throws { try roundTrips(BackupPositionsEnvelope.self, "positions") }
    @Test func collections() throws { try roundTrips(BackupCollectionsEnvelope.self, "collections") }
    @Test func libraryManifest() throws { try roundTrips(BackupLibraryManifestEnvelope.self, "library-manifest") }
    @Test func settings() throws { try roundTrips(BackupSettingsEnvelope.self, "settings") }
    @Test func bookSources() throws { try roundTrips(BackupBookSourcesEnvelope.self, "book-sources") }
    @Test func perBookSettings() throws { try roundTrips(BackupPerBookSettingsEnvelope.self, "per-book-settings") }
    @Test func replacementRules() throws { try roundTrips(BackupReplacementRulesEnvelope.self, "replacement-rules") }
    @Test func readingHistory() throws { try roundTrips(BackupReadingHistoryEnvelope.self, "reading-history") }
    @Test func aiConversations() throws { try roundTrips(BackupAIConversationsEnvelope.self, "ai-conversations") }
    @Test func metadata() throws { try roundTrips(BackupMetadata.self, "metadata") }

    @Test("Schema constants match the vector + the contract")
    func schemaConstants() throws {
        #expect(kBackupCurrentSchemaVersion == 3)
        #expect(kBackupAcceptedSchemaVersions.contains(kBackupCurrentSchemaVersion))
    }
}
#endif
