// Purpose: Unit tests for SearchHitToLocatorResolver — SearchHit to Locator conversion.

import Testing
import Foundation
@testable import vreader

@Suite("SearchHitToLocatorResolver")
struct SearchHitToLocatorResolverTests {

    // MARK: - Test fixtures

    private static let epubFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 10240,
        format: .epub
    )

    private static let pdfFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112234",
        fileByteCount: 20480,
        format: .pdf
    )

    private static let txtFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112235",
        fileByteCount: 512,
        format: .txt
    )

    // MARK: - EPUB resolution

    @Test func resolveEPUBHit() {
        let hit = SearchHit(
            fingerprintKey: Self.epubFP.canonicalKey,
            sourceUnitId: "epub:chapter1.xhtml",
            snippet: "...some text...",
            matchStartOffsetUTF16: 42,
            matchEndOffsetUTF16: 50
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.epubFP)
        #expect(locator != nil)
        #expect(locator?.href == "chapter1.xhtml")
        #expect(locator?.bookFingerprint == Self.epubFP)
    }

    // MARK: - PDF resolution

    @Test func resolvePDFHit() {
        let hit = SearchHit(
            fingerprintKey: Self.pdfFP.canonicalKey,
            sourceUnitId: "pdf:page:5",
            snippet: "...pdf text...",
            matchStartOffsetUTF16: 10,
            matchEndOffsetUTF16: 20
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.pdfFP)
        #expect(locator != nil)
        #expect(locator?.page == 5)
        #expect(locator?.bookFingerprint == Self.pdfFP)
    }

    @Test func resolvePDFPageZero() {
        let hit = SearchHit(
            fingerprintKey: Self.pdfFP.canonicalKey,
            sourceUnitId: "pdf:page:0",
            snippet: "first page",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 10
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.pdfFP)
        #expect(locator != nil)
        #expect(locator?.page == 0)
    }

    // MARK: - TXT resolution

    @Test func resolveTXTHit() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "txt:segment:2",
            snippet: "...txt content...",
            matchStartOffsetUTF16: 15,
            matchEndOffsetUTF16: 25
        )

        // With segment base offsets: segment 0 = 0..100, segment 1 = 100..200, segment 2 = 200..300
        let segmentBaseOffsets: [Int: Int] = [0: 0, 1: 100, 2: 200]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.txtFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator != nil)
        // The global offset should be segment base (200) + hit offset (15) = 215
        #expect(locator?.charOffsetUTF16 == 215)
    }

    @Test func resolveTXTRange() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "txt:segment:0",
            snippet: "hello",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 5
        )

        let segmentBaseOffsets: [Int: Int] = [0: 0]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.txtFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator != nil)
        #expect(locator?.charOffsetUTF16 == 0)
    }

    // MARK: - Edge cases

    @Test func invalidSourceUnitIdFormat() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "invalid:format",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.txtFP)
        #expect(locator == nil)
    }

    @Test func pdfNonNumericPage() {
        let hit = SearchHit(
            fingerprintKey: Self.pdfFP.canonicalKey,
            sourceUnitId: "pdf:page:abc",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.pdfFP)
        #expect(locator == nil)
    }

    @Test func txtMissingSegmentBaseOffset() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "txt:segment:99",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        // No segment 99 in base offsets
        let segmentBaseOffsets: [Int: Int] = [0: 0]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.txtFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator == nil)
    }

    // MARK: - MD resolution

    private static let mdFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112236",
        fileByteCount: 256,
        format: .md
    )

    @Test func resolveMDHit() {
        let hit = SearchHit(
            fingerprintKey: Self.mdFP.canonicalKey,
            sourceUnitId: "md:segment:1",
            snippet: "...md content...",
            matchStartOffsetUTF16: 10,
            matchEndOffsetUTF16: 20
        )

        let segmentBaseOffsets: [Int: Int] = [0: 0, 1: 50]

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.mdFP,
            segmentBaseOffsets: segmentBaseOffsets
        )
        #expect(locator != nil)
        // Global offset = segment base (50) + hit offset (10) = 60
        #expect(locator?.charOffsetUTF16 == 60)
    }

    @Test func resolveMDHitMissingOffsets() {
        let hit = SearchHit(
            fingerprintKey: Self.mdFP.canonicalKey,
            sourceUnitId: "md:segment:0",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(
            hit: hit,
            fingerprint: Self.mdFP,
            segmentBaseOffsets: nil
        )
        #expect(locator == nil)
    }

    // MARK: - Edge cases

    @Test func emptySourceUnitId() {
        let hit = SearchHit(
            fingerprintKey: Self.txtFP.canonicalKey,
            sourceUnitId: "",
            snippet: "text",
            matchStartOffsetUTF16: 0,
            matchEndOffsetUTF16: 4
        )

        let locator = SearchHitToLocatorResolver.resolve(hit: hit, fingerprint: Self.txtFP)
        #expect(locator == nil)
    }
}
