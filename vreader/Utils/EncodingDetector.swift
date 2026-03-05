// Purpose: TXT encoding detection pipeline (Section 9.5).
// Pipeline: BOM sniff -> binary masquerade -> strict UTF-8 -> NSString heuristic -> CP1252 -> lossy UTF-8.
//
// Key decisions:
// - BOM detection runs BEFORE binary masquerade check, because UTF-16/32
//   files contain 0x00 bytes that would trip the binary heuristic.
// - Binary masquerade check only runs on non-BOM files.
// - NSString.stringEncoding(for:) uses Apple's ICU-backed heuristics.
// - Final fallback is lossy UTF-8 with U+FFFD replacement characters.
//
// @coordinates-with: BookImporter.swift, ImportError.swift

import Foundation

/// Result of encoding detection for a text file.
struct EncodingResult: Sendable {
    /// Decoded text content.
    let text: String

    /// Detected encoding.
    let encoding: String.Encoding

    /// Whether lossy conversion was used (some characters may be U+FFFD).
    let usedLossyConversion: Bool
}

/// Detects text file encoding using a multi-stage pipeline.
enum EncodingDetector {

    /// Maximum bytes to examine for binary masquerade detection.
    private static let binaryCheckSize = 8192

    /// Control byte threshold (fraction). Files with >10% control bytes are rejected.
    private static let binaryThreshold: Double = 0.10

    /// Suggested encodings for NSString heuristic, in priority order.
    private static let suggestedEncodings: [String.Encoding] = [
        .windowsCP1252,
        .isoLatin1,
        .shiftJIS,
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))),
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
    ]

    /// Detects encoding and decodes the given data.
    ///
    /// - Parameter data: Raw file bytes.
    /// - Returns: An `EncodingResult` with decoded text and detected encoding.
    /// - Throws: `ImportError.binaryMasquerade` if the data appears to be binary.
    static func detect(data: Data) throws -> EncodingResult {
        // Empty data is trivially UTF-8
        if data.isEmpty {
            return EncodingResult(text: "", encoding: .utf8, usedLossyConversion: false)
        }

        // Step 1: BOM sniff (must run BEFORE binary check — UTF-16/32 contain 0x00 bytes)
        if let result = detectByBOM(data: data) {
            return result
        }

        // Step 2: Binary masquerade check (only for non-BOM files)
        try checkBinaryMasquerade(data: data)

        // Step 3: Strict UTF-8
        if let text = String(data: data, encoding: .utf8) {
            return EncodingResult(text: text, encoding: .utf8, usedLossyConversion: false)
        }

        // Step 4: NSString heuristic with suggested encodings
        if let result = detectByNSString(data: data) {
            return result
        }

        // Step 5: Fallback to Windows CP1252
        if let text = String(data: data, encoding: .windowsCP1252) {
            return EncodingResult(text: text, encoding: .windowsCP1252, usedLossyConversion: false)
        }

        // Step 6: Final fallback — lossy UTF-8 with replacement character
        let text = String(decoding: data, as: UTF8.self)
        return EncodingResult(text: text, encoding: .utf8, usedLossyConversion: true)
    }

    /// Returns a human-readable encoding name for storage in metadata.
    static func encodingName(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "utf-8"
        case .utf16LittleEndian: return "utf-16le"
        case .utf16BigEndian: return "utf-16be"
        case .utf32LittleEndian: return "utf-32le"
        case .utf32BigEndian: return "utf-32be"
        case .windowsCP1252: return "windows-1252"
        case .isoLatin1: return "iso-8859-1"
        case .shiftJIS: return "shift_jis"
        default:
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
            if let name = CFStringConvertEncodingToIANACharSetName(cfEncoding) {
                return (name as String).lowercased()
            }
            return "x-unknown" // Unknown encoding; downstream should treat as binary-safe
        }
    }

    // MARK: - Private

    /// Checks if data appears to be a binary file masquerading as text.
    /// Examines first 8KB, counting control bytes (excluding \t \n \r).
    /// Throws `.binaryMasquerade` if >10% of bytes are control characters.
    private static func checkBinaryMasquerade(data: Data) throws {
        let checkSize = min(data.count, binaryCheckSize)
        guard checkSize > 0 else { return }

        let slice = data.prefix(checkSize)
        var controlCount = 0

        for byte in slice {
            // Control bytes: 0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F, 0x7F
            // Excluded: \t (0x09), \n (0x0A), \r (0x0D)
            if byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
                controlCount += 1
            } else if byte == 0x7F {
                controlCount += 1
            }
        }

        let ratio = Double(controlCount) / Double(checkSize)
        if ratio > binaryThreshold {
            throw ImportError.binaryMasquerade
        }
    }

    /// Attempts BOM-based encoding detection.
    /// Uses Data subscript/slicing to minimize allocations.
    private static func detectByBOM(data: Data) -> EncodingResult? {
        guard data.count >= 2 else { return nil }

        let bytes = [UInt8](data.prefix(4))

        // UTF-32 LE BOM: FF FE 00 00 (must check before UTF-16 LE)
        if bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE
            && bytes[2] == 0x00 && bytes[3] == 0x00 {
            if let text = String(data: data.dropFirst(4), encoding: .utf32LittleEndian) {
                return EncodingResult(text: text, encoding: .utf32LittleEndian, usedLossyConversion: false)
            }
        }

        // UTF-32 BE BOM: 00 00 FE FF
        if bytes.count >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00
            && bytes[2] == 0xFE && bytes[3] == 0xFF {
            if let text = String(data: data.dropFirst(4), encoding: .utf32BigEndian) {
                return EncodingResult(text: text, encoding: .utf32BigEndian, usedLossyConversion: false)
            }
        }

        // UTF-8 BOM: EF BB BF
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB
            && bytes[2] == 0xBF {
            if let text = String(data: data.dropFirst(3), encoding: .utf8) {
                return EncodingResult(text: text, encoding: .utf8, usedLossyConversion: false)
            }
        }

        // UTF-16 LE BOM: FF FE
        if bytes[0] == 0xFF && bytes[1] == 0xFE {
            if let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
                return EncodingResult(text: text, encoding: .utf16LittleEndian, usedLossyConversion: false)
            }
        }

        // UTF-16 BE BOM: FE FF
        if bytes[0] == 0xFE && bytes[1] == 0xFF {
            if let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
                return EncodingResult(text: text, encoding: .utf16BigEndian, usedLossyConversion: false)
            }
        }

        return nil
    }

    /// Uses NSString's encoding detection heuristic with suggested encodings.
    private static func detectByNSString(data: Data) -> EncodingResult? {
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false

        let encodingOptions: [StringEncodingDetectionOptionsKey: Any] = [
            .suggestedEncodingsKey: suggestedEncodings.map { NSNumber(value: $0.rawValue) },
            .useOnlySuggestedEncodingsKey: false,
            .allowLossyKey: false,
        ]

        let detectedRawValue = NSString.stringEncoding(
            for: data,
            encodingOptions: encodingOptions,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )

        guard detectedRawValue != 0,
              let text = convertedString as? String else {
            return nil
        }

        let encoding = String.Encoding(rawValue: detectedRawValue)
        return EncodingResult(
            text: text,
            encoding: encoding,
            usedLossyConversion: usedLossyConversion.boolValue
        )
    }
}
