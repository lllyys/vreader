// Purpose: Unit tests for BookDetailsViewModel — feature #61 WI-1.
// Verifies the LibraryBookItem -> display-string mapping for the reader
// Book Details sheet: format display, file size, page count, fingerprint
// truncation, long-title detection, cover presence, tags, author fallback.

import Testing
import Foundation
@testable import vreader

@Suite("BookDetailsViewModel")
struct BookDetailsViewModelTests {

    /// Builds a `LibraryBookItem` with sensible defaults; individual
    /// tests override only the field under test.
    private func makeItem(
        fingerprintKey: String =
            "epub:0000000000000000000000000000000000000000000000000000000000000000:204800",
        title: String = "Sample Book",
        author: String? = "Jane Austen",
        coverImagePath: String? = "covers/sample.jpg",
        format: String = "epub",
        fileByteCount: Int64 = 204_800,
        totalPageCount: Int? = 312,
        collectionNames: [String] = ["Fiction", "Classics"]
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: fingerprintKey,
            title: title,
            author: author,
            coverImagePath: coverImagePath,
            format: format,
            fileByteCount: fileByteCount,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: 0,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            collectionNames: collectionNames,
            totalPageCount: totalPageCount
        )
    }

    @Test func mapsBasicFields() {
        let vm = BookDetailsViewModel(book: makeItem())
        #expect(vm.title == "Sample Book")
        #expect(vm.author == "Jane Austen")
        #expect(vm.tags == ["Fiction", "Classics"])
        #expect(vm.hasCover == true)
    }

    @Test func authorFallsBackWhenNil() {
        #expect(BookDetailsViewModel(book: makeItem(author: nil)).author == "Unknown Author")
    }

    @Test func hasCoverFalseWhenNoCoverPath() {
        #expect(BookDetailsViewModel(book: makeItem(coverImagePath: nil)).hasCover == false)
    }

    @Test(arguments: [
        ("epub", "EPUB"), ("pdf", "PDF"), ("txt", "TXT"),
        ("md", "Markdown"), ("azw3", "AZW3"),
    ])
    func formatDisplayMapsPerFormat(_ raw: String, _ expected: String) {
        #expect(BookDetailsViewModel(book: makeItem(format: raw)).formatDisplay == expected)
    }

    @Test func fileSizeDisplayFormatsBytes() {
        let vm = BookDetailsViewModel(book: makeItem(fileByteCount: 204_800))
        #expect(vm.fileSizeDisplay == FileSizeFormatter.format(byteCount: 204_800))
    }

    @Test func fileSizeDisplayUnknownForZeroBytes() {
        #expect(BookDetailsViewModel(book: makeItem(fileByteCount: 0)).fileSizeDisplay == "Unknown")
    }

    @Test func pagesDisplayPresentWhenCountSet() {
        #expect(BookDetailsViewModel(book: makeItem(totalPageCount: 312)).pagesDisplay == "312")
    }

    @Test func pagesDisplayNilWhenCountNil() {
        #expect(BookDetailsViewModel(book: makeItem(totalPageCount: nil)).pagesDisplay == nil)
    }

    @Test func pagesDisplayNilWhenCountZero() {
        // An indexed book with a zero page count must omit the Pages row,
        // not render "0" — zero is treated the same as an absent count.
        #expect(BookDetailsViewModel(book: makeItem(totalPageCount: 0)).pagesDisplay == nil)
    }

    @Test func pagesDisplayNilWhenCountNegative() {
        // A negative page count (degenerate index data) is suppressed the
        // same as zero — pins the documented `> 0` boundary against a
        // regression to `>= 0`.
        #expect(BookDetailsViewModel(book: makeItem(totalPageCount: -1)).pagesDisplay == nil)
    }

    @Test func fingerprintFullIsTheRawKey() {
        let key = "txt:short:1"
        #expect(BookDetailsViewModel(book: makeItem(fingerprintKey: key)).fingerprintFull == key)
    }

    @Test func fingerprintDisplayMiddleTruncatesLongKeys() {
        let key = "epub:" + String(repeating: "a", count: 64) + ":204800"
        let vm = BookDetailsViewModel(book: makeItem(fingerprintKey: key))
        #expect(vm.fingerprintDisplay.contains("…"))
        #expect(vm.fingerprintDisplay.hasPrefix(String(key.prefix(14))))
        #expect(vm.fingerprintDisplay.hasSuffix(String(key.suffix(8))))
        #expect(vm.fingerprintDisplay.count < key.count)
    }

    @Test func fingerprintDisplayLeavesShortKeysIntact() {
        let key = "txt:short:1"
        #expect(BookDetailsViewModel(book: makeItem(fingerprintKey: key)).fingerprintDisplay == key)
    }

    @Test func isLongTitleBoundary() {
        #expect(BookDetailsViewModel(book: makeItem(title: String(repeating: "x", count: 33))).isLongTitle == true)
        #expect(BookDetailsViewModel(book: makeItem(title: String(repeating: "x", count: 32))).isLongTitle == false)
        #expect(BookDetailsViewModel(book: makeItem(title: "Short")).isLongTitle == false)
    }

    @Test func isLongTitleCountsCharactersNotBytes() {
        // 33 CJK characters — long by Character count even though it is
        // many more UTF-8 bytes.
        #expect(BookDetailsViewModel(book: makeItem(title: String(repeating: "字", count: 33))).isLongTitle == true)
    }

    @Test func emptyTagsWhenNoCollections() {
        #expect(BookDetailsViewModel(book: makeItem(collectionNames: [])).tags == [])
    }

    @Test func locationDisplayDerivesFromResolvedFileURL() {
        let vm = BookDetailsViewModel(book: makeItem(
            fingerprintKey: "epub:deadbeef:100", format: "epub"))
        #expect(vm.locationDisplay.hasPrefix("ImportedBooks/"))
        #expect(vm.locationDisplay.hasSuffix(".epub"))
    }
}
