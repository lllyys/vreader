// Purpose: Tests for MOBIMetadataParser — native MOBI/PDB binary parsing for
// AZW3/MOBI title + author extraction (EXTH records 503 + 100).
//
// Uses the real `mini-azw3.azw3` fixture (PG ebook 1064, "The Masque of the
// Red Death" by Edgar Allan Poe) in DEBUG bundle for the happy path.
// Synthetic fixtures cover edge cases (malformed file, missing EXTH).
//
// @coordinates-with: MOBIMetadataParser.swift, MetadataExtractor.swift (AZW3MetadataExtractor)

import Testing
import Foundation
@testable import vreader

@Suite("MOBIMetadataParser")
struct MOBIMetadataParserTests {

    // MARK: - Real fixture (mini-azw3.azw3)

    /// Bug #149 / GH #340 happy path: real MOBI file's EXTH records yield the
    /// canonical title + author. This is the production input the AZW3
    /// metadata extractor will run against.
    @Test func extractsTitleAndAuthor_fromMiniAzw3Fixture() throws {
        #if DEBUG
        let url = try #require(Bundle.main.url(
            forResource: "mini-azw3",
            withExtension: "azw3",
            subdirectory: RealDebugBridgeContext.fixtureBundleSubdirectory
        ))
        let result = MOBIMetadataParser.extractTitleAndAuthor(from: url)
        #expect(result.title == "The Masque of the Red Death",
                "EXTH 503 (Updated title) must be returned, not the underscore-joined palmdb title")
        #expect(result.author == "Edgar Allan Poe",
                "EXTH 100 (Author) must be returned")
        #endif
    }

    // MARK: - Edge cases

    @Test func returnsNil_whenFileMissing() {
        let url = URL(fileURLWithPath: "/nonexistent/path/file.azw3")
        let result = MOBIMetadataParser.extractTitleAndAuthor(from: url)
        #expect(result.title == nil)
        #expect(result.author == nil)
    }

    @Test func returnsNil_whenFileTooSmall() throws {
        // Smaller than the 78-byte PDB header → guard returns nil.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tiny-\(UUID().uuidString).bin")
        try Data(repeating: 0, count: 32).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let result = MOBIMetadataParser.extractTitleAndAuthor(from: tmp)
        #expect(result.title == nil)
        #expect(result.author == nil)
    }

    @Test func returnsNil_whenNotMobi() throws {
        // 200 bytes of zeros — passes minimum-size guard, but no MOBI magic at
        // record 0 / offset 16 → parser bails.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("notmobi-\(UUID().uuidString).bin")
        try Data(repeating: 0, count: 200).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let result = MOBIMetadataParser.extractTitleAndAuthor(from: tmp)
        #expect(result.title == nil)
        #expect(result.author == nil)
    }

    /// Codex round-1 Medium: a file with EXTH magic but `exthLength < 12`
    /// (smaller than the EXTH header itself) should NOT let the loop wander
    /// off into adjacent bytes; parser must return (nil, nil). We construct
    /// a minimal corrupt MOBI by copying the real fixture and overwriting
    /// the 4-byte exthLength with `0x00000004` (claims 4 bytes total — too
    /// short to even hold the header).
    @Test func returnsNil_whenExthLengthTooSmall() throws {
        #if DEBUG
        let realURL = try #require(Bundle.main.url(
            forResource: "mini-azw3",
            withExtension: "azw3",
            subdirectory: RealDebugBridgeContext.fixtureBundleSubdirectory
        ))
        var data = try Data(contentsOf: realURL)

        // Locate exthLength field and overwrite with a too-small value (4).
        // Replicating the parser's offset math:
        //   record0 starts at offsets[0] (78-byte PDB header + table)
        //   MOBI header is at record0+16; mobiLength at record0+20 (UInt32 BE)
        //   EXTH starts at record0 + 16 + mobiLength
        //   exthLength is at exthStart + 4
        let record0Offset = Int(UInt32(data[78]) << 24 | UInt32(data[79]) << 16
                                | UInt32(data[80]) << 8 | UInt32(data[81]))
        let mobiLength = Int(UInt32(data[record0Offset + 20]) << 24
                             | UInt32(data[record0Offset + 21]) << 16
                             | UInt32(data[record0Offset + 22]) << 8
                             | UInt32(data[record0Offset + 23]))
        let exthLengthOffset = record0Offset + 16 + mobiLength + 4

        data[exthLengthOffset]     = 0x00
        data[exthLengthOffset + 1] = 0x00
        data[exthLengthOffset + 2] = 0x00
        data[exthLengthOffset + 3] = 0x04  // exthLength = 4 (< 12)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("malformed-exth-\(UUID().uuidString).azw3")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = MOBIMetadataParser.extractTitleAndAuthor(from: tmp)
        #expect(result.title == nil,
                "Malformed EXTH length must NOT yield garbage title")
        #expect(result.author == nil,
                "Malformed EXTH length must NOT yield garbage author")
        #endif
    }
}

@Suite("AZW3MetadataExtractor — EXTH integration")
struct AZW3MetadataExtractorEXTHTests {

    /// Bug #149 / GH #340: the production extractor must surface EXTH title +
    /// author when present, and fall back to filename when not.
    @Test func extractMetadata_fromMiniAzw3_returnsExthTitleAndAuthor() async throws {
        #if DEBUG
        let url = try #require(Bundle.main.url(
            forResource: "mini-azw3",
            withExtension: "azw3",
            subdirectory: RealDebugBridgeContext.fixtureBundleSubdirectory
        ))
        let extractor = AZW3MetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "The Masque of the Red Death",
                "AZW3MetadataExtractor must use EXTH 503 over filename")
        #expect(metadata.author == "Edgar Allan Poe",
                "AZW3MetadataExtractor must use EXTH 100")
        #endif
    }

    /// Fallback: a non-MOBI file (or missing EXTH) → use filename, like before.
    @Test func extractMetadata_fromNonMobi_fallsBackToFilename() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("My Book Title-\(UUID().uuidString).azw3")
        try Data(repeating: 0, count: 200).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let extractor = AZW3MetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: tmp)
        // Filename without extension; UUID suffix is part of the title since
        // we synthesized it that way.
        #expect(metadata.title.hasPrefix("My Book Title-"),
                "Non-MOBI / missing EXTH should fall back to filename")
        #expect(metadata.author == nil,
                "No EXTH 100 → author stays nil")
    }
}
