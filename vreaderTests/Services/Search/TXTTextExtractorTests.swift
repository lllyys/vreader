// Purpose: Tests for TXTTextExtractor — URL-based extraction with encoding
// detection, segment generation, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("TXTTextExtractor")
struct TXTTextExtractorTests {

    // MARK: - URL-based extraction with encoding detection

    @Test func extractWithOffsetsFromUTF8File() async throws {
        let text = "Hello world.\n\nSecond paragraph."
        let url = try writeTempFile(text, encoding: .utf8, ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = TXTTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)

        #expect(!result.textUnits.isEmpty)
        #expect(result.textUnits[0].text.contains("Hello world"))
    }

    @Test func extractWithOffsetsFromUTF16LEFile() async throws {
        let text = "UTF-16 encoded text.\n\nAnother paragraph."
        let url = try writeTempFile(text, encoding: .utf16LittleEndian, ext: "txt", addBOM: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = TXTTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)

        #expect(!result.textUnits.isEmpty)
        #expect(result.textUnits[0].text.contains("UTF-16"))
    }

    @Test func extractWithOffsetsFromLatin1File() async throws {
        // True Latin-1 bytes: "Café résumé" with 0xE9 for é (not UTF-8 multi-byte)
        let bytes: [UInt8] = [
            0x43, 0x61, 0x66, 0xE9,       // Café
            0x20,                           // space
            0x72, 0xE9, 0x73, 0x75, 0x6D, 0xE9  // résumé
        ]
        let url = try writeTempBytes(bytes, ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = TXTTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)
        #expect(!result.textUnits.isEmpty)
        let allText = result.textUnits.map(\.text).joined(separator: " ")
        #expect(allText.contains("Caf"), "Should decode Latin-1 accented text")
    }

    @Test func extractWithOffsetsFromEmptyFile() async throws {
        let url = try writeTempFile("", encoding: .utf8, ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = TXTTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)
        #expect(result.textUnits.isEmpty)
        #expect(result.segmentBaseOffsets.isEmpty)
    }

    // MARK: - GBK encoding

    @Test func extractWithOffsetsFromGBKFile() async throws {
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let chineseText = "第一章 引言\n\n这是一本关于编程的书。\n\n你好世界"
        guard let encoded = chineseText.data(using: gbkEncoding) else {
            Issue.record("Could not encode test string as GBK")
            return
        }
        let url = try writeTempBytes(Array(encoded), ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = TXTTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)

        #expect(!result.textUnits.isEmpty, "Expected non-empty text units for GBK file")
        let allText = result.textUnits.map(\.text).joined(separator: " ")
        #expect(allText.contains("编程"), "Expected decoded Chinese text, got: \(allText.prefix(80))")
        #expect(allText.contains("你好世界"), "Expected decoded Chinese text")
    }

    // MARK: - GBK large content

    @Test func extractWithOffsetsFromGBKLargeContent() async throws {
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let paragraph1 = "第一章 引言"
        let paragraph2 = "人工智能是计算机科学的一个重要分支，它致力于创造能够模拟人类智能的系统。"
        let paragraph3 = "自然语言处理是其中一个关键领域，涉及文本分析、机器翻译和信息检索等任务。"
        let paragraph4 = "深度学习技术的发展极大地推动了这些领域的进步。"
        let chineseText = [paragraph1, paragraph2, paragraph3, paragraph4].joined(separator: "\n\n")

        guard let encoded = chineseText.data(using: gbkEncoding) else {
            Issue.record("Could not encode multi-paragraph Chinese text as GBK")
            return
        }
        let url = try writeTempBytes(Array(encoded), ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = TXTTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)

        #expect(result.textUnits.count >= 3, "Expected at least 3 segments for 4 paragraphs, got \(result.textUnits.count)")

        let allText = result.textUnits.map(\.text).joined(separator: " ")
        #expect(allText.contains("人工智能"), "Should contain '人工智能' after GBK decoding")
        #expect(allText.contains("自然语言处理"), "Should contain '自然语言处理' after GBK decoding")
        #expect(allText.contains("深度学习"), "Should contain '深度学习' after GBK decoding")

        // Verify no garbled text — each segment should contain only valid Chinese characters
        for unit in result.textUnits {
            let hasValidChinese = unit.text.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value)
            }
            #expect(hasValidChinese, "Segment '\(unit.sourceUnitId)' should contain CJK characters, got: \(unit.text.prefix(40))")
        }
    }

    // MARK: - Big5 encoding

    @Test func extractWithOffsetsFromBig5File() async throws {
        let big5Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )
        )
        let traditionalChinese = "第一章 緒論\n\n這是一本關於程式設計的書。\n\n歡迎來到世界"

        guard let encoded = traditionalChinese.data(using: big5Encoding) else {
            Issue.record("Could not encode Traditional Chinese text as Big5")
            return
        }
        let url = try writeTempBytes(Array(encoded), ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = TXTTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)

        #expect(!result.textUnits.isEmpty, "Expected non-empty text units for Big5 file")

        let allText = result.textUnits.map(\.text).joined(separator: " ")
        #expect(allText.contains("程式設計"), "Expected decoded Traditional Chinese '程式設計', got: \(allText.prefix(80))")
        #expect(allText.contains("歡迎"), "Expected decoded Traditional Chinese '歡迎'")
    }

    // MARK: - Helpers

    private func writeTempFile(
        _ content: String,
        encoding: String.Encoding,
        ext: String,
        addBOM: Bool = false
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).\(ext)")
        var data = Data()
        if addBOM && (encoding == .utf16LittleEndian || encoding == .utf16BigEndian) {
            // Add BOM for UTF-16
            if encoding == .utf16LittleEndian {
                data.append(contentsOf: [0xFF, 0xFE])
            } else {
                data.append(contentsOf: [0xFE, 0xFF])
            }
        }
        if let encoded = content.data(using: encoding) {
            data.append(encoded)
        }
        try data.write(to: url)
        return url
    }

    private func writeTempBytes(_ bytes: [UInt8], ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).\(ext)")
        try Data(bytes).write(to: url)
        return url
    }
}
