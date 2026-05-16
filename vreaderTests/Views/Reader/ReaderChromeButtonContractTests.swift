// Purpose: Feature #60 WI-6 — pins the button-slot contract for the
// new reader chrome (top + bottom). The chrome views consume these
// enums declaratively so the order in which buttons appear matches
// the design bundle's `vreader-reader.jsx` definitions:
//
//   - Top: back / title / bookmark / more
//   - Bottom toolbar: Contents / Notes / Display / AI (AI gets the
//     accent)
//
// A regression that swaps the order, drops a case, or adds an
// unrelated case fails here before any SwiftUI render path runs.

import Testing
@testable import vreader

@Suite("Feature #60 WI-6 — Reader chrome button contract")
struct ReaderChromeButtonContractTests {

    // MARK: - Top chrome slots

    @Test("Top chrome has exactly 4 slots")
    func topChromeSlotCount() {
        #expect(ReaderTopChromeSlot.allCases.count == 4)
    }

    @Test("Top chrome slot order matches design bundle")
    func topChromeOrder() {
        // Mirrors `vreader-reader.jsx:ReaderTopChrome` layout:
        // left → leading back · title (center, flex) · trailing
        // bookmark + more.
        #expect(ReaderTopChromeSlot.allCases == [.back, .title, .bookmark, .more])
    }

    // MARK: - Bottom chrome toolbar buttons

    @Test("Bottom chrome toolbar has exactly 4 buttons")
    func bottomChromeButtonCount() {
        #expect(ReaderBottomChromeButton.allCases.count == 4)
    }

    @Test("Bottom chrome button order matches design bundle")
    func bottomChromeOrder() {
        // Mirrors `vreader-reader.jsx:ReaderBottomChrome` toolbar
        // array — TOC / Highlights (Notes) / Aa (Display) / Sparkle
        // (AI). AI is the accent slot.
        #expect(ReaderBottomChromeButton.allCases == [.contents, .notes, .display, .ai])
    }

    @Test("AI is the accent button in the bottom toolbar")
    func bottomChromeAIAccent() {
        // The design renders only one accent button in the bottom
        // toolbar (`accent: true` in the JSX). Pin which one.
        #expect(ReaderBottomChromeButton.ai.isAccent)
        #expect(!ReaderBottomChromeButton.contents.isAccent)
        #expect(!ReaderBottomChromeButton.notes.isAccent)
        #expect(!ReaderBottomChromeButton.display.isAccent)
    }

    // MARK: - Accessibility identifiers

    @Test("Top chrome slots expose stable accessibility identifiers")
    func topChromeAccessibilityIdentifiers() {
        // XCUITest harnesses + verify-cron snapshots rely on these
        // identifiers; pin them so renames surface here.
        #expect(ReaderTopChromeSlot.back.accessibilityIdentifier == "readerBackButton")
        #expect(ReaderTopChromeSlot.title.accessibilityIdentifier == "readerTitleLabel")
        #expect(ReaderTopChromeSlot.bookmark.accessibilityIdentifier == "readerBookmarkButton")
        #expect(ReaderTopChromeSlot.more.accessibilityIdentifier == "readerMoreButton")
    }

    @Test("Bottom chrome buttons expose stable accessibility identifiers")
    func bottomChromeAccessibilityIdentifiers() {
        #expect(ReaderBottomChromeButton.contents.accessibilityIdentifier == "readerContentsButton")
        #expect(ReaderBottomChromeButton.notes.accessibilityIdentifier == "readerNotesButton")
        #expect(ReaderBottomChromeButton.display.accessibilityIdentifier == "readerDisplayButton")
        #expect(ReaderBottomChromeButton.ai.accessibilityIdentifier == "readerAIButton")
    }
}
