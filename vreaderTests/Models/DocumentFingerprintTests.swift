// Purpose: Tests for DocumentFingerprint — identity, canonicalKey, Codable, Hashable.

import Testing
import Foundation
@testable import vreader

@Suite("DocumentFingerprint")
struct DocumentFingerprintTests {

    static let sampleSHA = "abc123def456789012345678901234567890123456789012345678901234abcd"

    // MARK: - Canonical Key

    @Test func canonicalKeyFormat() {
        let fp = DocumentFingerprint(
            contentSHA256: Self.sampleSHA,
            fileByteCount: 1024,
            format: .epub
        )
        #expect(fp.canonicalKey == "epub:\(Self.sampleSHA):1024")
    }

    @Test func canonicalKeyDiffersAcrossFormats() {
        let epub = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 1024, format: .epub)
        let pdf = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 1024, format: .pdf)
        #expect(epub.canonicalKey != pdf.canonicalKey)
    }

    @Test func canonicalKeyDiffersAcrossSizes() {
        let small = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 1024, format: .epub)
        let large = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 2048, format: .epub)
        #expect(small.canonicalKey != large.canonicalKey)
    }

    @Test func canonicalKeyDiffersAcrossHashes() {
        let a = DocumentFingerprint(contentSHA256: "aaa", fileByteCount: 1024, format: .epub)
        let b = DocumentFingerprint(contentSHA256: "bbb", fileByteCount: 1024, format: .epub)
        #expect(a.canonicalKey != b.canonicalKey)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let original = DocumentFingerprint(
            contentSHA256: Self.sampleSHA,
            fileByteCount: 1_048_576,
            format: .pdf
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DocumentFingerprint.self, from: data)
        #expect(decoded == original)
        #expect(decoded.canonicalKey == original.canonicalKey)
    }

    // MARK: - Hashable

    @Test func equalFingerprintsHaveSameHash() {
        let a = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 100, format: .txt)
        let b = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 100, format: .txt)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func differentFingerprintsAreNotEqual() {
        let a = DocumentFingerprint(contentSHA256: "aaa", fileByteCount: 100, format: .txt)
        let b = DocumentFingerprint(contentSHA256: "bbb", fileByteCount: 100, format: .txt)
        #expect(a != b)
    }

    @Test func usableAsSetElement() {
        let fp = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 100, format: .epub)
        var set: Set<DocumentFingerprint> = []
        set.insert(fp)
        set.insert(fp)  // duplicate
        #expect(set.count == 1)
    }

    @Test func usableAsDictionaryKey() {
        let fp = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 100, format: .epub)
        var dict: [DocumentFingerprint: String] = [:]
        dict[fp] = "test"
        #expect(dict[fp] == "test")
    }

    // MARK: - Edge Cases

    @Test func zeroByteCount() {
        let fp = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: 0, format: .txt)
        #expect(fp.canonicalKey == "txt:\(Self.sampleSHA):0")
    }

    @Test func largeByteCount() {
        let fp = DocumentFingerprint(contentSHA256: Self.sampleSHA, fileByteCount: Int64.max, format: .pdf)
        #expect(fp.canonicalKey.contains("\(Int64.max)"))
    }

    @Test func emptySHA() {
        let fp = DocumentFingerprint(contentSHA256: "", fileByteCount: 100, format: .epub)
        #expect(fp.canonicalKey == "epub::100")
    }

    // MARK: - Canonical Key Parsing

    @Test func initFromCanonicalKeyRoundTrips() {
        let original = DocumentFingerprint(
            contentSHA256: Self.sampleSHA,
            fileByteCount: 1024,
            format: .epub
        )
        let parsed = DocumentFingerprint(canonicalKey: original.canonicalKey)
        #expect(parsed == original)
    }

    @Test func initFromCanonicalKeyAllFormats() {
        for format in BookFormat.allCases {
            let key = "\(format.rawValue):\(Self.sampleSHA):2048"
            let fp = DocumentFingerprint(canonicalKey: key)
            #expect(fp != nil)
            #expect(fp?.format == format)
            #expect(fp?.contentSHA256 == Self.sampleSHA)
            #expect(fp?.fileByteCount == 2048)
        }
    }

    @Test func initFromCanonicalKeyZeroBytes() {
        let fp = DocumentFingerprint(canonicalKey: "txt:\(Self.sampleSHA):0")
        #expect(fp != nil)
        #expect(fp?.fileByteCount == 0)
    }

    @Test func initFromCanonicalKeyRejectsInvalidFormat() {
        let fp = DocumentFingerprint(canonicalKey: "docx:\(Self.sampleSHA):1024")
        #expect(fp == nil)
    }

    @Test func initFromCanonicalKeyRejectsInvalidSHA() {
        // Too short
        let fp = DocumentFingerprint(canonicalKey: "epub:abc123:1024")
        #expect(fp == nil)
    }

    @Test func initFromCanonicalKeyRejectsNegativeBytes() {
        let fp = DocumentFingerprint(canonicalKey: "epub:\(Self.sampleSHA):-1")
        #expect(fp == nil)
    }

    @Test func initFromCanonicalKeyRejectsMissingParts() {
        #expect(DocumentFingerprint(canonicalKey: "epub") == nil)
        #expect(DocumentFingerprint(canonicalKey: "epub:\(Self.sampleSHA)") == nil)
        #expect(DocumentFingerprint(canonicalKey: "") == nil)
    }

    @Test func initFromCanonicalKeyRejectsNonNumericBytes() {
        let fp = DocumentFingerprint(canonicalKey: "epub:\(Self.sampleSHA):notanumber")
        #expect(fp == nil)
    }
}
