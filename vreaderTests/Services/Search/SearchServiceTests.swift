// Purpose: Tests for SearchService — index + search round-trip, pagination,
// no-results, source context formatting, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("SearchService")
struct SearchServiceTests {

    // MARK: - Helpers

    private static let txtFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    private static let pdfFP = DocumentFingerprint(
        contentSHA256: "bbccddee00112233bbccddee00112233bbccddee00112233bbccddee00112233",
        fileByteCount: 2048,
        format: .pdf
    )

    private static let epubFP = DocumentFingerprint(
        contentSHA256: "ccddeeff00112233ccddeeff00112233ccddeeff00112233ccddeeff00112233",
        fileByteCount: 4096,
        format: .epub
    )

    private func makeService() throws -> SearchService {
        let store = try SearchIndexStore()
        return SearchService(store: store)
    }

    // MARK: - Index and Search Round-Trip

    @Test func indexAndSearchReturnsResults() async throws {
        let service = try makeService()
        let units = [
            TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world this is a test"),
            TextUnit(sourceUnitId: "txt:segment:1", text: "Another paragraph with words"),
        ]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0, 1: 30]
        )

        let page = try await service.search(
            query: "hello",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )

        #expect(!page.results.isEmpty)
        #expect(page.page == 0)
    }

    @Test func searchReturnsLocatorWithCorrectFingerprint() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        let page = try await service.search(
            query: "hello",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )

        #expect(!page.results.isEmpty)
        #expect(page.results.first?.locator.bookFingerprint == Self.txtFP)
    }

    // MARK: - No Results

    @Test func searchNoResults() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        let page = try await service.search(
            query: "xyznonexistent",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )

        #expect(page.results.isEmpty)
        #expect(!page.hasMore)
    }

    // MARK: - Empty Query

    @Test func searchEmptyQuery() async throws {
        let service = try makeService()
        let page = try await service.search(
            query: "",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )

        #expect(page.results.isEmpty)
        #expect(page.totalEstimate == 0)
    }

    @Test func searchWhitespaceOnlyQuery() async throws {
        let service = try makeService()
        let page = try await service.search(
            query: "   ",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )

        // Whitespace normalizes to empty — should return empty
        #expect(page.results.isEmpty)
    }

    // MARK: - Pagination

    @Test func paginationHasMoreWhenMoreResults() async throws {
        let service = try makeService()
        var units: [TextUnit] = []
        for i in 0..<10 {
            units.append(TextUnit(
                sourceUnitId: "txt:segment:\(i)",
                text: "common word in segment number \(i)"
            ))
        }
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, $0 * 40) })
        )

        let page0 = try await service.search(
            query: "common",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 3
        )

        #expect(page0.results.count == 3)
        #expect(page0.hasMore == true)
    }

    @Test func paginationSecondPage() async throws {
        let service = try makeService()
        var units: [TextUnit] = []
        for i in 0..<5 {
            units.append(TextUnit(
                sourceUnitId: "txt:segment:\(i)",
                text: "common word in segment \(i)"
            ))
        }
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, $0 * 30) })
        )

        let page1 = try await service.search(
            query: "common",
            bookFingerprint: Self.txtFP,
            page: 1,
            pageSize: 3
        )

        #expect(page1.page == 1)
        // 5 total results, page size 3, page 1 should have 2 results
        #expect(page1.results.count == 2)
        #expect(page1.hasMore == false)
    }

    @Test func paginationBeyondResults() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        let page = try await service.search(
            query: "hello",
            bookFingerprint: Self.txtFP,
            page: 99,
            pageSize: 10
        )

        #expect(page.results.isEmpty)
        #expect(!page.hasMore)
    }

    // MARK: - isIndexed

    @Test func isIndexedFalseBeforeIndexing() async throws {
        let service = try makeService()
        let indexed = await service.isIndexed(fingerprint: Self.txtFP)
        #expect(!indexed)
    }

    @Test func isIndexedTrueAfterIndexing() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: nil
        )

        let indexed = await service.isIndexed(fingerprint: Self.txtFP)
        #expect(indexed)
    }

    // MARK: - removeIndex

    @Test func removeIndexClearsData() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        try await service.removeIndex(fingerprint: Self.txtFP)

        let indexed = await service.isIndexed(fingerprint: Self.txtFP)
        #expect(!indexed)

        // Verify search also returns no results (stale data cleared)
        let page = try await service.search(
            query: "hello",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )
        #expect(page.results.isEmpty)
    }

    // MARK: - Invalid Pagination

    @Test func searchNegativePageClampsToZero() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        let page = try await service.search(
            query: "hello",
            bookFingerprint: Self.txtFP,
            page: -1,
            pageSize: 10
        )

        #expect(!page.results.isEmpty)
    }

    @Test func searchZeroPageSizeClampsToOne() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        let page = try await service.search(
            query: "hello",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 0
        )

        #expect(page.results.count == 1)
    }

    // MARK: - Source Context Formatting

    @Test func formatSourceContextEPUB() {
        let ctx = SearchService.formatSourceContext(sourceUnitId: "epub:chapter1.xhtml")
        #expect(ctx == "chapter1")
    }

    @Test func formatSourceContextPDF() {
        let ctx = SearchService.formatSourceContext(sourceUnitId: "pdf:page:0")
        #expect(ctx == "Page 1") // 1-indexed display
    }

    @Test func formatSourceContextTXT() {
        let ctx = SearchService.formatSourceContext(sourceUnitId: "txt:segment:2")
        #expect(ctx == "Section 3") // 1-indexed display
    }

    @Test func formatSourceContextMD() {
        let ctx = SearchService.formatSourceContext(sourceUnitId: "md:segment:1")
        #expect(ctx == "Section 2") // 1-indexed display
    }

    @Test func formatSourceContextUnknown() {
        let ctx = SearchService.formatSourceContext(sourceUnitId: "unknown:format")
        #expect(ctx == "")
    }

    // MARK: - PDF Format

    @Test func searchPDFFormat() async throws {
        let service = try makeService()
        let units = [
            TextUnit(sourceUnitId: "pdf:page:0", text: "First page content"),
            TextUnit(sourceUnitId: "pdf:page:1", text: "Second page with different text"),
        ]
        try await service.indexBook(
            fingerprint: Self.pdfFP,
            textUnits: units,
            segmentBaseOffsets: nil
        )

        let page = try await service.search(
            query: "first",
            bookFingerprint: Self.pdfFP,
            page: 0,
            pageSize: 10
        )

        #expect(!page.results.isEmpty)
        #expect(page.results.first?.locator.page == 0)
        #expect(page.results.first?.sourceContext == "Page 1")
    }

    // MARK: - EPUB Format

    @Test func searchEPUBFormat() async throws {
        let service = try makeService()
        let units = [
            TextUnit(sourceUnitId: "epub:intro.xhtml", text: "Welcome to the book"),
        ]
        try await service.indexBook(
            fingerprint: Self.epubFP,
            textUnits: units,
            segmentBaseOffsets: nil
        )

        let page = try await service.search(
            query: "welcome",
            bookFingerprint: Self.epubFP,
            page: 0,
            pageSize: 10
        )

        #expect(!page.results.isEmpty)
        #expect(page.results.first?.locator.href == "intro.xhtml")
        #expect(page.results.first?.sourceContext == "intro")
    }

    // MARK: - Re-Index Replaces Data

    @Test func reIndexSameBookReplacesOldData() async throws {
        let service = try makeService()
        let units1 = [TextUnit(sourceUnitId: "txt:segment:0", text: "original unique alpha")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units1,
            segmentBaseOffsets: [0: 0]
        )

        // Re-index with different content
        let units2 = [TextUnit(sourceUnitId: "txt:segment:0", text: "replacement unique beta")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units2,
            segmentBaseOffsets: [0: 0]
        )

        // Old content should not be found
        let oldPage = try await service.search(
            query: "alpha",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )
        #expect(oldPage.results.isEmpty)

        // New content should be found
        let newPage = try await service.search(
            query: "beta",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )
        #expect(!newPage.results.isEmpty)
    }

    // MARK: - CJK Search

    @Test func searchCJKText() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "这是一个中文测试文本")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        let page = try await service.search(
            query: "中文",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )
        #expect(!page.results.isEmpty, "CJK search should return results after segmentation fix")
        #expect(page.results.first?.sourceContext == "Section 1")
    }

    // MARK: - Diacritic Search

    @Test func searchDiacriticFolding() async throws {
        let service = try makeService()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "café résumé naïve")]
        try await service.indexBook(
            fingerprint: Self.txtFP,
            textUnits: units,
            segmentBaseOffsets: [0: 0]
        )

        let page = try await service.search(
            query: "cafe",
            bookFingerprint: Self.txtFP,
            page: 0,
            pageSize: 10
        )

        #expect(!page.results.isEmpty)
    }
}
