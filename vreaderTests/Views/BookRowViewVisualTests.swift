// Purpose: Contract tests for the feature #60 WI-8 re-skin of
// `BookRowView` (Library list row). Structural / token assertions, NOT
// pixel snapshots — they pin the design constants the row reads from
// `LibraryCardTokens`, confirm the row's accessibility contract is
// preserved, and confirm the feature-#47 file-state badge logic
// survives the re-skin (remote / downloading / failed / missing).
//
// Design source: `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-library.jsx` (`ListView`) + `vreader-cover.jsx` (`BookCover`).
//
// @coordinates-with: BookRowView.swift, LibraryCardTokens.swift,
//   LibraryBookItem.swift, BookFileState.swift, AccessibilityFormatters.swift

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("BookRowView visual tokens (feature #60 WI-8)")
@MainActor
struct BookRowViewVisualTests {

    // MARK: - Helpers

    private func makeBook(
        title: String = "The Beginning of Infinity",
        author: String? = "David Deutsch",
        format: String = "pdf",
        readingSeconds: Int = 0,
        fileState: BookFileState = .local,
        progressFraction: Double? = nil,
        lastReadAt: Date? = nil
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: "pdf:\(String(repeating: "b", count: 64)):2048",
            title: title,
            author: author,
            coverImagePath: nil,
            format: format,
            fileByteCount: 2048,
            addedAt: Date(timeIntervalSince1970: 0),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: readingSeconds,
            lastReadAt: lastReadAt,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            fileState: fileState,
            progressFraction: progressFraction
        )
    }

    // MARK: - Cover thumbnail sizing per design

    @Test("Row cover thumbnail is the design 44×62 size")
    func rowCoverSizeMatchesDesign() {
        // `ListView` calls BookCover with width:44, height:62, radius:3.
        #expect(LibraryCardTokens.rowCoverWidth == 44)
        #expect(LibraryCardTokens.rowCoverHeight == 62)
        #expect(LibraryCardTokens.rowCoverCornerRadius == 3)
    }

    @Test("Row cover thumbnail keeps a portrait aspect ratio")
    func rowCoverIsPortrait() {
        #expect(LibraryCardTokens.rowCoverWidth < LibraryCardTokens.rowCoverHeight)
    }

    // MARK: - Layout constants per design

    @Test("Row content spacing matches design gap:12")
    func rowContentSpacingMatchesDesign() {
        #expect(LibraryCardTokens.rowContentSpacing == 12)
    }

    @Test("List card corner radius matches design borderRadius:20")
    func listCardCornerRadiusMatchesDesign() {
        #expect(LibraryCardTokens.listCardCornerRadius == 20)
    }

    // MARK: - Typography per design

    @Test("Row title uses the design 15pt size")
    func rowTitleFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.rowTitleFontSize == 15)
    }

    @Test("Row author uses the design 12pt size")
    func rowAuthorFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.rowAuthorFontSize == 12)
    }

    @Test("Row format chip uses the design 9.5pt size")
    func rowChipFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.rowChipFontSize == 9.5)
    }

    // MARK: - Palette per design

    @Test("Format chip background is the design warm wash")
    func chipBackgroundMatchesDesign() {
        // rgba(60,40,20,0.08) → #3c2814 @ 0.08
        assertColor(
            LibraryCardTokens.chipBackground,
            rgb: (0x3c, 0x28, 0x14),
            alpha: 0.08
        )
    }

    @Test("List card surface is white per design")
    func listCardBackgroundIsWhite() {
        assertColor(LibraryCardTokens.listCardBackground, rgb: (0xff, 0xff, 0xff))
    }

    // MARK: - Accessibility contract preserved

    @Test("Row accessibility label is the VoiceOver book description")
    func rowAccessibilityLabelPreserved() {
        let book = makeBook(readingSeconds: 7200)
        let view = BookRowView(book: book)
        let expected = AccessibilityFormatters.accessibleBookDescription(
            title: book.title,
            author: book.author,
            format: book.format,
            readingTimeSeconds: book.totalReadingSeconds
        )
        #expect(view.accessibilityLabelForTesting == expected)
        #expect(view.accessibilityHintForTesting == "Double tap to open")
    }

    @Test("Row builds for a book with no author")
    func rowBuildsWithoutAuthor() {
        let view = BookRowView(book: makeBook(author: nil))
        #expect(!view.accessibilityLabelForTesting.isEmpty)
    }

    // MARK: - feature-#47 file-state badge survives the re-skin

    @Test("File-state badge label is preserved for every BookFileState")
    func fileStateBadgeLabelsPreserved() {
        // The re-skin re-skins the badge *container*; the per-state
        // text must be unchanged (feature #47 contract).
        let cases: [(BookFileState, String)] = [
            (.remoteOnly, "Remote"),
            (.downloading, "Downloading"),
            (.failed, "Retry"),
            (.missingRemote, "Missing"),
        ]
        for (state, expectedText) in cases {
            let view = BookRowView(book: makeBook(fileState: state))
            #expect(
                view.fileStateBadgeTextForTesting == expectedText,
                "state \(state)"
            )
        }
    }

    @Test("Local file-state shows the format badge, not a transfer label")
    func localFileStateShowsFormatBadge() {
        let view = BookRowView(book: makeBook(format: "epub", fileState: .local))
        #expect(view.fileStateBadgeTextForTesting == "EPUB")
    }

    @Test("File-state symbol is preserved for every non-local state")
    func fileStateBadgeSymbolsPreserved() {
        let cases: [(BookFileState, String)] = [
            (.remoteOnly, "cloud"),
            (.downloading, "arrow.down.circle"),
            (.failed, "exclamationmark.icloud"),
            (.missingRemote, "xmark.icloud"),
        ]
        for (state, expectedSymbol) in cases {
            let view = BookRowView(book: makeBook(fileState: state))
            #expect(
                view.fileStateBadgeSymbolForTesting == expectedSymbol,
                "state \(state)"
            )
        }
    }

    @Test("Local file-state has no transfer symbol")
    func localFileStateHasNoSymbol() {
        let view = BookRowView(book: makeBook(fileState: .local))
        #expect(view.fileStateBadgeSymbolForTesting == nil)
    }

    // MARK: - Reading-progress display (feature #60 WI-8)

    @Test("Row with no reading position shows no progress span")
    func rowNotStartedHasNoSpan() {
        let view = BookRowView(book: makeBook(progressFraction: nil))
        #expect(view.progressStateForTesting == .notStarted)
        #expect(view.progressMetadataTextForTesting == nil)
    }

    @Test("Row in progress shows percent and a relative last-read")
    func rowInProgressShowsPercentAndLastRead() {
        let view = BookRowView(book: makeBook(
            progressFraction: 0.37,
            lastReadAt: Date(timeIntervalSinceNow: -3 * 86_400)
        ))
        // The relative suffix shifts with run time; the percent prefix
        // and separator are the deterministic part of the contract.
        #expect(view.progressMetadataTextForTesting?.hasPrefix("37% · ") == true)
    }

    @Test("Row in progress with no last-read shows percent only")
    func rowInProgressNoLastReadShowsPercentOnly() {
        let view = BookRowView(book: makeBook(
            progressFraction: 0.6, lastReadAt: nil
        ))
        #expect(view.progressMetadataTextForTesting == "60%")
    }

    @Test("Row at full progress shows the Finished label")
    func rowFinishedShowsFinishedLabel() {
        let view = BookRowView(book: makeBook(progressFraction: 1.0))
        #expect(view.progressStateForTesting == .finished)
        #expect(view.progressMetadataTextForTesting == "Finished")
    }

    @Test("Progress-ring track is the design rgba(60,40,20,0.12)")
    func progressRingTrackMatchesDesign() {
        assertColor(
            LibraryCardTokens.progressRingTrack,
            rgb: (0x3c, 0x28, 0x14),
            alpha: 0.12
        )
    }

    // MARK: - Color assertion helper

    private func assertColor(
        _ color: Color,
        rgb expected: (Int, Int, Int),
        alpha expectedAlpha: Double = 1.0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let resolved = color.resolve(in: EnvironmentValues())
        let r = Int((resolved.red * 255).rounded())
        let g = Int((resolved.green * 255).rounded())
        let b = Int((resolved.blue * 255).rounded())
        #expect(r == expected.0, "red", sourceLocation: sourceLocation)
        #expect(g == expected.1, "green", sourceLocation: sourceLocation)
        #expect(b == expected.2, "blue", sourceLocation: sourceLocation)
        #expect(
            abs(Double(resolved.opacity) - expectedAlpha) < 0.01,
            "alpha",
            sourceLocation: sourceLocation
        )
    }
}
