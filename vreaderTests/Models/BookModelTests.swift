// Purpose: Tests for Book @Model — initialization, fingerprint key consistency,
// indexing metadata, and relationship defaults.

import Testing
import Foundation
@testable import vreader

@Suite("Book Model")
struct BookModelTests {

    // Use a valid 64-character hex hash to match production invariants
    static let sampleFP = DocumentFingerprint(
        contentSHA256: "abc123def456abc123def456abc123def456abc123def456abc123def456abcd",
        fileByteCount: 1_048_576,
        format: .epub
    )

    static let sampleProvenance = ImportProvenance(
        source: .filesApp,
        importedAt: Date(timeIntervalSince1970: 1_700_000_000),
        originalURLBookmarkData: nil
    )

    // MARK: - Initialization

    @Test func initSetsAllRequiredFields() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test Book",
            author: "Test Author",
            provenance: Self.sampleProvenance
        )
        #expect(book.title == "Test Book")
        #expect(book.author == "Test Author")
        #expect(book.format == "epub")
        #expect(book.fileByteCount == 1_048_576)
        #expect(book.isFavorite == false)
        #expect(book.tags.isEmpty)
    }

    @Test func fingerprintKeyMatchesCanonicalKey() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        #expect(book.fingerprintKey == Self.sampleFP.canonicalKey)
    }

    @Test func fingerprintKeyContainsFormat() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        #expect(book.fingerprintKey.hasPrefix("epub:"))
    }

    // MARK: - Optional Fields Default to Nil

    @Test func optionalFieldsDefaultToNil() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        #expect(book.coverImagePath == nil)
        #expect(book.lastOpenedAt == nil)
        #expect(book.totalWordCount == nil)
        #expect(book.totalPageCount == nil)
        #expect(book.totalTextLengthUTF16 == nil)
        #expect(book.detectedEncoding == nil)
    }

    // MARK: - Detected Encoding

    @Test func detectedEncodingCanBeSet() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        book.detectedEncoding = "utf-8"
        #expect(book.detectedEncoding == "utf-8")
    }

    @Test func detectedEncodingStoresIANAName() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        book.detectedEncoding = "shift_jis"
        #expect(book.detectedEncoding == "shift_jis")
    }

    // MARK: - Indexing Metadata

    @Test func indexingMetadataCanBeSet() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        book.totalWordCount = 50_000
        book.totalPageCount = 200
        book.totalTextLengthUTF16 = 300_000

        #expect(book.totalWordCount == 50_000)
        #expect(book.totalPageCount == 200)
        #expect(book.totalTextLengthUTF16 == 300_000)
    }

    // MARK: - Relationship Defaults

    @Test func relationshipsInitializeEmpty() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance
        )
        #expect(book.readingPosition == nil)
        #expect(book.bookmarks.isEmpty)
        #expect(book.highlights.isEmpty)
        #expect(book.annotations.isEmpty)
    }

    // MARK: - Tags

    @Test func tagsCanBeProvided() {
        let book = Book(
            fingerprint: Self.sampleFP,
            title: "Test",
            provenance: Self.sampleProvenance,
            tags: ["fiction", "sci-fi"]
        )
        #expect(book.tags.count == 2)
        #expect(book.tags.contains("fiction"))
    }

    // MARK: - Different Formats

    @Test func pdfBookHasCorrectFormat() {
        let pdfFP = DocumentFingerprint(
            contentSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            fileByteCount: 2048,
            format: .pdf
        )
        let book = Book(fingerprint: pdfFP, title: "PDF Book", provenance: Self.sampleProvenance)
        #expect(book.format == "pdf")
        #expect(book.fingerprintKey.hasPrefix("pdf:"))
    }

    @Test func txtBookHasCorrectFormat() {
        let txtFP = DocumentFingerprint(
            contentSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            fileByteCount: 512,
            format: .txt
        )
        let book = Book(fingerprint: txtFP, title: "TXT Book", provenance: Self.sampleProvenance)
        #expect(book.format == "txt")
    }
}
