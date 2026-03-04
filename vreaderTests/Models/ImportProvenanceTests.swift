// Purpose: Tests for ImportProvenance and ImportSource — Codable, Hashable, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("ImportProvenance")
struct ImportProvenanceTests {

    // MARK: - ImportSource

    @Test func allSourcesCodable() throws {
        for source in ImportSource.allCases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(ImportSource.self, from: data)
            #expect(decoded == source)
        }
    }

    @Test func importSourceHasFourCases() {
        #expect(ImportSource.allCases.count == 4)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let original = ImportProvenance(
            source: .filesApp,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalURLBookmarkData: Data([0x01, 0x02, 0x03])
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImportProvenance.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundTripWithNilBookmark() throws {
        let original = ImportProvenance(
            source: .shareSheet,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImportProvenance.self, from: data)
        #expect(decoded.originalURLBookmarkData == nil)
        #expect(decoded.source == .shareSheet)
    }

    // MARK: - Hashable

    @Test func equalProvenancesHaveSameHash() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = ImportProvenance(source: .icloudDrive, importedAt: date, originalURLBookmarkData: nil)
        let b = ImportProvenance(source: .icloudDrive, importedAt: date, originalURLBookmarkData: nil)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func differentSourcesAreNotEqual() {
        let date = Date()
        let a = ImportProvenance(source: .filesApp, importedAt: date, originalURLBookmarkData: nil)
        let b = ImportProvenance(source: .localCopy, importedAt: date, originalURLBookmarkData: nil)
        #expect(a != b)
    }

    // MARK: - Edge Cases

    @Test func largeBookmarkData() throws {
        let largeData = Data(repeating: 0xFF, count: 100_000)
        let prov = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: largeData
        )
        let encoded = try JSONEncoder().encode(prov)
        let decoded = try JSONDecoder().decode(ImportProvenance.self, from: encoded)
        #expect(decoded.originalURLBookmarkData?.count == 100_000)
    }

    @Test func distantPastDate() throws {
        let prov = ImportProvenance(
            source: .filesApp,
            importedAt: Date.distantPast,
            originalURLBookmarkData: nil
        )
        let data = try JSONEncoder().encode(prov)
        let decoded = try JSONDecoder().decode(ImportProvenance.self, from: data)
        #expect(decoded.importedAt == Date.distantPast)
    }

    @Test func distantFutureDate() throws {
        let prov = ImportProvenance(
            source: .filesApp,
            importedAt: Date.distantFuture,
            originalURLBookmarkData: nil
        )
        let data = try JSONEncoder().encode(prov)
        let decoded = try JSONDecoder().decode(ImportProvenance.self, from: data)
        #expect(decoded.importedAt == Date.distantFuture)
    }
}
