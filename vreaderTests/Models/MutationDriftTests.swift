// Purpose: Tests for mutation drift — derived keys stay consistent when parent fields change.

import Testing
import Foundation
@testable import vreader

@Suite("Mutation Drift")
struct MutationDriftTests {

    static let provenance = ImportProvenance(
        source: .filesApp,
        importedAt: Date(timeIntervalSince1970: 1_700_000_000),
        originalURLBookmarkData: nil
    )

    static let epubFP = DocumentFingerprint(
        contentSHA256: "abc123def456789012345678901234567890123456789012345678901234abcd",
        fileByteCount: 1024,
        format: .epub
    )

    static let pdfFP = DocumentFingerprint(
        contentSHA256: "def456abc789012345678901234567890123456789012345678901234567ef01",
        fileByteCount: 2048,
        format: .pdf
    )

    // MARK: - Book Drift

    @Test func bookFingerprintChangeSyncsDerivedFields() {
        let book = Book(
            fingerprint: Self.epubFP,
            title: "Test",
            provenance: Self.provenance
        )
        #expect(book.format == "epub")
        #expect(book.fingerprintKey == Self.epubFP.canonicalKey)

        // Mutate fingerprint
        book.fingerprint = Self.pdfFP

        #expect(book.format == "pdf")
        #expect(book.fileByteCount == 2048)
        #expect(book.fingerprintKey == Self.pdfFP.canonicalKey)
    }

    // MARK: - ReadingPosition Drift

    @Test func readingPositionLocatorChangeSyncsHash() {
        let loc1 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.1, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let pos = ReadingPosition(locator: loc1)
        let hash1 = pos.locatorHash

        let loc2 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch2.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        pos.locator = loc2

        #expect(pos.locatorHash != hash1)
        #expect(pos.locatorHash == loc2.canonicalHash)
    }

    // MARK: - Bookmark Drift

    @Test func bookmarkLocatorChangeSyncsProfileKey() {
        let loc1 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.1, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let bookmark = Bookmark(locator: loc1)
        let key1 = bookmark.profileKey

        let loc2 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch3.xhtml", progression: 0.9, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        bookmark.locator = loc2

        #expect(bookmark.profileKey != key1)
        #expect(bookmark.profileKey.contains(loc2.canonicalHash))
    }

    // MARK: - ReadingSession Drift

    @Test func sessionFingerprintChangeSyncsKey() {
        let session = ReadingSession(bookFingerprint: Self.epubFP)
        #expect(session.bookFingerprintKey == Self.epubFP.canonicalKey)

        session.bookFingerprint = Self.pdfFP

        #expect(session.bookFingerprintKey == Self.pdfFP.canonicalKey)
    }

    // MARK: - Negative Value Clamping

    @Test func sessionClamsNegativeDuration() {
        let session = ReadingSession(
            bookFingerprint: Self.epubFP,
            durationSeconds: -100
        )
        #expect(session.durationSeconds == 0)
    }

    @Test func sessionClampsNegativePagesRead() {
        let session = ReadingSession(
            bookFingerprint: Self.epubFP,
            pagesRead: -5
        )
        #expect(session.pagesRead == 0)
    }

    @Test func sessionClampsNegativeWordsRead() {
        let session = ReadingSession(
            bookFingerprint: Self.epubFP,
            wordsRead: -1000
        )
        #expect(session.wordsRead == 0)
    }

    @Test func sessionDidSetClamsNegativeDuration() {
        let session = ReadingSession(bookFingerprint: Self.epubFP, durationSeconds: 100)
        session.durationSeconds = -50
        #expect(session.durationSeconds == 0)
    }

    // MARK: - Timeline Validation

    @Test func validTimelineReturnsTrue() {
        let session = ReadingSession(
            bookFingerprint: Self.epubFP,
            startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 2000)
        )
        #expect(session.hasValidTimeline)
    }

    @Test func invertedTimelineReturnsFalse() {
        let session = ReadingSession(
            bookFingerprint: Self.epubFP,
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 1000)
        )
        #expect(!session.hasValidTimeline)
    }

    @Test func nilEndedAtIsValidTimeline() {
        let session = ReadingSession(bookFingerprint: Self.epubFP)
        #expect(session.hasValidTimeline)
    }
}
