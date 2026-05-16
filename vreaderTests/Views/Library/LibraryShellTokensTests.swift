// Purpose: Contract tests for the feature #60 WI-9 Library-container
// shell tokens — the warm-paper background, nav-bar pill metrics, and
// filter-chip palette added to `LibraryCardTokens` for the container
// re-skin. Structural / token assertions only, not pixel snapshots.
//
// Design source: `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-library.jsx` — `LibraryScreen` (`#f7f4ee` shell, `pillBtn`),
// filter-chip block, search-bar block.
//
// @coordinates-with: LibraryCardTokens.swift, LibraryNavBar.swift,
//   LibraryFilterChips.swift, LibrarySearchBar.swift

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("LibraryShellTokens — feature #60 WI-9")
@MainActor
struct LibraryShellTokensTests {

    // MARK: - Shell background (design `#f7f4ee`)

    @Test("Shell background is the design warm paper #f7f4ee")
    func shellBackgroundMatchesDesign() {
        assertColor(LibraryCardTokens.shellBackground,
                    rgb: (0xf7, 0xf4, 0xee))
    }

    @Test("Shell background differs from the reader paper stop")
    func shellBackgroundDistinctFromReaderPaper() {
        // The file header documents the Library shell (#f7f4ee) is a
        // different shade from `ReaderThemeV2.paper` (#f4eee0). Pin the
        // distinction so a future refactor doesn't collapse them.
        let shell = LibraryCardTokens.shellBackground
            .resolve(in: EnvironmentValues())
        let readerPaper = ReaderThemeV2.paper.backgroundColor
        var rpR: CGFloat = 0, rpG: CGFloat = 0, rpB: CGFloat = 0, rpA: CGFloat = 0
        readerPaper.getRed(&rpR, green: &rpG, blue: &rpB, alpha: &rpA)
        let differs = abs(Double(shell.red) - Double(rpR)) > 0.001
            || abs(Double(shell.green) - Double(rpG)) > 0.001
            || abs(Double(shell.blue) - Double(rpB)) > 0.001
        #expect(differs)
    }

    // MARK: - Nav-bar pill button (design `pillBtn`)

    @Test("Nav-bar pill button is the design's 36pt square")
    func pillButtonSizeMatchesDesign() {
        #expect(LibraryCardTokens.navPillSize == 36)
    }

    @Test("Nav-bar pill corner radius is half the size (full capsule)")
    func pillButtonIsFullCapsule() {
        // Design: `borderRadius: 18` on a 36pt box — a circle.
        #expect(LibraryCardTokens.navPillCornerRadius
                == LibraryCardTokens.navPillSize / 2)
    }

    @Test("Nav-bar pill fill is the design warm wash rgba(60,40,20,0.06)")
    func pillButtonFillMatchesDesign() {
        assertColor(LibraryCardTokens.navPillBackground,
                    rgb: (0x3c, 0x28, 0x14), alpha: 0.06)
    }

    @Test("Nav-bar icon tint is the design dark brown #3a2913")
    func pillIconTintMatchesDesign() {
        assertColor(LibraryCardTokens.navIconTint,
                    rgb: (0x3a, 0x29, 0x13))
    }

    // MARK: - Title typography (design 36pt Source Serif 4)

    @Test("Library title uses the design 36pt size")
    func titleFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.titleFontSize == 36)
    }

    @Test("Section-header title uses the design 18pt size")
    func sectionHeaderFontSizeMatchesDesign() {
        // `Continue reading` + `All books` headers — design `fontSize: 18`.
        #expect(LibraryCardTokens.sectionHeaderFontSize == 18)
    }

    @Test("Subtitle uses the design 13pt size")
    func subtitleFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.subtitleFontSize == 13)
    }

    // MARK: - Filter chip (design filter-chip block)

    @Test("Filter chip is a full pill — design borderRadius:100")
    func filterChipIsPill() {
        #expect(LibraryCardTokens.filterChipCornerRadius >= 100)
    }

    @Test("Selected filter chip fill is the design near-black ink")
    func selectedChipFillMatchesDesign() {
        // Design: selected chip `background: #1d1a14` — the ink token.
        assertColor(LibraryCardTokens.filterChipSelectedBackground,
                    rgb: (0x1d, 0x1a, 0x14))
    }

    @Test("Unselected filter chip fill is the warm wash")
    func unselectedChipFillMatchesDesign() {
        assertColor(LibraryCardTokens.filterChipBackground,
                    rgb: (0x3c, 0x28, 0x14), alpha: 0.06)
    }

    @Test("Selected filter chip text is the warm-paper shell colour")
    func selectedChipTextMatchesDesign() {
        // Design: selected chip `color: #f7f4ee`.
        assertColor(LibraryCardTokens.filterChipSelectedText,
                    rgb: (0xf7, 0xf4, 0xee))
    }

    @Test("Filter chip text uses the design 13pt size")
    func filterChipFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.filterChipFontSize == 13)
    }

    // MARK: - Continue card (design ContinueCard 124×186)

    @Test("Continue card cover width matches design 124pt")
    func continueCardWidthMatchesDesign() {
        #expect(LibraryCardTokens.continueCardCoverWidth == 124)
    }

    @Test("Continue card cover height matches design 186pt")
    func continueCardHeightMatchesDesign() {
        #expect(LibraryCardTokens.continueCardCoverHeight == 186)
    }

    @Test("Continue card cover is the design 2:3 portrait proportion")
    func continueCardCoverIsPortrait() {
        let ratio = LibraryCardTokens.continueCardCoverWidth
            / LibraryCardTokens.continueCardCoverHeight
        #expect(ratio < 1.0)
        // 124/186 == 2/3 exactly.
        #expect(abs(Double(ratio) - 2.0 / 3.0) < 0.0001)
    }

    @Test("Continue card title uses the design 13.5pt size")
    func continueCardTitleFontSizeMatchesDesign() {
        #expect(LibraryCardTokens.continueCardTitleFontSize == 13.5)
    }

    // MARK: - Search bar (design search-bar block)

    @Test("Search field fill is the design warm wash rgba(60,40,20,0.06)")
    func searchFieldFillMatchesDesign() {
        assertColor(LibraryCardTokens.searchFieldBackground,
                    rgb: (0x3c, 0x28, 0x14), alpha: 0.06)
    }

    @Test("Search field corner radius matches design borderRadius:12")
    func searchFieldCornerRadiusMatchesDesign() {
        #expect(LibraryCardTokens.searchFieldCornerRadius == 12)
    }

    // MARK: - Color assertion helper

    private func assertColor(
        _ color: Color,
        rgb expected: (Int, Int, Int),
        alpha: Double = 1.0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let resolved = color.resolve(in: EnvironmentValues())
        let r = Int((resolved.red * 255).rounded())
        let g = Int((resolved.green * 255).rounded())
        let b = Int((resolved.blue * 255).rounded())
        #expect(r == expected.0, "red", sourceLocation: sourceLocation)
        #expect(g == expected.1, "green", sourceLocation: sourceLocation)
        #expect(b == expected.2, "blue", sourceLocation: sourceLocation)
        let a = Double(resolved.opacity)
        #expect(abs(a - alpha) < 0.02, "alpha",
                sourceLocation: sourceLocation)
    }
}
