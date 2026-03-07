// Purpose: Tests for EncodingDetector — BOM sniffing, UTF-8, NSString fallback,
// binary masquerade detection, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("EncodingDetector")
struct EncodingDetectorTests {

    // MARK: - BOM Detection

    @Test func detectsUTF8BOM() throws {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let content = "Hello UTF-8 BOM"
        let data = Data(bom) + content.data(using: .utf8)!

        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf8)
        #expect(result.text.contains("Hello UTF-8 BOM"))
        #expect(result.usedLossyConversion == false)
    }

    @Test func detectsUTF16LEBOM() throws {
        let bom: [UInt8] = [0xFF, 0xFE]
        let content = "Hello".data(using: .utf16LittleEndian)!
        let data = Data(bom) + content

        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf16LittleEndian)
        #expect(result.text.contains("Hello"))
    }

    @Test func detectsUTF16BEBOM() throws {
        let bom: [UInt8] = [0xFE, 0xFF]
        let content = "Hello".data(using: .utf16BigEndian)!
        let data = Data(bom) + content

        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf16BigEndian)
        #expect(result.text.contains("Hello"))
    }

    @Test func detectsUTF32LEBOM() throws {
        let bom: [UInt8] = [0xFF, 0xFE, 0x00, 0x00]
        // UTF-32 LE encoded "Hi"
        let content: [UInt8] = [
            0x48, 0x00, 0x00, 0x00,  // H
            0x69, 0x00, 0x00, 0x00,  // i
        ]
        let data = Data(bom) + Data(content)

        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf32LittleEndian)
        #expect(result.text.contains("Hi"))
    }

    @Test func detectsUTF32BEBOM() throws {
        let bom: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]
        let content: [UInt8] = [
            0x00, 0x00, 0x00, 0x48,  // H
            0x00, 0x00, 0x00, 0x69,  // i
        ]
        let data = Data(bom) + Data(content)

        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf32BigEndian)
        #expect(result.text.contains("Hi"))
    }

    // MARK: - UTF-8 Without BOM

    @Test func detectsPlainUTF8() throws {
        let data = "Hello, world! This is plain UTF-8.".data(using: .utf8)!
        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf8)
        #expect(result.text == "Hello, world! This is plain UTF-8.")
    }

    @Test func detectsUTF8WithMultibyteChars() throws {
        let data = "日本語テスト".data(using: .utf8)!
        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf8)
        #expect(result.text == "日本語テスト")
    }

    @Test func detectsUTF8Emoji() throws {
        let data = "Hello 🌍🎉".data(using: .utf8)!
        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf8)
        #expect(result.text.contains("🌍"))
    }

    // MARK: - Empty Data

    @Test func emptyDataSucceeds() throws {
        let data = Data()
        let result = try EncodingDetector.detect(data: data)
        #expect(result.text.isEmpty)
        #expect(result.encoding == .utf8)
    }

    // MARK: - Binary Masquerade Detection

    @Test func binaryFileRejected() {
        // Create data with >10% control bytes
        var bytes = [UInt8](repeating: 0x41, count: 100) // 'A'
        for i in 0..<15 {
            bytes[i] = 0x01 // SOH control byte
        }
        let data = Data(bytes)

        do {
            _ = try EncodingDetector.detect(data: data)
            Issue.record("Expected binaryMasquerade error")
        } catch let error as ImportError {
            #expect(error == .binaryMasquerade)
        } catch {
            Issue.record("Expected ImportError, got \(error)")
        }
    }

    @Test func binaryDetectionExcludesTabNewlineReturn() throws {
        // Tab, newline, return should NOT count as control bytes
        var bytes = [UInt8](repeating: 0x41, count: 100) // 'A'
        // Replace 15% with allowed control chars
        for i in 0..<5 { bytes[i] = 0x09 }  // tab
        for i in 5..<10 { bytes[i] = 0x0A } // newline
        for i in 10..<15 { bytes[i] = 0x0D } // return

        let data = Data(bytes)
        let result = try EncodingDetector.detect(data: data)
        #expect(!result.text.isEmpty)
    }

    @Test func binaryDetectionUsesFirst8KB() throws {
        // First 8KB is clean, rest has binary — should pass
        var data = Data(repeating: 0x41, count: 8192) // 8KB of 'A'
        data.append(Data(repeating: 0x01, count: 4096)) // 4KB binary after

        let result = try EncodingDetector.detect(data: data)
        #expect(!result.text.isEmpty)
    }

    @Test func exactlyAtThresholdPasses() {
        // 100 bytes, 10 control bytes = exactly 10%.
        // Threshold is strictly >10%, so exactly 10% should pass.
        var bytes = [UInt8](repeating: 0x41, count: 100)
        for i in 0..<10 {
            bytes[i] = 0x01
        }
        let data = Data(bytes)

        let result = try? EncodingDetector.detect(data: data)
        #expect(result != nil, "Exactly 10% control bytes should not trigger binary rejection (threshold is >10%)")
    }

    @Test func justAboveThreshold() {
        // 100 bytes, 11 control bytes = 11%, should reject
        var bytes = [UInt8](repeating: 0x41, count: 100)
        for i in 0..<11 {
            bytes[i] = 0x01
        }
        let data = Data(bytes)

        do {
            _ = try EncodingDetector.detect(data: data)
            Issue.record("Expected binaryMasquerade error")
        } catch let error as ImportError {
            #expect(error == .binaryMasquerade)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - NSString Fallback Encodings

    @Test func detectsLatin1() throws {
        // ISO Latin 1 encoded text with characters outside UTF-8
        // "café" in Latin-1: 63 61 66 E9
        let data = Data([0x63, 0x61, 0x66, 0xE9])
        let result = try EncodingDetector.detect(data: data)
        #expect(result.text.contains("caf"), "Expected decoded text to contain 'caf'")
        // The encoding should be a Latin-1 family encoding
        let acceptedEncodings: Set<String.Encoding> = [.isoLatin1, .windowsCP1252]
        #expect(
            acceptedEncodings.contains(result.encoding),
            "Expected Latin-1 family encoding, got \(EncodingDetector.encodingName(result.encoding))"
        )
    }

    @Test func detectsWindowsCP1252() throws {
        // Windows-1252 "smart quotes" — 0x93 0x94 are left/right double quotes
        let data = Data([0x93, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x94])
        let result = try EncodingDetector.detect(data: data)
        #expect(result.text.contains("Hello"))
    }

    // MARK: - Lossy Fallback

    @Test func invalidUTF8BytesHandledGracefully() throws {
        // 0x80 bytes are invalid UTF-8 (bare continuation bytes) but valid
        // in CP1252 (Euro sign) and ISO Latin 1. The pipeline correctly
        // decodes them via NSString heuristic or CP1252 fallback — the lossy
        // UTF-8 fallback is unreachable because ISO Latin 1 maps all 256 bytes.
        let data = Data([0x80, 0x80, 0x80, 0x80, 0x80])
        let result = try EncodingDetector.detect(data: data)
        // Must succeed (no throw) and produce non-empty text
        #expect(!result.text.isEmpty, "Pipeline should decode invalid-UTF-8 bytes via fallback encoding")
        // Encoding should NOT be UTF-8 (since strict UTF-8 rejects 0x80)
        #expect(result.encoding != .utf8, "Expected a non-UTF-8 fallback encoding for bare 0x80 bytes")
    }

    // MARK: - BOM Prioritized Over Binary Check

    @Test func utf16LEWithNullBytesNotRejectedAsBinary() throws {
        // UTF-16 LE text contains 0x00 bytes which would trip binary check.
        // BOM detection must run first to correctly identify the encoding.
        let bom: [UInt8] = [0xFF, 0xFE]
        let text = String(repeating: "A", count: 100)
        let content = text.data(using: .utf16LittleEndian)!
        let data = Data(bom) + content

        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf16LittleEndian)
        #expect(result.text.contains("A"))
    }

    @Test func utf32BEWithNullBytesNotRejectedAsBinary() throws {
        // UTF-32 BE has three 0x00 bytes per ASCII char — would be ~75% "control bytes"
        let bom: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]
        let content: [UInt8] = [
            0x00, 0x00, 0x00, 0x48,  // H
            0x00, 0x00, 0x00, 0x65,  // e
            0x00, 0x00, 0x00, 0x6C,  // l
            0x00, 0x00, 0x00, 0x6C,  // l
            0x00, 0x00, 0x00, 0x6F,  // o
        ]
        let data = Data(bom) + Data(content)

        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf32BigEndian)
        #expect(result.text == "Hello")
    }

    // MARK: - Whitespace-Only Content

    @Test func whitespaceOnlySucceeds() throws {
        let data = "   \n\t\r\n  ".data(using: .utf8)!
        let result = try EncodingDetector.detect(data: data)
        #expect(!result.text.isEmpty)
        #expect(result.encoding == .utf8)
    }

    // MARK: - Encoding Name

    @Test func encodingNameForUTF8() throws {
        let data = "hello".data(using: .utf8)!
        let result = try EncodingDetector.detect(data: data)
        let name = EncodingDetector.encodingName(result.encoding)
        #expect(name == "utf-8")
    }

    @Test func encodingNameForUTF16LE() throws {
        let bom: [UInt8] = [0xFF, 0xFE]
        let content = "Hi".data(using: .utf16LittleEndian)!
        let data = Data(bom) + content
        let result = try EncodingDetector.detect(data: data)
        let name = EncodingDetector.encodingName(result.encoding)
        #expect(name == "utf-16le")
    }

    // MARK: - GBK / CJK Encoding Detection

    @Test func detectsGBKEncodedChinese() throws {
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        // "你好世界" (Hello World) encoded in GBK/GB18030
        let chineseText = "你好世界"
        guard let data = chineseText.data(using: gbkEncoding) else {
            Issue.record("Could not encode test string as GBK")
            return
        }

        let result = try EncodingDetector.detect(data: data)
        #expect(
            result.text.contains("你好世界"),
            "Expected decoded text to contain '你好世界', got: \(result.text.prefix(50))"
        )
    }

    @Test func detectsGBKWithMixedContent() throws {
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        // Mixed ASCII + Chinese in GBK
        let text = "Chapter 1: 第一章 引言\n\n这是一本关于编程的书。\n\nHello World 你好世界"
        guard let data = text.data(using: gbkEncoding) else {
            Issue.record("Could not encode test string as GBK")
            return
        }

        let result = try EncodingDetector.detect(data: data)
        #expect(result.text.contains("第一章"), "Expected decoded text to contain '第一章'")
        #expect(result.text.contains("编程"), "Expected decoded text to contain '编程'")
        #expect(result.text.contains("Chapter 1"), "Expected decoded text to contain ASCII content")
    }
}
