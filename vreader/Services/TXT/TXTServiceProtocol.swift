// Purpose: Protocol for TXT file loading, encoding detection, and content access.
// Decouples the reader ViewModel from file I/O for testability.
//
// Key decisions:
// - Async throws for all I/O operations.
// - Sendable for safe cross-actor usage.
// - Returns decoded string content and metadata (byte count, encoding).
// - open/close lifecycle mirrors EPUBParserProtocol pattern.
// - totalWordCount and totalTextLengthUTF16 provided for wordsRead estimation.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTChunkedLoader.swift, TXTOffsetMapper.swift

import Foundation

/// Errors that can occur during TXT file loading.
enum TXTServiceError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case encodingDetectionFailed(String)
    case decodingFailed(String)
    case notOpen
    case alreadyOpen
}

/// Metadata about a loaded TXT file.
struct TXTFileMetadata: Sendable, Equatable {
    /// The decoded full text content.
    let text: String
    /// Total byte count of the source file.
    let fileByteCount: Int64
    /// Detected or specified encoding name (e.g., "UTF-8", "Shift_JIS").
    let detectedEncoding: String
    /// Total text length in UTF-16 code units.
    let totalTextLengthUTF16: Int
    /// Total word count (whitespace-split, locale-independent).
    let totalWordCount: Int
}

/// Protocol for TXT file loading operations.
/// In production, backed by file I/O + encoding detection. In tests, backed by a mock.
protocol TXTServiceProtocol: Sendable {
    /// Opens and decodes a TXT file at the given URL.
    func open(url: URL) async throws -> TXTFileMetadata

    /// Closes the currently open file and releases resources.
    func close() async

    /// Whether a file is currently open.
    var isOpen: Bool { get async }
}
