// Purpose: Feature #56 WI-9 — pin the `ReaderTopChrome` extension
// that inserts `BilingualPill` next to the title. Two things matter:
// (1) the slot enum gains a `.bilingualPill` case with a stable
// accessibility identifier; (2) chrome's `showsBilingualPill`
// predicate flips based on the `bilingualActive` input.
//
// The pill is only rendered when bilingual mode is on for the open
// book; off → no pill. The chrome must not allocate the slot when
// off, so XCUITest doesn't pick up a hidden `readerBilingualPill`
// identifier and harnesses can use the pill's presence as the
// ground truth for bilingual state.
//
// @coordinates-with: ReaderTopChrome.swift, ReaderChromeButton.swift,
//   BilingualPill.swift

import Testing
@testable import vreader

@Suite("Feature #56 WI-9 — ReaderTopChrome bilingual pill slot")
struct ReaderTopChromeBilingualPillTests {

    @Test("Top chrome adds the bilingualPill slot between title and search")
    func slotInsertion() {
        // The pill sits inside the title block per the design; the
        // enum order pins its layout position relative to the other
        // slots. After WI-9 the enum reads:
        //   back · title · bilingualPill · search · bookmark · more
        #expect(ReaderTopChromeSlot.allCases == [
            .back,
            .title,
            .bilingualPill,
            .search,
            .bookmark,
            .more,
        ])
    }

    @Test("Total slot count is 6 after WI-9")
    func slotCount() {
        #expect(ReaderTopChromeSlot.allCases.count == 6)
    }

    @Test("bilingualPill slot exposes the readerBilingualPill identifier")
    func bilingualPillAccessibilityIdentifier() {
        #expect(ReaderTopChromeSlot.bilingualPill.accessibilityIdentifier ==
                "readerBilingualPill")
    }

    @Test("Pre-existing slot identifiers stay stable across the WI-9 cutover")
    func preExistingIdentifiersUnchanged() {
        // The XCUITest harnesses + verify-cron snapshots use these
        // identifiers; pin so an accidental WI-9 rename surfaces.
        #expect(ReaderTopChromeSlot.back.accessibilityIdentifier == "readerBackButton")
        #expect(ReaderTopChromeSlot.title.accessibilityIdentifier == "readerTitleLabel")
        #expect(ReaderTopChromeSlot.search.accessibilityIdentifier == "readerSearchButton")
        #expect(ReaderTopChromeSlot.bookmark.accessibilityIdentifier == "readerBookmarkButton")
        #expect(ReaderTopChromeSlot.more.accessibilityIdentifier == "readerMoreButton")
    }

    @Test("Chrome shows the pill when bilingual is active")
    func showsPillWhenBilingualActive() {
        #expect(ReaderTopChrome.shouldShowBilingualPill(
            bilingualActive: true,
            bilingualLanguage: "Chinese"
        ) == true)
    }

    @Test("Chrome hides the pill when bilingual is off")
    func hidesPillWhenBilingualOff() {
        // Off → never render the slot, regardless of the language
        // value (which may have been set by a previous session).
        #expect(ReaderTopChrome.shouldShowBilingualPill(
            bilingualActive: false,
            bilingualLanguage: "Chinese"
        ) == false)
        #expect(ReaderTopChrome.shouldShowBilingualPill(
            bilingualActive: false,
            bilingualLanguage: nil
        ) == false)
    }

    @Test("Chrome hides the pill when active but no language is resolved")
    func hidesPillWhenLanguageIsNil() {
        // Defensive — the host should always pass a language when
        // active, but a nil during transition must not render an
        // empty pill.
        #expect(ReaderTopChrome.shouldShowBilingualPill(
            bilingualActive: true,
            bilingualLanguage: nil
        ) == false)
    }

    @Test("Chrome resolves the pill language with registry fallback")
    func chromeResolvesPillLanguage() {
        // Unknown language at runtime degrades to the registry's
        // first entry — same fallback the pill uses internally.
        #expect(ReaderTopChrome.resolvedPillLanguage(for: "Klingon") == "Chinese")
        #expect(ReaderTopChrome.resolvedPillLanguage(for: "Japanese") == "Japanese")
    }
}
