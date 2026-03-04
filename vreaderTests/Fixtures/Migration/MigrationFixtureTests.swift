// Purpose: Tests that migration fixtures produce valid, consistent data.
// This is the baseline migration test — ensures fixture data is well-formed
// and models can be instantiated from fixture values.

import Testing
import Foundation
@testable import vreader

@Suite("Migration Fixtures")
struct MigrationFixtureTests {

    // MARK: - Fingerprint Fixtures

    @Test func epubFingerprintIsValid() {
        let fp = MigrationFixtures.sampleEpubFingerprint()
        #expect(fp.format == .epub)
        #expect(!fp.contentSHA256.isEmpty)
        #expect(fp.fileByteCount > 0)
        #expect(!fp.canonicalKey.isEmpty)
    }

    @Test func pdfFingerprintIsValid() {
        let fp = MigrationFixtures.samplePdfFingerprint()
        #expect(fp.format == .pdf)
        #expect(fp.fileByteCount > 0)
    }

    @Test func txtFingerprintIsValid() {
        let fp = MigrationFixtures.sampleTxtFingerprint()
        #expect(fp.format == .txt)
    }

    @Test func fixtureFingerprrintsAreDistinct() {
        let epub = MigrationFixtures.sampleEpubFingerprint()
        let pdf = MigrationFixtures.samplePdfFingerprint()
        let txt = MigrationFixtures.sampleTxtFingerprint()
        #expect(epub.canonicalKey != pdf.canonicalKey)
        #expect(pdf.canonicalKey != txt.canonicalKey)
        #expect(epub.canonicalKey != txt.canonicalKey)
    }

    // MARK: - Locator Fixtures

    @Test func epubLocatorHasEpubFields() {
        let loc = MigrationFixtures.sampleEpubLocator()
        #expect(loc.href != nil)
        #expect(loc.progression != nil)
        #expect(loc.cfi != nil)
        #expect(loc.bookFingerprint.format == .epub)
    }

    @Test func pdfLocatorHasPageField() {
        let loc = MigrationFixtures.samplePdfLocator()
        #expect(loc.page != nil)
        #expect(loc.href == nil)
        #expect(loc.bookFingerprint.format == .pdf)
    }

    @Test func txtLocatorHasUTF16Offset() {
        let loc = MigrationFixtures.sampleTxtLocator()
        #expect(loc.charOffsetUTF16 != nil)
        #expect(loc.bookFingerprint.format == .txt)
    }

    @Test func txtRangeLocatorHasRange() {
        let loc = MigrationFixtures.sampleTxtRangeLocator()
        #expect(loc.charRangeStartUTF16 != nil)
        #expect(loc.charRangeEndUTF16 != nil)
        #expect(loc.charRangeEndUTF16! > loc.charRangeStartUTF16!)
    }

    // MARK: - Book Fixtures

    @Test func epubBookFixtureIsValid() {
        let book = MigrationFixtures.sampleEpubBook()
        #expect(book.title == "Sample EPUB Book")
        #expect(book.author == "Test Author")
        #expect(book.format == "epub")
        #expect(book.fingerprintKey == MigrationFixtures.sampleEpubFingerprint().canonicalKey)
    }

    @Test func pdfBookFixtureIsValid() {
        let book = MigrationFixtures.samplePdfBook()
        #expect(book.format == "pdf")
        #expect(book.provenance.source == .icloudDrive)
        #expect(book.provenance.originalURLBookmarkData != nil)
    }

    // MARK: - Session Fixtures

    @Test func sessionFixtureIsValid() {
        let session = MigrationFixtures.sampleSession()
        #expect(session.durationSeconds == 1800)
        #expect(session.pagesRead == 10)
        #expect(session.wordsRead == 3000)
        #expect(session.endedAt != nil)
    }

    @Test func sessionFixtureCustomParams() {
        let fp = MigrationFixtures.samplePdfFingerprint()
        let session = MigrationFixtures.sampleSession(
            fingerprint: fp,
            durationSeconds: 600,
            pagesRead: 5,
            wordsRead: nil
        )
        #expect(session.bookFingerprintKey == fp.canonicalKey)
        #expect(session.durationSeconds == 600)
        #expect(session.wordsRead == nil)
    }

    // MARK: - Locator Serialization Stability

    @Test func epubLocatorCodableRoundTrip() throws {
        let original = MigrationFixtures.sampleEpubLocator()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == original)
    }

    @Test func pdfLocatorCodableRoundTrip() throws {
        let original = MigrationFixtures.samplePdfLocator()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == original)
    }

    @Test func txtLocatorCodableRoundTrip() throws {
        let original = MigrationFixtures.sampleTxtLocator()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == original)
    }

    @Test func txtRangeLocatorCodableRoundTrip() throws {
        let original = MigrationFixtures.sampleTxtRangeLocator()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Canonical Hash Stability Across Fixtures

    @Test func fixtureLocatorHashesAreDistinct() {
        let epub = MigrationFixtures.sampleEpubLocator()
        let pdf = MigrationFixtures.samplePdfLocator()
        let txt = MigrationFixtures.sampleTxtLocator()
        let txtRange = MigrationFixtures.sampleTxtRangeLocator()

        let hashes = Set([epub.canonicalHash, pdf.canonicalHash, txt.canonicalHash, txtRange.canonicalHash])
        #expect(hashes.count == 4, "All fixture locators should have distinct canonical hashes")
    }
}
