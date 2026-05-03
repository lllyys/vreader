// Purpose: Tests for DebugPositionResolver — pure parser that turns
// `?position=<value>` strings into typed DebugPosition values per book
// format. Feature #49 WI-7a.

#if DEBUG

import XCTest
@testable import vreader

final class DebugPositionResolverTests: XCTestCase {

    // MARK: - TXT / MD (UTF-16 offsets)

    func test_resolve_txt_validOffset_returnsCharOffset() throws {
        let pos = try DebugPositionResolver.resolve("1024", format: "txt")
        XCTAssertEqual(pos, .charOffsetUTF16(1024))
    }

    func test_resolve_md_acceptsSameShapeAsTxt() throws {
        let pos = try DebugPositionResolver.resolve("0", format: "md")
        XCTAssertEqual(pos, .charOffsetUTF16(0))
    }

    func test_resolve_txt_negativeOffset_throws() {
        XCTAssertThrowsError(try DebugPositionResolver.resolve("-1", format: "txt")) { error in
            guard case DebugPositionResolverError.invalidPositionForFormat(let format, let position, _) = error else {
                XCTFail("expected invalidPositionForFormat, got \(error)")
                return
            }
            XCTAssertEqual(format, "txt")
            XCTAssertEqual(position, "-1")
        }
    }

    func test_resolve_txt_nonNumeric_throws() {
        XCTAssertThrowsError(try DebugPositionResolver.resolve("foo", format: "txt"))
    }

    // MARK: - EPUB (CFI)

    func test_resolve_epub_cfiString_returnsEpubCFI() throws {
        let cfi = "epubcfi(/6/4!/4/1:0)"
        let pos = try DebugPositionResolver.resolve(cfi, format: "epub")
        XCTAssertEqual(pos, .epubCFI(cfi))
    }

    func test_resolve_epub_emptyString_throws() {
        XCTAssertThrowsError(try DebugPositionResolver.resolve("", format: "epub"))
    }

    // MARK: - AZW3 (Foliate CFI)

    func test_resolve_azw3_cfiString_returnsFoliateCFI() throws {
        let cfi = "epubcfi(/6/12!/4/3)"
        let pos = try DebugPositionResolver.resolve(cfi, format: "azw3")
        XCTAssertEqual(pos, .foliateCFI(cfi))
    }

    func test_resolve_azw3_emptyString_throws() {
        XCTAssertThrowsError(try DebugPositionResolver.resolve("", format: "azw3"))
    }

    // MARK: - PDF (1-based page)

    func test_resolve_pdf_validPage_returnsPdfPage() throws {
        let pos = try DebugPositionResolver.resolve("3", format: "pdf")
        XCTAssertEqual(pos, .pdfPage(3))
    }

    func test_resolve_pdf_pageZero_throws() {
        XCTAssertThrowsError(try DebugPositionResolver.resolve("0", format: "pdf")) { error in
            guard case DebugPositionResolverError.invalidPositionForFormat = error else {
                XCTFail("expected invalidPositionForFormat, got \(error)")
                return
            }
        }
    }

    func test_resolve_pdf_negativePage_throws() {
        XCTAssertThrowsError(try DebugPositionResolver.resolve("-1", format: "pdf"))
    }

    // MARK: - Unknown format

    func test_resolve_unknownFormat_throws() {
        XCTAssertThrowsError(try DebugPositionResolver.resolve("anything", format: "xyz")) { error in
            guard case DebugPositionResolverError.unknownFormat(let f) = error else {
                XCTFail("expected unknownFormat, got \(error)")
                return
            }
            XCTAssertEqual(f, "xyz")
        }
    }

    // MARK: - Case insensitivity

    func test_resolve_uppercaseFormat_normalizesToLowercase() throws {
        let pos = try DebugPositionResolver.resolve("42", format: "TXT")
        XCTAssertEqual(pos, .charOffsetUTF16(42))
    }
}

#endif
