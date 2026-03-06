// Purpose: Tests for ZIPReader — parsing and extraction of ZIP archives.

import Testing
import Foundation
@testable import vreader

@Suite("ZIPReader")
struct ZIPReaderTests {

    // MARK: - Test ZIP Creation Helper

    /// Creates a minimal valid ZIP file with a single stored (uncompressed) entry.
    private static func createTestZIP(
        fileName: String,
        content: Data
    ) throws -> URL {
        var archive = Data()
        let nameData = Data(fileName.utf8)

        // Local File Header
        let localHeader = buildLocalFileHeader(
            nameData: nameData,
            content: content
        )
        let localHeaderOffset = archive.count
        archive.append(localHeader)
        archive.append(nameData)
        archive.append(content)

        // Central Directory Entry
        let cdOffset = archive.count
        let cdEntry = buildCentralDirectoryEntry(
            nameData: nameData,
            content: content,
            localHeaderOffset: UInt32(localHeaderOffset)
        )
        archive.append(cdEntry)
        archive.append(nameData)

        let cdSize = archive.count - cdOffset

        // End of Central Directory
        let eocd = buildEOCD(
            entryCount: 1,
            cdSize: UInt32(cdSize),
            cdOffset: UInt32(cdOffset)
        )
        archive.append(eocd)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).zip")
        try archive.write(to: url)
        return url
    }

    private static func buildLocalFileHeader(nameData: Data, content: Data) -> Data {
        var header = Data()
        header.appendUInt32LE(0x04034b50) // signature
        header.appendUInt16LE(20)         // version needed
        header.appendUInt16LE(0)          // flags
        header.appendUInt16LE(0)          // compression (stored)
        header.appendUInt16LE(0)          // mod time
        header.appendUInt16LE(0)          // mod date
        header.appendUInt32LE(0)          // crc32 (ignored for test)
        header.appendUInt32LE(UInt32(content.count)) // compressed size
        header.appendUInt32LE(UInt32(content.count)) // uncompressed size
        header.appendUInt16LE(UInt16(nameData.count)) // name length
        header.appendUInt16LE(0)          // extra length
        return header
    }

    private static func buildCentralDirectoryEntry(
        nameData: Data,
        content: Data,
        localHeaderOffset: UInt32
    ) -> Data {
        var entry = Data()
        entry.appendUInt32LE(0x02014b50) // signature
        entry.appendUInt16LE(20)         // version made by
        entry.appendUInt16LE(20)         // version needed
        entry.appendUInt16LE(0)          // flags
        entry.appendUInt16LE(0)          // compression
        entry.appendUInt16LE(0)          // mod time
        entry.appendUInt16LE(0)          // mod date
        entry.appendUInt32LE(0)          // crc32
        entry.appendUInt32LE(UInt32(content.count)) // compressed
        entry.appendUInt32LE(UInt32(content.count)) // uncompressed
        entry.appendUInt16LE(UInt16(nameData.count)) // name length
        entry.appendUInt16LE(0)          // extra length
        entry.appendUInt16LE(0)          // comment length
        entry.appendUInt16LE(0)          // disk number
        entry.appendUInt16LE(0)          // internal attributes
        entry.appendUInt32LE(0)          // external attributes
        entry.appendUInt32LE(localHeaderOffset)
        return entry
    }

    private static func buildEOCD(entryCount: UInt16, cdSize: UInt32, cdOffset: UInt32) -> Data {
        var eocd = Data()
        eocd.appendUInt32LE(0x06054b50) // signature
        eocd.appendUInt16LE(0)          // disk number
        eocd.appendUInt16LE(0)          // disk with CD
        eocd.appendUInt16LE(entryCount) // entries on disk
        eocd.appendUInt16LE(entryCount) // total entries
        eocd.appendUInt32LE(cdSize)     // CD size
        eocd.appendUInt32LE(cdOffset)   // CD offset
        eocd.appendUInt16LE(0)          // comment length
        return eocd
    }

    // MARK: - Tests

    @Test func readsStoredEntry() async throws {
        let content = Data("Hello, EPUB!".utf8)
        let zipURL = try Self.createTestZIP(fileName: "test.txt", content: content)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let reader = try ZIPReader(fileURL: zipURL)
        let entries = await reader.listEntries()

        #expect(entries.count == 1)
        #expect(entries[0].path == "test.txt")
        #expect(entries[0].uncompressedSize == UInt32(content.count))
        #expect(entries[0].compressionMethod == 0)

        let extracted = try await reader.extractData(for: entries[0])
        #expect(extracted == content)
    }

    @Test func extractsAllToDirectory() async throws {
        let content = Data("file content".utf8)
        let zipURL = try Self.createTestZIP(fileName: "subdir/file.txt", content: content)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-extract-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destDir) }

        let reader = try ZIPReader(fileURL: zipURL)
        try await reader.extractAll(to: destDir)

        let extractedURL = destDir.appendingPathComponent("subdir/file.txt")
        #expect(FileManager.default.fileExists(atPath: extractedURL.path))

        let extractedData = try Data(contentsOf: extractedURL)
        #expect(extractedData == content)
    }

    @Test func rejectsInvalidFile() throws {
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).zip")
        try Data("not a zip file".utf8).write(to: badURL)
        defer { try? FileManager.default.removeItem(at: badURL) }

        #expect(throws: ZIPError.self) {
            _ = try ZIPReader(fileURL: badURL)
        }
    }

    @Test func rejectsNonExistentFile() {
        let missingURL = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).zip")
        #expect(throws: (any Error).self) {
            _ = try ZIPReader(fileURL: missingURL)
        }
    }

    @Test func rejectsPathTraversal() async throws {
        let content = Data("malicious".utf8)
        let zipURL = try Self.createTestZIP(fileName: "../escape.txt", content: content)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-traverse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destDir) }

        let reader = try ZIPReader(fileURL: zipURL)
        do {
            try await reader.extractAll(to: destDir)
            Issue.record("Expected ZIPError.pathTraversal to be thrown")
        } catch is ZIPError {
            // Expected
        }
    }

    @Test func rejectsAbsolutePath() async throws {
        let content = Data("abs".utf8)
        let zipURL = try Self.createTestZIP(fileName: "/etc/passwd", content: content)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-abs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destDir) }

        let reader = try ZIPReader(fileURL: zipURL)
        do {
            try await reader.extractAll(to: destDir)
            Issue.record("Expected ZIPError.pathTraversal to be thrown")
        } catch is ZIPError {
            // Expected
        }
    }

    @Test func handlesEmptyContent() async throws {
        let content = Data()
        let zipURL = try Self.createTestZIP(fileName: "empty.txt", content: content)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let reader = try ZIPReader(fileURL: zipURL)
        let entries = await reader.listEntries()
        #expect(entries.count == 1)
        #expect(entries[0].uncompressedSize == 0)

        let extracted = try await reader.extractData(for: entries[0])
        #expect(extracted.isEmpty)
    }
}

// MARK: - Test Helpers

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
