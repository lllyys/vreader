// Purpose: Minimal read-only ZIP file reader using Compression framework.
// Extracts entries from ZIP archives (including .epub files) without
// external dependencies.
//
// Key decisions:
// - Uses Compression framework's COMPRESSION_ZLIB for DEFLATE decompression.
// - Reads entire file into memory (suitable for typical EPUB sizes <100MB).
// - Supports Stored (method 0) and Deflated (method 8) entries.
// - Validates entry paths to prevent zip-slip directory traversal attacks.
// - Uses iterative buffer growth for DEFLATE to handle size mismatches.
// - Actor-isolated for thread safety.
//
// @coordinates-with: EPUBParser.swift

import Foundation
import Compression

// MARK: - Types

/// A single entry in a ZIP archive.
struct ZIPEntry: Sendable {
    /// Relative path within the archive.
    let path: String
    /// Uncompressed size in bytes.
    let uncompressedSize: UInt32
    /// Compressed size in bytes.
    let compressedSize: UInt32
    /// Compression method (0 = stored, 8 = deflated).
    let compressionMethod: UInt16
    /// Byte offset of the entry's data within the archive.
    let dataOffset: UInt64

    /// Whether this entry represents a directory.
    var isDirectory: Bool { path.hasSuffix("/") }
}

/// Errors from ZIP reading operations.
enum ZIPError: Error, Sendable {
    case invalidArchive(String)
    case unsupportedCompressionMethod(UInt16)
    case decompressionFailed
    case entryNotFound(String)
    case pathTraversal(String)
    case invalidEntryName
}

// MARK: - Reader

