// Purpose: Production implementation of TXTServiceProtocol.
// Reads a TXT file, detects encoding, and returns metadata + content.
//
// Key decisions:
// - Actor-isolated for thread safety.
// - Tries UTF-8 first, then common fallback encodings.
// - Word count uses whitespace splitting (locale-independent).
//
// @coordinates-with: TXTServiceProtocol.swift, TXTReaderViewModel.swift

import Foundation

/// Production TXT file loader.
actor TXTService: TXTServiceProtocol {
    private var _isOpen = false

    var isOpen: Bool { _isOpen }

    func open(url: URL) async throws -> TXTFileMetadata {
        guard !_isOpen else { throw TXTServiceError.alreadyOpen }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TXTServiceError.fileNotFound(url.lastPathComponent)
        }

        let data = try Data(contentsOf: url)

        guard let (text, encoding) = Self.decodeText(data) else {
            throw TXTServiceError.decodingFailed(
                "Could not decode the file with any supported encoding"
            )
        }

        _isOpen = true

        return TXTFileMetadata(
            text: text,
            fileByteCount: Int64(data.count),
            detectedEncoding: encoding,
            totalTextLengthUTF16: text.utf16.count,
            totalWordCount: text.split(whereSeparator: \.isWhitespace).count
        )
    }

    func close() async {
        _isOpen = false
    }

    // MARK: - Private

    /// Tries common encodings in priority order. Returns decoded text and encoding name.
    private static func decodeText(_ data: Data) -> (String, String)? {
        let encodings: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16, "UTF-16"),
            (.isoLatin1, "ISO-8859-1"),
            (.windowsCP1252, "Windows-1252"),
            (.japaneseEUC, "EUC-JP"),
            (.shiftJIS, "Shift_JIS"),
        ]
        for (encoding, name) in encodings {
            if let text = String(data: data, encoding: encoding) {
                return (text, name)
            }
        }
        return nil
    }
}
