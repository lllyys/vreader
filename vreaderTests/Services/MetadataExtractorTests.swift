// Purpose: Tests for MetadataExtractor protocol and stub implementations.

import Testing
import Foundation
@testable import vreader

@Suite("MetadataExtractor")
struct MetadataExtractorTests {

    // MARK: - TXT Metadata

    @Test func txtExtractsTitleFromFilename() async throws {
        let extractor = TXTMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/My Book.txt")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "My Book")
        #expect(metadata.author == nil)
        #expect(metadata.coverImagePath == nil)
    }

    @Test func txtTrimsWhitespace() async throws {
        let extractor = TXTMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/  spaced name  .txt")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "spaced name")
    }

    @Test func txtEmptyFilenameBecomesUntitled() async throws {
        let extractor = TXTMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/.txt")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "Untitled")
    }

    @Test func txtLongFilenameTruncated() async throws {
        let extractor = TXTMetadataExtractor()
        let longName = String(repeating: "a", count: 300)
        let url = URL(fileURLWithPath: "/tmp/\(longName).txt")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title.count == 255)
    }

    @Test func txtUnicodeFilename() async throws {
        let extractor = TXTMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/日本語の本.txt")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "日本語の本")
    }

    // MARK: - EPUB Stub

    @Test func epubStubExtractsFromFilename() async throws {
        let extractor = EPUBMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/Great Novel.epub")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "Great Novel")
        #expect(metadata.author == nil)
    }

    // MARK: - PDF Stub

    @Test func pdfStubExtractsFromFilename() async throws {
        let extractor = PDFMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/Research Paper.pdf")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "Research Paper")
        #expect(metadata.author == nil)
    }

    // MARK: - Edge Cases

    @Test func filenameWithDotsInPath() async throws {
        let extractor = TXTMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/Dr. Smith's Notes.txt")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "Dr. Smith's Notes")
    }

    @Test func whitespaceOnlyFilenameBecomesUntitled() async throws {
        let extractor = TXTMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/   .txt")
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "Untitled")
    }
}
