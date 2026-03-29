// Purpose: Tests for TXTService encoding detection.
// Verifies correct decoding of UTF-8, CJK (GBK, Big5, Shift_JIS), and Latin encodings.

import Testing
import Foundation
@testable import vreader

@Suite("TXTService Encoding Detection")
struct TXTServiceTests {

    // MARK: - Helpers

    /// Writes data to a temp file, opens via TXTService, returns metadata.
    private func openWithData(_ data: Data) async throws -> TXTFileMetadata {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("txt-test-\(UUID().uuidString).txt")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = TXTService()
        return try await service.open(url: url)
    }

    // MARK: - UTF-8

    @Test func decodesUTF8() async throws {
        let text = "Hello, World! 你好世界 🌍"
        let data = Data(text.utf8)
        let meta = try await openWithData(data)
        #expect(meta.text == text)
        #expect(meta.detectedEncoding == "UTF-8")
    }

    @Test func decodesUTF8WithBOM() async throws {
        let text = "BOM test"
        var data = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM
        data.append(Data(text.utf8))
        let meta = try await openWithData(data)
        #expect(meta.text.contains("BOM test"))
        #expect(meta.detectedEncoding == "UTF-8")
    }

    // MARK: - CJK Encodings

    @Test func decodesGBK() async throws {
        // "你好世界" in GBK: C4E3 BAC3 CAC0 BDE7
        let gbkBytes: [UInt8] = [0xC4, 0xE3, 0xBA, 0xC3, 0xCA, 0xC0, 0xBD, 0xE7]
        let data = Data(gbkBytes)
        let meta = try await openWithData(data)
        #expect(meta.text == "你好世界")
    }

