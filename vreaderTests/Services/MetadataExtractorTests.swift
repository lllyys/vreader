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

    // MARK: - EPUB Fallback

    @Test func epubFallsBackToFilenameWhenFileInvalid() async throws {
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

    // MARK: - Cover-path candidate fallback chain (bug #122)
    //
    // EPUBMetadataExtractor.coverPathCandidates is the pure-function core of
    // the cover-image fallback chain. The full extractCoverImage path (which
    // opens the ZIP and decodes UIImage bytes) is exercised end-to-end in
    // device verification; these tests pin the candidate ordering.

    private func makeEntry(_ path: String) -> ZIPEntry {
        ZIPEntry(
            path: path,
            uncompressedSize: 1,
            compressedSize: 1,
            compressionMethod: 0,
            dataOffset: 0
        )
    }

    @Test func coverCandidates_specCompliantHrefIsTriedFirst() {
        // Bug #122 acceptance criterion 2 — well-formed EPUBs continue to work.
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/Images/cover.jpg"),
            makeEntry("OEBPS/chapter1.xhtml"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "Images/cover.jpg",
            opfDirPath: "OEBPS",
            entries: entries
        )
        #expect(candidates.first == "OEBPS/Images/cover.jpg")
    }

    @Test func coverCandidates_redundantPrefixHrefFallsBackToBasename() {
        // Bug #122 acceptance criterion 1 — the reported repro shape.
        // OPF declares href="OEBPS/cover.jpg", spec join yields
        // "OEBPS/OEBPS/cover.jpg" which doesn't exist; real cover lives at
        // "OEBPS/Images/cover.jpg" (same basename). Basename fallback rescues.
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/Images/cover.jpg"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "OEBPS/cover.jpg",
            opfDirPath: "OEBPS",
            entries: entries
        )
        #expect(candidates.contains("OEBPS/Images/cover.jpg"))
        // Spec-compliant path is still emitted first even though it's a miss —
        // it's the caller (extractCoverImage) that drops misses by trying to
        // open each entry. This keeps the candidate generator pure.
        #expect(candidates.first == "OEBPS/OEBPS/cover.jpg")
    }

    @Test func coverCandidates_basenameMatchIsCaseInsensitive() {
        // Real EPUB packagers vary on case (Cover.jpg vs cover.jpg).
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/Images/Cover.JPG"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "OEBPS/cover.jpg",
            opfDirPath: "OEBPS",
            entries: entries
        )
        #expect(candidates.contains("OEBPS/Images/Cover.JPG"))
    }

    @Test func coverCandidates_basenameMatchOnlyImageExtensions() {
        // Don't accept any random entry whose basename happens to match —
        // a "cover.html" should not be returned as a candidate even though
        // its basename's stem is "cover".
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/cover.html"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "Images/cover.jpg",
            opfDirPath: "OEBPS",
            entries: entries
        )
        // Spec path is still emitted (the caller rejects it on missing
        // entry), but the .html match must NOT appear.
        #expect(!candidates.contains("OEBPS/cover.html"))
    }

    @Test func coverCandidates_archiveRootCoverFallback() {
        // When neither spec path nor basename match yields anything, scan
        // for a canonical cover.{ext} at archive root.
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("cover.png"),
            makeEntry("OEBPS/chapter1.xhtml"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "Images/missing.png",
            opfDirPath: "OEBPS",
            entries: entries
        )
        #expect(candidates.contains("cover.png"))
    }

    @Test func coverCandidates_noFallbackIfNoCoverAnywhere() {
        // Bug #122 acceptance criterion 3 — books without any cover still
        // degrade cleanly (no spurious extraction). The candidate list may
        // contain the spec path, but no actual archive entry would match
        // when extractCoverImage probes them.
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/chapter1.xhtml"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "Images/missing.png",
            opfDirPath: "OEBPS",
            entries: entries
        )
        // Only the spec-compliant attempt is emitted; no image fallback fired.
        #expect(candidates == ["OEBPS/Images/missing.png"])
    }

    @Test func coverCandidates_dedupesIdenticalPaths() {
        // If the spec path and the basename match resolve to the same entry,
        // it must appear only once in the candidate list.
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/Images/cover.jpg"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "Images/cover.jpg",
            opfDirPath: "OEBPS",
            entries: entries
        )
        #expect(candidates.filter { $0 == "OEBPS/Images/cover.jpg" }.count == 1)
    }

    @Test func coverCandidates_multipleSameBasenamePicksAll() {
        // If two entries inside the OPF tree share the same basename, both
        // are emitted in archive order so the caller can probe both. Real-
        // world EPUBs almost never have this; we just don't want to silently
        // drop either candidate.
        let entries = [
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/old/cover.jpg"),
            makeEntry("OEBPS/Images/cover.jpg"),
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "wrong/cover.jpg",
            opfDirPath: "OEBPS",
            entries: entries
        )
        #expect(candidates.contains("OEBPS/old/cover.jpg"))
        #expect(candidates.contains("OEBPS/Images/cover.jpg"))
    }

    @Test func coverCandidates_basenameRankingPrefersOPFDirTree() {
        // When a same-basename file exists both inside and outside the OPF
        // directory tree, the inside-OPF entry wins — that's the location a
        // publisher would actually associate with the book. Outside-OPF
        // matches are still kept as later fallbacks (e.g., a stray cover.jpg
        // at archive root) but never preferred.
        // Use coverHref="missing.jpg" so the spec-path candidate (which has
        // basename "missing.jpg") doesn't overlap with the same-basename
        // pool we're ranking — keeps the assertion focused on the ranker.
        let entries = [
            makeEntry("META-INF/container.xml"),
            makeEntry("backup/missing.jpg"),       // outside OPF tree
            makeEntry("OEBPS/content.opf"),
            makeEntry("OEBPS/Images/missing.jpg"), // inside OPF tree — should win
        ]
        let candidates = EPUBMetadataExtractor.coverPathCandidates(
            coverHref: "missing.jpg",
            opfDirPath: "OEBPS",
            entries: entries
        )
        // Inside-OPF basename match must precede outside-OPF basename match.
        let insideIdx = candidates.firstIndex(of: "OEBPS/Images/missing.jpg")
        let outsideIdx = candidates.firstIndex(of: "backup/missing.jpg")
        #expect(insideIdx != nil, "OPF-tree match should appear in candidates")
        #expect(outsideIdx != nil, "outside-OPF match should also appear (as later fallback)")
        if let inside = insideIdx, let outside = outsideIdx {
            #expect(inside < outside, "OPF-tree match must come before outside-OPF match")
        }
    }
}
