// Purpose: Tests for MDFileLoader — verifies file read + parse + position restore
// logic extracted from MDReaderViewModel in WI-008c.
//
// @coordinates-with: MDFileLoader.swift, MDParserProtocol.swift, MockMDParser.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFP = DocumentFingerprint(
    contentSHA256: "md_loader_test_sha256_00000000000000000000000000000000000000",
    fileByteCount: 500,
    format: .md
)

private let testRenderedText = "Title\nHello world. This is rendered markdown content.\n"
private let testMDSource = "# Title\n\nHello world. This is **rendered** markdown content.\n"

private func makeDocumentInfo(
    renderedText: String = testRenderedText
) -> MDDocumentInfo {
    MDDocumentInfo(
        renderedText: renderedText,
        renderedAttributedString: NSAttributedString(string: renderedText),
        headings: [MDHeading(level: 1, text: "Title", charOffsetUTF16: 0)],
        title: "Title"
    )
}

// MARK: - Tests

@Suite("MDFileLoader")
struct MDFileLoaderTests {

    @Test("load returns document info from parser")
    func loadReturnsDocumentInfo() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.documentInfo.renderedText == testRenderedText)
        #expect(result.documentInfo.title == "Title")
        #expect(parser.parseCallCount == 1)
    }

    @Test("load restores saved UTF-16 offset position")
    func loadRestoresSavedPosition() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let savedLocator = Locator(
            bookFingerprint: testFP,
            href: nil, progression: nil, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 25,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 25)
    }

    @Test("load falls back to offset 0 with no saved position")
    func loadFallsBackToZero() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fallback_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 0)
    }

    @Test("load clamps saved offset beyond text length")
    func loadClampsOversizedOffset() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let savedLocator = Locator(
            bookFingerprint: testFP,
            href: nil, progression: nil, totalProgression: 1.0,
            cfi: nil, page: nil,
            charOffsetUTF16: 999999,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: testFP.canonicalKey, locator: savedLocator)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clamp_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        let expectedMax = (testRenderedText as NSString).length
        #expect(result.restoredOffsetUTF16 == expectedMax)
    }

    @Test("load falls back on position store error")
    func loadFallsBackOnStoreError() async throws {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()
        await store.setLoadError(NSError(domain: "test", code: 1))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("error_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.restoredOffsetUTF16 == 0)
    }

    @Test("load throws on file read error")
    func loadThrowsOnFileError() async {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())
        let store = MockPositionStore()

        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).md")

        do {
            _ = try await MDFileLoader.load(
                url: url,
                parser: parser,
                positionStore: store,
                bookFingerprintKey: testFP.canonicalKey
            )
            Issue.record("Expected load to throw")
        } catch {
            // Any error is expected — file doesn't exist
        }
    }

    // MARK: - Bug #178 / GH #606: chineseConversion

    @Test("load with chineseConversion .none preserves source text passed to parser")
    func loadWithoutConversionPreservesText() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader_test_\(UUID().uuidString).md")
        try testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey,
            chineseConversion: .none
        )

        #expect(parser.lastParsedText == testMDSource)
    }

    @Test("load with chineseConversion .simpToTrad transforms source text before parse")
    func loadAppliesSimpToTradConversion() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let simpSource = "# 简体标题\n\n这是简体中文内容。\n"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader_test_simp_\(UUID().uuidString).md")
        try simpSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey,
            chineseConversion: .simpToTrad
        )

        let parsedText = parser.lastParsedText ?? ""
        #expect(parsedText != simpSource,
                "Source text should be transformed before parsing")
        // ICU Hans-Hant mappings: 简→簡, 这→這, 体→體, 内→內, 容→容 (容 already same)
        #expect(parsedText.contains("簡") || parsedText.contains("這") || parsedText.contains("體"),
                "Should contain at least one Traditional CJK character. Got: \(parsedText)")
        // Markdown structure characters must be preserved
        #expect(parsedText.contains("# "), "Markdown heading marker must be preserved")
    }

    @Test("load with chineseConversion .tradToSimp transforms source text before parse")
    func loadAppliesTradToSimpConversion() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let tradSource = "# 繁體標題\n\n這是繁體中文內容。\n"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader_test_trad_\(UUID().uuidString).md")
        try tradSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey,
            chineseConversion: .tradToSimp
        )

        let parsedText = parser.lastParsedText ?? ""
        #expect(parsedText != tradSource,
                "Source text should be transformed before parsing")
        // ICU Hans-Hant reverse mappings: 繁→繁 (same), 體→体, 標→标, 題→题, 這→这, 內→内
        #expect(parsedText.contains("体") || parsedText.contains("这") || parsedText.contains("标"),
                "Should contain at least one Simplified CJK character. Got: \(parsedText)")
    }

    @Test("load handles empty document")
    func loadEmptyDocument() async throws {
        let emptyInfo = MDDocumentInfo(
            renderedText: "",
            renderedAttributedString: NSAttributedString(string: ""),
            headings: [],
            title: nil
        )
        let parser = MockMDParser()
        parser.setDocumentInfo(emptyInfo)
        let store = MockPositionStore()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty_test_\(UUID().uuidString).md")
        try "".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(result.documentInfo.renderedText == "")
        #expect(result.documentInfo.renderedTextLengthUTF16 == 0)
        #expect(result.restoredOffsetUTF16 == 0)
    }
}
