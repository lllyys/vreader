// Purpose: Production implementation of TXTServiceProtocol.
// Reads a TXT file, detects encoding, and returns metadata + content.
//
// Key decisions:
// - Actor-isolated for thread safety.
// - Uses NSString heuristic detection first (handles CJK, BOM, etc.).
// - Falls back to manual encoding attempts in safe order.
// - Catch-all encodings (ISO-8859-1, CP1252) tried last — they match any byte sequence.
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

        // Use mappedIfSafe to avoid copying entire file into heap memory
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

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
            totalWordCount: Self.countWords(text)
        )
    }

    func close() async {
        _isOpen = false
    }

    // MARK: - Encoding Detection

    /// Detects encoding and decodes text data.
    ///
    /// Strategy:
    /// 1. UTF-8 (most common, BOM-aware via Foundation).
    /// 2. NSString heuristic detection (handles GBK, Big5, Shift_JIS, etc.).
    /// 3. Manual fallback list with CJK encodings before catch-all single-byte encodings.
    /// 4. ISO-8859-1 last — it accepts any byte sequence and acts as a catch-all.
    static func decodeText(_ data: Data) -> (String, String)? {
        // Empty data is valid UTF-8
        if data.isEmpty {
            return ("", "UTF-8")
        }

        // 1. Try UTF-8 first (fast path, handles BOM)
        if let text = String(data: data, encoding: .utf8) {
            return (text, "UTF-8")
        }

        // 2. Try UTF-16 only if BOM is present (avoid false positives on arbitrary data)
        if data.count >= 2 {
            let bom = (UInt16(data[0]) << 8) | UInt16(data[1])
            if bom == 0xFEFF || bom == 0xFFFE {
                if let text = String(data: data, encoding: .utf16) {
                    return (text, "UTF-16")
                }
            }
        }

        // 3. Use NSString heuristic detection
        if let (text, name) = detectWithNSString(data) {
            return (text, name)
        }

        // 4. Manual fallback: CJK encodings first, then catch-all single-byte last
        let fallbacks: [(String.Encoding, String)] = [
            (gbkEncoding, "GBK"),
            (big5Encoding, "Big5"),
            (.japaneseEUC, "EUC-JP"),
            (.shiftJIS, "Shift_JIS"),
            (eucKREncoding, "EUC-KR"),
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO-8859-1"),  // catch-all — must be last
        ]
        for (encoding, name) in fallbacks {
            if let text = String(data: data, encoding: encoding) {
                return (text, name)
            }
        }

        return nil
    }

    // MARK: - NSString Heuristic Detection

    /// Uses NSString's built-in encoding detection heuristics.
    /// This handles GBK, Big5, Shift_JIS, EUC-KR, and many others.
    private static func detectWithNSString(_ data: Data) -> (String, String)? {
        var usedLossyConversion: ObjCBool = false
        let detectedRaw = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: [
                    String.Encoding.utf8.rawValue,
                    gbkEncoding.rawValue,
                    big5Encoding.rawValue,
                    String.Encoding.japaneseEUC.rawValue,
                    String.Encoding.shiftJIS.rawValue,
                    eucKREncoding.rawValue,
                    String.Encoding.windowsCP1252.rawValue,
                    String.Encoding.isoLatin1.rawValue,
                ],
                .allowLossyKey: false,
            ],
            convertedString: nil,
            usedLossyConversion: &usedLossyConversion
        )
        let detected = String.Encoding(rawValue: detectedRaw)

        // Skip if lossy or if it fell through to a catch-all
        guard !usedLossyConversion.boolValue, detectedRaw != 0 else { return nil }

        if let text = String(data: data, encoding: detected) {
            let name = encodingName(detected)
            return (text, name)
        }
        return nil
    }

    // MARK: - Encoding Constants

    /// GBK / GB18030 encoding (covers GB2312 as a subset).
    private static let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    /// Big5 encoding (Traditional Chinese).
    private static let big5Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )

    /// EUC-KR encoding (Korean).
    private static let eucKREncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
    )

    /// Counts words without allocating split substrings. O(n) single pass.
    private static func countWords(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for char in text {
            if char.isWhitespace || char.isNewline {
                inWord = false
            } else if !inWord {
                count += 1
                inWord = true
            }
        }
        return count
    }

    /// Maps a String.Encoding to a human-readable name.
    private static func encodingName(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .isoLatin1: return "ISO-8859-1"
        case .windowsCP1252: return "Windows-1252"
        case .japaneseEUC: return "EUC-JP"
        case .shiftJIS: return "Shift_JIS"
        case gbkEncoding: return "GBK"
        case big5Encoding: return "Big5"
        case eucKREncoding: return "EUC-KR"
        default:
            let cfEnc = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
            if cfEnc != kCFStringEncodingInvalidId,
               let cfName = CFStringConvertEncodingToIANACharSetName(cfEnc) {
                return cfName as String
            }
            return "Unknown"
        }
    }
}
