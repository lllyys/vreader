// Purpose: Shared test helpers for WI-9 bookmark/highlight/annotation tests.

import Foundation
@testable import vreader

// MARK: - Fixtures

let wi9EPUBFingerprint = DocumentFingerprint(
    contentSHA256: "wi9_test_epub_sha256_00000000000000000000000000000000000000000000",
    fileByteCount: 5000,
    format: .epub
)

let wi9TXTFingerprint = DocumentFingerprint(
    contentSHA256: "wi9_test_txt_sha256_000000000000000000000000000000000000000000000",
    fileByteCount: 3000,
    format: .txt
)

let wi9PDFFingerprint = DocumentFingerprint(
    contentSHA256: "wi9_test_pdf_sha256_000000000000000000000000000000000000000000000",
    fileByteCount: 8000,
    format: .pdf
)

// MARK: - Locator Helpers

func makeEPUBLocator(
    fingerprint: DocumentFingerprint = wi9EPUBFingerprint,
    href: String = "chapter1.xhtml",
    progression: Double = 0.5
) -> Locator {
    LocatorFactory.epub(
        fingerprint: fingerprint,
        href: href,
        progression: progression
    )!
}

func makeTXTLocator(
    fingerprint: DocumentFingerprint = wi9TXTFingerprint,
    offset: Int = 100
) -> Locator {
    LocatorFactory.txtPosition(
        fingerprint: fingerprint,
        charOffsetUTF16: offset
    )!
}

func makeTXTRangeLocator(
    fingerprint: DocumentFingerprint = wi9TXTFingerprint,
    start: Int = 10,
    end: Int = 50,
    sourceText: String? = nil
) -> Locator {
    LocatorFactory.txtRange(
        fingerprint: fingerprint,
        charRangeStartUTF16: start,
        charRangeEndUTF16: end,
        sourceText: sourceText
    )!
}

func makePDFLocator(
    fingerprint: DocumentFingerprint = wi9PDFFingerprint,
    page: Int = 0
) -> Locator {
    LocatorFactory.pdf(
        fingerprint: fingerprint,
        page: page
    )!
}

// MARK: - Record Helpers

func makeBookmarkRecord(
    locator: Locator? = nil,
    title: String? = "Test Bookmark",
    createdAt: Date = Date()
) -> BookmarkRecord {
    let loc = locator ?? makeEPUBLocator()
    return BookmarkRecord(
        bookmarkId: UUID(),
        locator: loc,
        profileKey: "\(loc.bookFingerprint.canonicalKey):\(loc.canonicalHash)",
        title: title,
        createdAt: createdAt,
        updatedAt: createdAt
    )
}

func makeHighlightRecord(
    locator: Locator? = nil,
    selectedText: String = "highlighted text",
    color: String = "yellow",
    note: String? = nil,
    createdAt: Date = Date()
) -> HighlightRecord {
    let loc = locator ?? makeTXTRangeLocator()
    return HighlightRecord(
        highlightId: UUID(),
        locator: loc,
        profileKey: "\(loc.bookFingerprint.canonicalKey):\(loc.canonicalHash)",
        selectedText: selectedText,
        color: color,
        note: note,
        createdAt: createdAt,
        updatedAt: createdAt
    )
}

func makeAnnotationRecord(
    locator: Locator? = nil,
    content: String = "Test annotation",
    createdAt: Date = Date()
) -> AnnotationRecord {
    let loc = locator ?? makeEPUBLocator()
    return AnnotationRecord(
        annotationId: UUID(),
        locator: loc,
        profileKey: "\(loc.bookFingerprint.canonicalKey):\(loc.canonicalHash)",
        content: content,
        createdAt: createdAt,
        updatedAt: createdAt
    )
}

// MARK: - Test Errors

enum WI9TestError: Error, Sendable {
    case mockFailure
}
