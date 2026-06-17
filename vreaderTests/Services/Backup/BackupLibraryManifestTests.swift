// Purpose: Tests for BackupLibraryManifestEnvelope + BackupLibraryEntry — the
// new section emitted into the backup ZIP by feature #46 so restore can
// materialize books on a fresh device. Asserts round-trip, schemaVersion
// guard, and that blobPath agrees with BlobPath.make.
//
// @coordinates-with: vreader/Services/Backup/BackupSectionDTOs.swift,
//   vreader/Services/Backup/BlobPath.swift,
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Testing
import Foundation
@testable import vreader

@Suite("BackupLibraryManifest — feature #46 WI-2")
struct BackupLibraryManifestTests {

    // MARK: - Helpers

    private func sampleEntry(
        fingerprintKey: String = "epub:\(String(repeating: "a", count: 64)):1024",
        format: String = "epub",
        sha256: String = String(repeating: "a", count: 64),
        byteCount: Int64 = 1024,
        originalExtension: String = "epub",
        title: String? = "Sample",
        author: String? = "Author",
        addedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        lastOpenedAt: Date? = nil,
        blobPath: String? = nil
    ) -> BackupLibraryEntry {
        BackupLibraryEntry(
            fingerprintKey: fingerprintKey,
            format: format,
            sha256: sha256,
            byteCount: byteCount,
            originalExtension: originalExtension,
            title: title,
            author: author,
            addedAt: addedAt,
            lastOpenedAt: lastOpenedAt,
            blobPath: blobPath ?? BlobPath.make(format: .epub, sha256: sha256, byteCount: byteCount)
        )
    }

    // MARK: - Feature #108: sourceCanonicalKey carry + back-compat

    @Test func entryCarriesSourceCanonicalKeyAcrossRoundTrip() throws {
        let srcKey = "azw3:\(String(repeating: "b", count: 64)):4096"
        var entry = sampleEntry()
        entry.sourceCanonicalKey = srcKey
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: [entry])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupLibraryManifestEnvelope.self, from: data)
        #expect(decoded.books.first?.sourceCanonicalKey == srcKey)
    }

    @Test func olderManifestWithoutSourceKeyDecodesNil() throws {
        // A pre-#108 manifest entry has NO sourceCanonicalKey field.
        let json = """
        {"schemaVersion":1,"books":[{
          "fingerprintKey":"epub:\(String(repeating: "a", count: 64)):1024",
          "format":"epub","sha256":"\(String(repeating: "a", count: 64))",
          "byteCount":1024,"originalExtension":"epub","title":"Old","author":null,
          "addedAt":"2023-11-14T22:13:20Z","lastOpenedAt":null,
          "blobPath":"VReader/books/epub/\(String(repeating: "a", count: 64))_1024.epub"
        }]}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupLibraryManifestEnvelope.self, from: Data(json.utf8))
        #expect(decoded.books.count == 1)
        #expect(decoded.books.first?.sourceCanonicalKey == nil)   // back-compat
    }

    // MARK: - Round-trip

    @Test func emptyEnvelope_roundTrips() throws {
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupLibraryManifestEnvelope.self, from: data)
        #expect(decoded == envelope)
    }

    @Test func multiBookEnvelope_roundTrips() throws {
        let entries: [BackupLibraryEntry] = [
            sampleEntry(),
            sampleEntry(
                fingerprintKey: "azw3:\(String(repeating: "b", count: 64)):4096",
                format: "azw3",
                sha256: String(repeating: "b", count: 64),
                byteCount: 4096,
                originalExtension: "mobi",
                title: "MOBI Book",
                lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_500),
                blobPath: BlobPath.make(format: .azw3, sha256: String(repeating: "b", count: 64), byteCount: 4096)
            ),
        ]
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupLibraryManifestEnvelope.self, from: data)
        #expect(decoded == envelope)
        // MOBI extension preserved through the round-trip — the whole point of WI-0a.
        #expect(decoded.books[1].originalExtension == "mobi")
        #expect(decoded.books[1].format == "azw3")
    }

    // MARK: - schemaVersion conformance

    @Test func envelopeConformsToVersionedProtocol() {
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: [])
        // Cast to the protocol — verifies conformance compiles + the field is exposed.
        let asProto: BackupVersionedEnvelope = envelope
        #expect(asProto.schemaVersion == 1)
    }

    // MARK: - Blob path agreement

    @Test func entryBlobPath_matchesBlobPathMakeForFormat() {
        let sha = String(repeating: "c", count: 64)
        let bytes: Int64 = 9_999_999
        let expected = BlobPath.make(format: .azw3, sha256: sha, byteCount: bytes)
        let entry = sampleEntry(
            fingerprintKey: "azw3:\(sha):\(bytes)",
            format: "azw3",
            sha256: sha,
            byteCount: bytes,
            originalExtension: "azw3",
            blobPath: expected
        )
        #expect(entry.blobPath == expected)
        // And it round-trips through the path's parser.
        let parsed = BlobPath.parse(entry.blobPath)
        #expect(parsed?.sha256 == sha)
        #expect(parsed?.byteCount == bytes)
        #expect(parsed?.format == .azw3)
    }

    // MARK: - JSON shape stability

    @Test func envelopeJSON_includesExpectedTopLevelKeys() throws {
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let json = String(data: data, encoding: .utf8) ?? ""
        // Pin the top-level shape so consumers (including older clients in the
        // future) can assert against a stable schema.
        #expect(json.contains("\"schemaVersion\":1"))
        #expect(json.contains("\"books\":"))
    }

    @Test func entryJSON_includesAllFields() throws {
        let entry = sampleEntry(lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_500))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entry)
        let json = String(data: data, encoding: .utf8) ?? ""
        for key in ["fingerprintKey", "format", "sha256", "byteCount",
                    "originalExtension", "title", "author", "addedAt",
                    "lastOpenedAt", "blobPath"] {
            #expect(json.contains("\"\(key)\":"), "missing key \"\(key)\" in JSON")
        }
    }

    // MARK: - Optional field encoding

    @Test func entryWithNilOptionals_decodes() throws {
        // Some entries may have nil author / lastOpenedAt / title.
        let entry = sampleEntry(title: nil, author: nil, lastOpenedAt: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupLibraryEntry.self, from: data)
        #expect(decoded.title == nil)
        #expect(decoded.author == nil)
        #expect(decoded.lastOpenedAt == nil)
    }
}
