// Purpose: Tests for BlobPath — content-addressed WebDAV path utility used by
// feature #46 (WebDAV materializing restore). Asserts canonical layout, format
// round-trip, and rejection of malformed inputs.
//
// @coordinates-with: vreader/Services/Backup/BlobPath.swift,
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Testing
import Foundation
@testable import vreader

@Suite("BlobPath — feature #46 WI-1")
struct BlobPathTests {

    // MARK: - make() — happy path per format

    @Test func makeEpubPath() {
        let path = BlobPath.make(
            format: .epub,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1024
        )
        #expect(path == "VReader/books/epub/\(String(repeating: "a", count: 64))_1024.epub")
    }

    @Test func makeAzw3Path() {
        // MOBI/PRC/AZW collapse to canonical .azw3 — blob path uses .azw3
        // regardless of original extension. originalExtension lives in the manifest.
        let path = BlobPath.make(
            format: .azw3,
            sha256: String(repeating: "b", count: 64),
            byteCount: 9_999_999
        )
        #expect(path == "VReader/books/azw3/\(String(repeating: "b", count: 64))_9999999.azw3")
    }

    @Test func makeTxtPath() {
        let path = BlobPath.make(
            format: .txt,
            sha256: String(repeating: "c", count: 64),
            byteCount: 14_059_220
        )
        #expect(path == "VReader/books/txt/\(String(repeating: "c", count: 64))_14059220.txt")
    }

    @Test func makeMdPath() {
        let path = BlobPath.make(
            format: .md,
            sha256: String(repeating: "d", count: 64),
            byteCount: 512
        )
        #expect(path == "VReader/books/md/\(String(repeating: "d", count: 64))_512.md")
    }

    @Test func makePdfPath() {
        let path = BlobPath.make(
            format: .pdf,
            sha256: String(repeating: "e", count: 64),
            byteCount: 1_048_576
        )
        #expect(path == "VReader/books/pdf/\(String(repeating: "e", count: 64))_1048576.pdf")
    }

    // MARK: - parse() — round trip

    @Test(arguments: BookFormat.allCases) func roundTripPerFormat(_ format: BookFormat) throws {
        let sha = String(repeating: "f", count: 64)
        let bytes: Int64 = 65_537
        let path = BlobPath.make(format: format, sha256: sha, byteCount: bytes)
        let parsed = try #require(BlobPath.parse(path))
        #expect(parsed.format == format)
        #expect(parsed.sha256 == sha)
        #expect(parsed.byteCount == bytes)
    }

    // MARK: - parse() — rejection

    @Test func parseInvalidFormat_returnsNil() {
        let bogus = "VReader/books/zzz/\(String(repeating: "a", count: 64))_1024.zzz"
        #expect(BlobPath.parse(bogus) == nil)
    }

    @Test func parseShortSHA_returnsNil() {
        // SHA-256 must be 64 hex chars. Anything shorter is invalid identity.
        let short = "VReader/books/epub/abcd_1024.epub"
        #expect(BlobPath.parse(short) == nil)
    }

    @Test func parseNonHexSHA_returnsNil() {
        // 64 chars but not all hex — corrupt fingerprint, reject.
        let nonHex = "VReader/books/epub/\(String(repeating: "z", count: 64))_1024.epub"
        #expect(BlobPath.parse(nonHex) == nil)
    }

    @Test func parseMissingByteCount_returnsNil() {
        let missing = "VReader/books/epub/\(String(repeating: "a", count: 64)).epub"
        #expect(BlobPath.parse(missing) == nil)
    }

    @Test func parseNonNumericByteCount_returnsNil() {
        let bad = "VReader/books/epub/\(String(repeating: "a", count: 64))_xyz.epub"
        #expect(BlobPath.parse(bad) == nil)
    }

    @Test func parseWrongRoot_returnsNil() {
        let wrong = "Other/path/epub/\(String(repeating: "a", count: 64))_1024.epub"
        #expect(BlobPath.parse(wrong) == nil)
    }

    @Test func parseEmptyString_returnsNil() {
        #expect(BlobPath.parse("") == nil)
    }

    // MARK: - Invariants

    @Test func booksRootIsStable() {
        // Servers cache and tools script against this prefix; changing it would
        // break every previously-uploaded backup. Pin via test.
        #expect(BlobPath.booksRoot == "VReader/books")
    }

    @Test func makeNeverContainsColons() {
        // Colons in the canonical fingerprintKey ("epub:abc:1024") aren't
        // safe across every WebDAV server. Blob path uses underscores.
        let path = BlobPath.make(
            format: .epub,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1024
        )
        #expect(!path.contains(":"))
    }
}