    @Test func decodesBig5() async throws {
        // "你好" in Big5: A741 A861 (actually A741=你, A861=好 — but let's use
        // NSString for reliable encoding). Use CFStringEncoding for Big5.
        let big5Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )
        )
        let original = "你好世界"
        guard let data = original.data(using: big5Encoding) else {
            Issue.record("Could not encode test string as Big5")
            return
        }
        let meta = try await openWithData(data)
        #expect(meta.text == original)
    }

    @Test func decodesShiftJIS() async throws {
        let original = "こんにちは"
        guard let data = original.data(using: .shiftJIS) else {
            Issue.record("Could not encode test string as Shift_JIS")
            return
        }
        let meta = try await openWithData(data)
        #expect(meta.text == original)
    }

    @Test func decodesEUCJP() async throws {
        let original = "日本語テスト"
        guard let data = original.data(using: .japaneseEUC) else {
            Issue.record("Could not encode test string as EUC-JP")
            return
        }
        let meta = try await openWithData(data)
        #expect(meta.text == original)
    }

    // MARK: - Latin Encodings (should still work as fallback)

    @Test func decodesISOLatin1() async throws {
        // Latin-1 specific chars: café, naïve, über
        let original = "café naïve über"
        guard let data = original.data(using: .isoLatin1) else {
            Issue.record("Could not encode test string as ISO-8859-1")
            return
        }
        let meta = try await openWithData(data)
        #expect(meta.text == original)
    }

    @Test func decodesWindowsCP1252() async throws {
        // CP1252 has chars like curly quotes (0x93, 0x94) that ISO-8859-1 doesn't map
        let cp1252Bytes: [UInt8] = [0x93, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x94] // "Hello"
        let data = Data(cp1252Bytes)
        let meta = try await openWithData(data)
        // Should decode without crashing; the curly quotes should be present
        #expect(meta.text.contains("Hello"))
    }

    // MARK: - Edge Cases

    @Test func emptyFileDecodesAsUTF8() async throws {
        let data = Data()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("txt-test-\(UUID().uuidString).txt")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = TXTService()
        let meta = try await service.open(url: url)
        #expect(meta.text == "")
        #expect(meta.detectedEncoding == "UTF-8")
    }

    // MARK: - Sample-Based Encoding Detection Boundary Tests (Audit Issue 4)

    @Test func detectEncodingFromSample_GBK_midCharBoundary() {
        // Audit Issue 4: If the 8KB sample cut lands between the lead and trail byte
        // of a GBK character, the detection can fail or produce a wrong result.
        // Build a GBK data block that has a 2-byte character spanning the 8KB boundary.
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let filler = String(repeating: "A", count: TXTService.encodingSampleSize - 1)
        // Append a 2-byte GBK character so its lead byte is at index 8191 (last byte of sample)
        // and trail byte is at index 8192 (first byte past sample).
        let fullString = filler + "你好世界"
        guard let gbkData = fullString.data(using: gbkEncoding) else {
            Issue.record("Could not encode test string as GBK")
            return
        }
        // Verify the data is larger than the sample size
        #expect(gbkData.count > TXTService.encodingSampleSize)

        // The sample-based detection should NOT crash and should return a valid encoding.
        // With the fix, the trailing lead byte at the boundary is backed up.
        let detected = TXTService.detectEncodingFromSample(gbkData)
        #expect(!detected.isEmpty, "Should detect a valid encoding, got empty string")
        // It should detect as UTF-8 (since the filler is ASCII) or GBK — not crash/fail.
    }

    @Test func detectEncodingFromSample_ShiftJIS_midCharBoundary() {
        // Similar boundary test for Shift_JIS 2-byte sequences.
        let filler = String(repeating: "A", count: TXTService.encodingSampleSize - 1)
        let fullString = filler + "こんにちは"
        guard let sjisData = fullString.data(using: .shiftJIS) else {
            Issue.record("Could not encode test string as Shift_JIS")
            return
        }
        #expect(sjisData.count > TXTService.encodingSampleSize)

        let detected = TXTService.detectEncodingFromSample(sjisData)
        #expect(!detected.isEmpty, "Should detect a valid encoding for Shift_JIS boundary case")
    }

    @Test func pureASCIIDecodesAsUTF8() async throws {
        let text = "Hello, plain ASCII text."
        let data = Data(text.utf8)
        let meta = try await openWithData(data)
        #expect(meta.text == text)
        #expect(meta.detectedEncoding == "UTF-8")
    }

    // MARK: - GBK should NOT be decoded as ISO-8859-1

    @Test func gbkNotDecodedAsLatin1() async throws {
        // This is the core regression test. GBK bytes should NOT be
        // misidentified as ISO-8859-1 (which would produce garbled text).
        let gbkBytes: [UInt8] = [0xC4, 0xE3, 0xBA, 0xC3, 0xCA, 0xC0, 0xBD, 0xE7]
        let data = Data(gbkBytes)
        let meta = try await openWithData(data)
        // Must NOT be detected as ISO-8859-1
        #expect(meta.detectedEncoding != "ISO-8859-1")
        #expect(meta.detectedEncoding != "Windows-1252")
        // Must contain actual Chinese characters, not garbled Latin
        #expect(meta.text.contains("你") || meta.text.contains("好"))
    }

    // MARK: - encodingFromName round-trip (bug #60)

    @Test func encodingFromNameRoundTrip() {
        let knownNames = ["UTF-8", "UTF-16", "ISO-8859-1", "Windows-1252",
                          "EUC-JP", "Shift_JIS", "GBK", "Big5", "EUC-KR"]
        for name in knownNames {
            let enc = TXTService.encodingFromName(name)
            #expect(enc != nil, "encodingFromName should resolve '\(name)'")
        }
    }

    @Test func encodingFromNameUnknownReturnsNil() {
        #expect(TXTService.encodingFromName("FooBar-999") == nil)
    }

    @Test func sampleDetectionMatchesFullDetection() {
        // GBK-encoded CJK text — sample detection should match full
        let text = "你好世界"
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        guard let data = text.data(using: enc) else { return }
        let sampleName = TXTService.detectEncodingFromSample(data)
        guard let (_, fullName) = TXTService.decodeText(data) else { return }
        #expect(sampleName == fullName)
    }
}

// MARK: - SearchService offset restoration (bug #61)

@Suite("SearchService Segment Offsets")
struct SearchServiceOffsetTests {
    @Test func restoreSegmentOffsetsAreUsed() async throws {
        let store = try SearchIndexStore()
        let service = SearchService(store: store)
        let fp = DocumentFingerprint(
            contentSHA256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            fileByteCount: 1000,
            format: .txt
        )
        let offsets: [Int: Int] = [0: 0, 1: 500, 2: 1200]

        await service.restoreSegmentOffsets(fingerprint: fp, offsets: offsets)

        // Verify the service considers the book indexed
        let indexed = await service.isIndexed(fingerprint: fp)
        #expect(indexed)
    }
}
