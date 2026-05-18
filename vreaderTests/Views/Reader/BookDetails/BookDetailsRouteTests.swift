// Purpose: Feature #61 WI-3 — pins the reader More-menu → host-effect
// route and the Book Details sheet's metadata-row composition.
//
// The route half: `ReaderMoreMenuEffect(row:)` is the pure decision
// `ReaderContainerView.handleMoreMenuAction(_:)` switches on. The
// `@State` mutation it drives is not unit-testable without a SwiftUI
// render path, so the decision is extracted here. The contract these
// tests guard is feature #61's behavior change — the `.bookDetails`
// row now resolves to the dedicated Book Details sheet
// (`.presentBookDetails`), replacing the feature-#60 WI-6c interim
// that routed it to the reader settings panel.
//
// The composition half: `BookDetailsSheet.metadataRows` is the row
// list the sheet body renders. The Pages row is omitted when the book
// has no usable page count (plan Risk 1) — pinned here.
//
// @coordinates-with: ReaderMoreMenuEffect.swift, ReaderMoreMenuRow.swift,
//   BookDetailsSheet.swift, BookDetailsMetadataRow.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #61 WI-3 — Book Details route + sheet composition")
struct BookDetailsRouteTests {

    // MARK: - Fixtures

    /// Builds a `LibraryBookItem` with sensible defaults; individual
    /// tests override only the field under test.
    private func makeItem(
        title: String = "Sample Book",
        author: String? = "Jane Austen",
        coverImagePath: String? = "covers/sample.jpg",
        format: String = "epub",
        fileByteCount: Int64 = 204_800,
        collectionNames: [String] = ["Fiction"],
        totalPageCount: Int? = 312
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey:
                "epub:0000000000000000000000000000000000000000000000000000000000000000:204800",
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

    // MARK: - Route — the feature #61 behavior change

    @Test("Book details row routes to the dedicated Book Details sheet")
    func bookDetailsRoutesToBookDetailsSheet() {
        // Feature #60 WI-6c routed `.bookDetails` to the reader settings
        // panel as an interim (`showSettings = true`); feature #61 gives
        // it a dedicated surface. Pin the new destination.
        #expect(ReaderMoreMenuEffect(row: .bookDetails) == .presentBookDetails)
    }

    @Test("Book details effect is distinct from every other row's effect")
    func bookDetailsEffectIsDistinct() {
        // The settings interim is gone — `.bookDetails` must not collapse
        // onto another row's effect (a regression would re-route it).
        let bookDetails = ReaderMoreMenuEffect(row: .bookDetails)
        for row in ReaderMoreMenuRow.allCases where row != .bookDetails {
            #expect(ReaderMoreMenuEffect(row: row) != bookDetails)
        }
    }

    @Test("Each More-menu row resolves to its host effect")
    func everyRowResolvesToItsEffect() {
        #expect(ReaderMoreMenuEffect(row: .readAloud) == .toggleReadAloud)
        #expect(ReaderMoreMenuEffect(row: .autoTurnPages) == .toggleAutoPageTurn)
        #expect(ReaderMoreMenuEffect(row: .bookDetails) == .presentBookDetails)
        #expect(ReaderMoreMenuEffect(row: .shareBook) == .presentShareSheet)
        #expect(ReaderMoreMenuEffect(row: .exportAnnotations) == .presentAnnotationsExport)
    }

    @Test("Every More-menu row maps to a distinct effect")
    func everyRowMapsToDistinctEffect() {
        // Exhaustive over the enum — a future row without a mapping, or a
        // duplicated mapping, fails here.
        let effects = ReaderMoreMenuRow.allCases.map { ReaderMoreMenuEffect(row: $0) }
        #expect(Set(effects).count == ReaderMoreMenuRow.allCases.count)
    }

    // MARK: - Metadata composition — Pages omitted when absent (Risk 1)

    @Test("Metadata rows include Pages when the book has a page count")
    func metadataRowsIncludePagesWhenCountPresent() {
        let sheet = BookDetailsSheet(book: makeItem(totalPageCount: 312), theme: .paper)
        let pages = sheet.metadataRows.first { $0.label == "Pages" }
        #expect(pages != nil)
        #expect(pages?.value == "312")
    }

    @Test("Metadata rows omit Pages when the book has no page count")
    func metadataRowsOmitPagesWhenCountNil() {
        let sheet = BookDetailsSheet(book: makeItem(totalPageCount: nil), theme: .paper)
        #expect(!sheet.metadataRows.contains { $0.label == "Pages" })
    }

    @Test("Metadata rows omit Pages when the page count is zero")
    func metadataRowsOmitPagesWhenCountZero() {
        // A zero page count (reflowable / un-indexed book) is treated the
        // same as absent — the row is dropped, not rendered as "0".
        let sheet = BookDetailsSheet(book: makeItem(totalPageCount: 0), theme: .paper)
        #expect(!sheet.metadataRows.contains { $0.label == "Pages" })
    }

    @Test("Metadata rows follow the design order (Format, Size, Pages, Fingerprint, Location)")
    func metadataRowsFollowDesignOrder() {
        let sheet = BookDetailsSheet(book: makeItem(totalPageCount: 312), theme: .paper)
        #expect(sheet.metadataRows.map(\.label) == [
            "Format", "Size", "Pages", "Fingerprint", "Location",
        ])
    }

    @Test("With Pages omitted the remaining rows keep their order")
    func metadataRowsKeepOrderWithoutPages() {
        let sheet = BookDetailsSheet(book: makeItem(totalPageCount: nil), theme: .paper)
        #expect(sheet.metadataRows.map(\.label) == [
            "Format", "Size", "Fingerprint", "Location",
        ])
    }

    @Test("Fingerprint row carries the copy accessory; Location carries reveal")
    func metadataRowAccessories() {
        let sheet = BookDetailsSheet(book: makeItem(), theme: .paper)
        #expect(sheet.metadataRows.first { $0.label == "Fingerprint" }?.accessory == .copy)
        #expect(sheet.metadataRows.first { $0.label == "Location" }?.accessory == .reveal)
        #expect(sheet.metadataRows.first { $0.label == "Format" }?.accessory == nil)
    }

    @Test("Metadata row values are projected from the view model")
    func metadataRowValuesMatchViewModel() {
        let book = makeItem(format: "epub", fileByteCount: 204_800)
        let sheet = BookDetailsSheet(book: book, theme: .paper)
        let vm = BookDetailsViewModel(book: book)
        #expect(sheet.metadataRows.first { $0.label == "Format" }?.value == vm.formatDisplay)
        #expect(sheet.metadataRows.first { $0.label == "Size" }?.value == vm.fileSizeDisplay)
        #expect(sheet.metadataRows.first { $0.label == "Fingerprint" }?.value == vm.fingerprintDisplay)
        #expect(sheet.metadataRows.first { $0.label == "Location" }?.value == vm.locationDisplay)
    }
}
