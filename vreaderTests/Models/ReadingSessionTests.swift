// Purpose: Tests for ReadingSession model — initialization, key consistency, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("ReadingSession")
struct ReadingSessionTests {

    static let sampleFP = DocumentFingerprint(
        contentSHA256: "session123", fileByteCount: 1024, format: .epub
    )

    // MARK: - Initialization

    @Test func initSetsAllFields() {
        let sessionId = UUID()
        let start = Date()
        let session = ReadingSession(
            sessionId: sessionId,
            bookFingerprint: Self.sampleFP,
            startedAt: start,
            durationSeconds: 1800,
            pagesRead: 15,
            wordsRead: 4500,
            deviceId: "device-001"
        )
        #expect(session.sessionId == sessionId)
        #expect(session.bookFingerprintKey == Self.sampleFP.canonicalKey)
        #expect(session.durationSeconds == 1800)
        #expect(session.pagesRead == 15)
        #expect(session.wordsRead == 4500)
        #expect(session.deviceId == "device-001")
        #expect(session.isRecovered == false)
    }

    @Test func bookFingerprintKeyMatchesFingerprint() {
        let session = ReadingSession(bookFingerprint: Self.sampleFP)
        #expect(session.bookFingerprintKey == Self.sampleFP.canonicalKey)
    }

    // MARK: - Default Values

    @Test func defaultsAreCorrect() {
        let session = ReadingSession(bookFingerprint: Self.sampleFP)
        #expect(session.endedAt == nil)
        #expect(session.durationSeconds == 0)
        #expect(session.pagesRead == nil)
        #expect(session.wordsRead == nil)
        #expect(session.startLocator == nil)
        #expect(session.endLocator == nil)
        #expect(session.isRecovered == false)
    }

    // MARK: - Recovered Session

    @Test func recoveredSessionFlag() {
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 300,
            isRecovered: true
        )
        #expect(session.isRecovered == true)
    }

    // MARK: - Locator Attachment

    @Test func sessionCanHaveStartAndEndLocators() {
        let startLoc = Locator(
            bookFingerprint: Self.sampleFP,
            href: "ch1.xhtml", progression: 0.0, totalProgression: 0.0,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let endLoc = Locator(
            bookFingerprint: Self.sampleFP,
            href: "ch3.xhtml", progression: 0.8, totalProgression: 0.15,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 3600,
            startLocator: startLoc,
            endLocator: endLoc
        )
        #expect(session.startLocator != nil)
        #expect(session.endLocator != nil)
        #expect(session.endLocator?.progression == 0.8)
    }

    // MARK: - Edge Cases

    @Test func zeroDurationSession() {
        let session = ReadingSession(bookFingerprint: Self.sampleFP, durationSeconds: 0)
        #expect(session.durationSeconds == 0)
    }

    @Test func veryLongSession() {
        // 24 hours in seconds
        let session = ReadingSession(bookFingerprint: Self.sampleFP, durationSeconds: 86400)
        #expect(session.durationSeconds == 86400)
    }
}
