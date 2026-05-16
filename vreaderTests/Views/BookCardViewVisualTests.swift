// Purpose: Contract tests for the feature #60 WI-8 re-skin of
// `BookCardView` (Library grid card). These are structural / token
// assertions, NOT pixel snapshots — they pin the design constants the
// card view reads from `LibraryCardTokens` and confirm the card's
// accessibility contract is preserved across the re-skin.
//
// Design source: `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-library.jsx` (`GridView`) + `vreader-cover.jsx` (`BookCover`).
//
// @coordinates-with: BookCardView.swift, LibraryCardTokens.swift,
//   LibraryBookItem.swift, AccessibilityFormatters.swift

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("BookCardView visual tokens (feature #60 WI-8)")
@MainActor
struct BookCardViewVisualTests {

    // MARK: - Helpers

    private func makeBook(
        title: String = "Pride and Prejudice",
        author: String? = "Jane Austen",
        format: String = "epub",
        readingSeconds: Int = 0,
        progressFraction: Double? = nil
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: "epub:\(String(repeating: "a", count: 64)):1024",
            title: title,
            author: author,
            coverImagePath: nil,
            format: format,
            fileByteCount: 1024,
            addedAt: Date(timeIntervalSince1970: 0),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: readingSeconds,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            progressFraction: progressFraction
        )
    }

    // MARK: - Cover sizing per design

    @Test("Cover uses the design's 2:3 aspect ratio (110×165)")
    func coverAspectRatioMatchesDesign() {
        // `BookCover` default is 110 × 165 — the plan's WI-8 catalogue
        // pins "110 × 165 including spine + page-edge accents". Compared
        // with a tolerance because the token is a CGFloat and the
        // design ratio a Double — IEEE-754 round-trip can differ in the
        // last bit, and the load-bearing fact is the 2:3 proportion.
        let ratio = Double(LibraryCardTokens.coverAspectRatio)
        #expect(abs(ratio - 110.0 / 165.0) < 0.0001)
        // Sanity: the ratio is portrait (< 1) and is the 2:3 proportion.
        #expect(ratio < 1.0)
        #expect(abs(ratio - 2.0 / 3.0) < 0.0001)
    }

    @Test("Card cover corner radius matches design BookCover radius:4")
    func coverCornerRadiusMatchesDesign() {
        #expect(LibraryCardTokens.cardCoverCornerRadius == 4)
    }

    // MARK: - Typography per design

    @Test("Card title uses the design 12.5pt size")
    func cardTitleFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.cardTitleFontSize == 12.5)
    }

    @Test("Card author uses the design 10.5pt size")
    func cardAuthorFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.cardAuthorFontSize == 10.5)
    }

    @Test("Card stack spacing matches design gap:8")
    func cardStackSpacingMatchesDesign() {
        #expect(LibraryCardTokens.cardStackSpacing == 8)
    }

    @Test("Serif title font resolves to Source Serif 4 (or its fallback)")
    func serifTitleFontResolves() {
        // ReaderTypography guarantees a usable UIFont for .sourceSerif4
        // (the bundled face, or Georgia/system fallback). The bridge
        // must not crash and must carry the requested point size.
        let uiFont = ReaderTypography.body(for: .sourceSerif4, size: 12.5)
        #expect(uiFont.pointSize == 12.5)
        // The Font wrapper is constructible from it.
        _ = LibraryCardTokens.serifTitleFont(size: 12.5)
    }

    // MARK: - Palette per design

    @Test("Ink token is the design near-black #1d1a14")
    func inkTokenMatchesDesign() {
        assertColor(LibraryCardTokens.ink, rgb: (0x1d, 0x1a, 0x14))
    }

    @Test("Sub-text token is the design warm taupe #7a6a4a")
    func subTextTokenMatchesDesign() {
        assertColor(LibraryCardTokens.subText, rgb: (0x7a, 0x6a, 0x4a))
    }

    @Test("Accent token reuses the feature-#60 oxblood #8c2f2f")
    func accentTokenMatchesFeatureAccent() {
        assertColor(LibraryCardTokens.accent, rgb: (0x8c, 0x2f, 0x2f))
        // And is literally derived from AccentColor.light.
        #expect(AccentColor.light.hex == "#8c2f2f")
    }

    // MARK: - Accessibility contract preserved

    @Test("Card accessibility label is the VoiceOver book description")
    func cardAccessibilityLabelPreserved() {
        let book = makeBook(readingSeconds: 3600)
        let view = BookCardView(book: book)
        // The re-skin must keep routing through AccessibilityFormatters
        // so VoiceOver output is unchanged for XCUITest harnesses.
        let expected = AccessibilityFormatters.accessibleBookDescription(
            title: book.title,
            author: book.author,
            format: book.format,
            readingTimeSeconds: book.totalReadingSeconds
        )
        #expect(view.accessibilityLabelForTesting == expected)
        #expect(view.accessibilityHintForTesting == "Double tap to open")
    }

    @Test("Card builds for a book with no author")
    func cardBuildsWithoutAuthor() {
        let view = BookCardView(book: makeBook(author: nil))
        // No crash; label still well-formed.
        #expect(!view.accessibilityLabelForTesting.isEmpty)
    }

    @Test("Card builds across every supported format")
    func cardBuildsForEveryFormat() {
        for format in ["epub", "pdf", "txt", "md", "azw3"] {
            let view = BookCardView(book: makeBook(format: format))
            #expect(!view.accessibilityLabelForTesting.isEmpty)
        }
    }

    // MARK: - Reading-progress accents (feature #60 WI-8)

    @Test("Card with no reading position reports notStarted")
    func cardNotStartedWithoutProgress() {
        let view = BookCardView(book: makeBook(progressFraction: nil))
        #expect(view.progressStateForTesting == .notStarted)
    }

    @Test("Card with a zero fraction reports notStarted")
    func cardNotStartedAtZero() {
        let view = BookCardView(book: makeBook(progressFraction: 0))
        #expect(view.progressStateForTesting == .notStarted)
    }

    @Test("Card with a partial fraction reports inProgress")
    func cardInProgressAtPartialFraction() {
        let view = BookCardView(book: makeBook(progressFraction: 0.42))
        #expect(view.progressStateForTesting == .inProgress(0.42))
    }

    @Test("Card at full progress reports finished")
    func cardFinishedAtFullProgress() {
        let view = BookCardView(book: makeBook(progressFraction: 1.0))
        #expect(view.progressStateForTesting == .finished)
    }

    @Test("Finished green token is the design #3a6a5a")
    func finishedTokenMatchesDesign() {
        assertColor(LibraryCardTokens.finished, rgb: (0x3a, 0x6a, 0x5a))
    }

    // MARK: - Color assertion helper

    /// Asserts a SwiftUI `Color` resolves to the given 8-bit RGB triple
    /// (alpha 1.0) in the sRGB space. Tolerates float rounding.
    private func assertColor(
        _ color: Color,
        rgb expected: (Int, Int, Int),
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let resolved = color.resolve(in: EnvironmentValues())
        let r = Int((resolved.red * 255).rounded())
        let g = Int((resolved.green * 255).rounded())
        let b = Int((resolved.blue * 255).rounded())
        #expect(r == expected.0, "red", sourceLocation: sourceLocation)
        #expect(g == expected.1, "green", sourceLocation: sourceLocation)
        #expect(b == expected.2, "blue", sourceLocation: sourceLocation)
    }
}