/// Reads entries from a ZIP archive file.
actor ZIPReader {
    private let data: Data
    private let entries: [ZIPEntry]

    /// Opens a ZIP archive at the given URL.
    init(fileURL: URL) throws {
        self.data = try Data(contentsOf: fileURL)
        self.entries = try Self.parseEntries(data)
    }

    /// Returns all entries in the archive.
    func listEntries() -> [ZIPEntry] { entries }

    /// Extracts the data for a single entry.
    func extractData(for entry: ZIPEntry) throws -> Data {
        let start = Int(entry.dataOffset)
        let end = start + Int(entry.compressedSize)
        guard end <= data.count else {
            throw ZIPError.invalidArchive("Entry data extends beyond archive bounds")
        }
        let rawData = data[start..<end]

        switch entry.compressionMethod {
        case 0: // Stored
            return Data(rawData)
        case 8: // Deflated
            return try Self.inflate(Data(rawData), expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZIPError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    /// Extracts all entries to the given directory.
    /// Validates paths to prevent zip-slip directory traversal.
    func extractAll(to directory: URL) throws {
        let fm = FileManager.default
        let canonicalRoot = directory.standardizedFileURL.path

        for entry in entries {
            // Validate: reject absolute paths and path traversal
            guard !entry.path.isEmpty else { continue }
            try Self.validateEntryPath(entry.path)

            let dest = directory.appendingPathComponent(entry.path).standardizedFileURL
            guard dest.path.hasPrefix(canonicalRoot) else {
                throw ZIPError.pathTraversal(entry.path)
            }

            if entry.isDirectory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let entryData = try extractData(for: entry)
                try entryData.write(to: dest)
            }
        }
    }

    // MARK: - Path Validation

    /// Rejects paths that could escape the extraction root.
    private static func validateEntryPath(_ path: String) throws {
        // Reject absolute paths
        if path.hasPrefix("/") || path.hasPrefix("\\") {
            throw ZIPError.pathTraversal(path)
        }
        // Reject parent directory traversal components
        let components = path.components(separatedBy: "/")
        for component in components {
            if component == ".." {
                throw ZIPError.pathTraversal(path)
            }
        }
    }

    // MARK: - ZIP Format Parsing

    private static func parseEntries(_ data: Data) throws -> [ZIPEntry] {
        guard let eocdOffset = findEOCD(in: data) else {
            throw ZIPError.invalidArchive("Cannot find End of Central Directory")
        }

        let cdOffset = Int(data.readUInt32LE(at: eocdOffset + 16))
        let cdEntryCount = Int(data.readUInt16LE(at: eocdOffset + 10))

        // Guard against ZIP64 archives (unsupported)
        if cdEntryCount == 0xFFFF || cdOffset == 0xFFFFFFFF {
            throw ZIPError.invalidArchive("ZIP64 archives are not supported")
        }

        var entries: [ZIPEntry] = []
        entries.reserveCapacity(cdEntryCount)
        var offset = cdOffset

        for _ in 0..<cdEntryCount {
            guard offset + 46 <= data.count,
                  data.readUInt32LE(at: offset) == 0x02014b50 else {
                throw ZIPError.invalidArchive("Invalid Central Directory entry")
            }

            let compressionMethod = data.readUInt16LE(at: offset + 10)
            let compressedSize = data.readUInt32LE(at: offset + 20)
            let uncompressedSize = data.readUInt32LE(at: offset + 24)
            let nameLength = Int(data.readUInt16LE(at: offset + 28))
            let extraLength = Int(data.readUInt16LE(at: offset + 30))
            let commentLength = Int(data.readUInt16LE(at: offset + 32))
            let localHeaderOffset = Int(data.readUInt32LE(at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else {
                throw ZIPError.invalidArchive("Entry name extends beyond archive")
            }
            let nameData = data[nameStart..<(nameStart + nameLength)]
            guard let path = String(data: Data(nameData), encoding: .utf8), !path.isEmpty else {
                throw ZIPError.invalidEntryName
            }

            // Validate Local File Header signature
            guard localHeaderOffset + 30 <= data.count,
                  data.readUInt32LE(at: localHeaderOffset) == 0x04034b50 else {
                throw ZIPError.invalidArchive("Invalid Local File Header at offset \(localHeaderOffset)")
            }
            let localNameLen = Int(data.readUInt16LE(at: localHeaderOffset + 26))
            let localExtraLen = Int(data.readUInt16LE(at: localHeaderOffset + 28))
            let dataOffset = UInt64(localHeaderOffset + 30 + localNameLen + localExtraLen)

            entries.append(ZIPEntry(
                path: path,
                uncompressedSize: uncompressedSize,
                compressedSize: compressedSize,
                compressionMethod: compressionMethod,
                dataOffset: dataOffset
            ))

            offset += 46 + nameLength + extraLength + commentLength
        }

        return entries
    }

    /// Searches backwards for the End of Central Directory signature (0x06054b50).
    private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let maxSearch = min(data.count, 65536 + 22)
        let start = max(0, data.count - maxSearch)
        for i in stride(from: data.count - 22, through: start, by: -1) {
            if data[i] == 0x50 && data[i + 1] == 0x4b
                && data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                return i
            }
        }
        return nil
    }

    /// Decompresses DEFLATE data using the Compression framework.
    /// Uses iterative buffer growth to handle entries where expectedSize is inaccurate.
    private static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }

        // Try with expected size first, then grow iteratively
        var bufferSize = max(expectedSize * 2, 4096)
        let maxBufferSize = 256 * 1024 * 1024 // 256 MB safety limit

        while bufferSize <= maxBufferSize {
            var decompressed = Data(count: bufferSize)
            let result = decompressed.withUnsafeMutableBytes { destPtr in
                compressed.withUnsafeBytes { srcPtr in
                    compression_decode_buffer(
                        destPtr.bindMemory(to: UInt8.self).baseAddress!,
                        bufferSize,
                        srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                        compressed.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            guard result > 0 else {
                throw ZIPError.decompressionFailed
            }
            if result < bufferSize {
                // Decompression complete — output fit in buffer
                decompressed.count = result
                return decompressed
            }
            // Buffer was exactly filled — might be truncated, try larger
            bufferSize *= 2
        }
        throw ZIPError.decompressionFailed
    }
}

// MARK: - Data Helpers

private extension Data {
    /// Reads a little-endian UInt16 at the given byte offset.
    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    /// Reads a little-endian UInt32 at the given byte offset.
    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
        | UInt32(self[offset + 1]) << 8
        | UInt32(self[offset + 2]) << 16
        | UInt32(self[offset + 3]) << 24
    }
}
