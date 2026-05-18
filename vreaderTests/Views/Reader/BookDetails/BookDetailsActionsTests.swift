// Purpose: Feature #61 WI-4 — pins the Book Details sheet's Actions
// card composition and the fingerprint-copy contract.
//
// The action-row composition (three rows; the cover row's label
// tracking `hasCover`) is a pure projection of `BookDetailsSheet`.
// `copyFingerprintToPasteboard()` is the one action with an
// observable, render-free effect — it must write the *full*
// fingerprint key (not the middle-truncated display string) to the
// system pasteboard.
//
// @coordinates-with: BookDetailsSheet.swift, BookDetailsSheet+Actions.swift,
//   BookDetailsActionRow.swift

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("Feature #61 WI-4 — Book Details actions")
@MainActor
struct BookDetailsActionsTests {

    // MARK: - Fixtures

    private func makeItem(
        fingerprintKey: String = "epub:deadbeefdeadbeef:204800",
        coverImagePath: String? = "covers/sample.jpg"
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: fingerprintKey,
            title: "Sample Book",
            author: "Jane Austen",
            coverImagePath: coverImagePath,
            format: "epub",
            fileByteCount: 204_800,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: 0,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            collectionNames: [],
            totalPageCount: 100
        )
    }

    private func makeSheet(_ book: LibraryBookItem) -> BookDetailsSheet {
        BookDetailsSheet(
            book: book,
            theme: .paper,
            coverPickCoordinator: CoverPickCoordinator(),
            onExportAnnotations: {}
        )
    }

    // MARK: - Actions card composition

    @Test("Actions card exposes exactly three rows in design order")
    func actionRowsAreThreeInOrder() {
        let sheet = makeSheet(makeItem())
        #expect(sheet.actionRows.map(\.kind) == [.cover, .share, .exportAnnotations])
    }

    @Test("Cover action label is 'Replace cover…' when the book has a cover")
    func coverActionLabelWhenHasCover() {
        let sheet = makeSheet(makeItem(coverImagePath: "covers/sample.jpg"))
        #expect(
            sheet.actionRows.first { $0.kind == .cover }?.label == "Replace cover\u{2026}")
    }

    @Test("Cover action label is 'Add cover…' when the book has no cover")
    func coverActionLabelWhenNoCover() {
        let sheet = makeSheet(makeItem(coverImagePath: nil))
        #expect(
            sheet.actionRows.first { $0.kind == .cover }?.label == "Add cover\u{2026}")
    }

    @Test("Share and Export action rows carry the design labels")
    func shareAndExportLabels() {
        let sheet = makeSheet(makeItem())
        #expect(sheet.actionRows.first { $0.kind == .share }?.label == "Share book\u{2026}")
        let export = sheet.actionRows.first { $0.kind == .exportAnnotations }
        #expect(export?.label == "Export annotations\u{2026}")
        #expect(export?.sublabel == "Markdown \u{00b7} JSON \u{00b7} VReader JSON")
    }

    // MARK: - Fingerprint copy

    @Test("Fingerprint copy writes the full fingerprint key to the pasteboard")
    func copyFingerprintWritesFullKeyToPasteboard() {
        let key =
            "epub:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:204800"
        let sheet = makeSheet(makeItem(fingerprintKey: key))
        // Seed a sentinel so a pass cannot come from stale pasteboard state.
        UIPasteboard.general.string = "book-details-copy-sentinel"
        sheet.copyFingerprintToPasteboard()
        #expect(UIPasteboard.general.string == key)
        // The copy payload is the FULL key, not the middle-truncated
        // value the Fingerprint row displays.
        #expect(UIPasteboard.general.string != sheet.viewModel.fingerprintDisplay)
    }

    // MARK: - Action routing

    @Test("Cover action arms the cover-pick coordinator at this book")
    func coverActionPresentsCoverPickerForBook() {
        let book = makeItem()
        let coordinator = CoverPickCoordinator()
        let sheet = BookDetailsSheet(
            book: book, theme: .paper,
            coverPickCoordinator: coordinator, onExportAnnotations: {})
        #expect(coordinator.bookForCover == nil)
        sheet.handleAction(.cover)
        // `present(for:)` targets the PhotosPicker flow at exactly this
        // book (its `coverPicker` modifier presents off `bookForCover`).
        #expect(coordinator.bookForCover == book)
    }

    @Test("Export action invokes the host's export route")
    func exportActionInvokesHostRoute() {
        var exportRouteFired = false
        let sheet = BookDetailsSheet(
            book: makeItem(), theme: .paper,
            coverPickCoordinator: CoverPickCoordinator(),
            onExportAnnotations: { exportRouteFired = true })
        sheet.handleAction(.exportAnnotations)
        #expect(exportRouteFired)
    }
}
