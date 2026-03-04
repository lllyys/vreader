// Purpose: Test fixtures for schema migration testing.
// Each schema version should have corresponding fixture data
// that exercises all model fields and relationships.
//
// Layout:
// - vreaderTests/Fixtures/Migration/MigrationFixtures.swift — fixture factory
// - Future: vreaderTests/Fixtures/Migration/V1toV2/ — migration test data

import Foundation
@testable import vreader

/// Factory for creating test fixture data for migration testing.
enum MigrationFixtures {

    // MARK: - DocumentFingerprint Fixtures

    static func sampleEpubFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "abc123def456789012345678901234567890123456789012345678901234abcd",
            fileByteCount: 1_048_576,
            format: .epub
        )
    }

    static func samplePdfFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "def456abc789012345678901234567890123456789012345678901234567ef01",
            fileByteCount: 2_097_152,
            format: .pdf
        )
    }

    static func sampleTxtFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "789012345678901234567890123456789012345678901234567890123456abcd",
            fileByteCount: 32_768,
            format: .txt
        )
    }

    // MARK: - Locator Fixtures

    static func sampleEpubLocator() -> Locator {
        Locator(
            bookFingerprint: sampleEpubFingerprint(),
            href: "chapter1.xhtml",
            progression: 0.42,
            totalProgression: 0.15,
            cfi: "/6/4[chap01]!/4/2/1:0",
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: "It was a dark and stormy night",
            textContextBefore: "Chapter 1. ",
            textContextAfter: ", the wind howled."
        )
    }

    static func samplePdfLocator() -> Locator {
        Locator(
            bookFingerprint: samplePdfFingerprint(),
            href: nil,
            progression: nil,
            totalProgression: 0.05,
            cfi: nil,
            page: 7,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: "Introduction to algorithms",
            textContextBefore: nil,
            textContextAfter: nil
        )
    }

    static func sampleTxtLocator() -> Locator {
        Locator(
            bookFingerprint: sampleTxtFingerprint(),
            href: nil,
            progression: nil,
            totalProgression: 0.5,
            cfi: nil,
            page: nil,
            charOffsetUTF16: 1024,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: "Call me Ishmael",
            textContextBefore: nil,
            textContextAfter: ". Some years ago"
        )
    }

    static func sampleTxtRangeLocator() -> Locator {
        Locator(
            bookFingerprint: sampleTxtFingerprint(),
            href: nil,
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: 100,
            charRangeEndUTF16: 200,
            textQuote: "selected text",
            textContextBefore: "some ",
            textContextAfter: " more"
        )
    }

    // MARK: - ImportProvenance Fixtures

    static func sampleProvenance() -> ImportProvenance {
        ImportProvenance(
            source: .filesApp,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalURLBookmarkData: nil
        )
    }

    // MARK: - Book Fixtures

    static func sampleEpubBook() -> Book {
        Book(
            fingerprint: sampleEpubFingerprint(),
            title: "Sample EPUB Book",
            author: "Test Author",
            provenance: sampleProvenance()
        )
    }

    static func samplePdfBook() -> Book {
        Book(
            fingerprint: samplePdfFingerprint(),
            title: "Sample PDF Book",
            provenance: ImportProvenance(
                source: .icloudDrive,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                originalURLBookmarkData: Data([0x01, 0x02, 0x03])
            )
        )
    }

    // MARK: - ReadingSession Fixtures

    static func sampleSession(
        fingerprint: DocumentFingerprint? = nil,
        durationSeconds: Int = 1800,
        pagesRead: Int? = 10,
        wordsRead: Int? = 3000
    ) -> ReadingSession {
        let fp = fingerprint ?? sampleEpubFingerprint()
        return ReadingSession(
            bookFingerprint: fp,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            durationSeconds: durationSeconds,
            pagesRead: pagesRead,
            wordsRead: wordsRead,
            deviceId: "test-device-001"
        )
    }
}
