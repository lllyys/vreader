// Purpose: Feature #60 WI-7a — pins the visible-action contract for
// the new `SelectionPopoverView` against the committed design bundle.
//
// The popover's bottom toolbar in `vreader-reader.jsx:475-491` lays
// out four actions in a fixed order: Note / Translate / Ask AI /
// Read. "Ask AI" carries the `primary: true` flag — it's the only
// accent slot in the toolbar.
//
// `SelectionPopoverActionRow` is a UI-presentation enum that
// declaratively lists those four slots. It maps each to:
// - the corresponding `SelectionPopoverAction` dispatch case (WI-3),
// - a localized label string,
// - a SF Symbol name,
// - an `isAccent: Bool` predicate.
//
// A regression that reorders, drops, or adds a slot — or that flips
// the accent target — fails here before any SwiftUI render runs.

import Testing
@testable import vreader

@Suite("Feature #60 WI-7a — SelectionPopover action row contract")
struct SelectionPopoverActionRowTests {

    // MARK: - Cardinality + order

    @Test("Action row has exactly 4 entries")
    func actionRowCount() {
        #expect(SelectionPopoverActionRow.allCases.count == 4)
    }

    @Test("Action row order matches design bundle (Note / Translate / Ask AI / Read)")
    func actionRowOrder() {
        #expect(SelectionPopoverActionRow.allCases == [.note, .translate, .askAI, .read])
    }

    // MARK: - Mapping to dispatch action (WI-3 enum)

    @Test("Each row maps to its SelectionPopoverAction dispatch case")
    func dispatchActionMapping() {
        #expect(SelectionPopoverActionRow.note.dispatchAction == .note)
        #expect(SelectionPopoverActionRow.translate.dispatchAction == .translate)
        #expect(SelectionPopoverActionRow.askAI.dispatchAction == .askAI)
        #expect(SelectionPopoverActionRow.read.dispatchAction == .read)
    }

    // MARK: - Accent slot (one and only one)

    @Test("Ask AI is the sole accent slot")
    func accentSlot() {
        // Design renders only one accented action (`primary: true` in
        // the JSX). Pin which one — protects against a future renamer
        // accidentally adding accent to the wrong row.
        #expect(SelectionPopoverActionRow.askAI.isAccent)
        #expect(!SelectionPopoverActionRow.note.isAccent)
        #expect(!SelectionPopoverActionRow.translate.isAccent)
        #expect(!SelectionPopoverActionRow.read.isAccent)
        #expect(SelectionPopoverActionRow.allCases.filter(\.isAccent).count == 1)
    }

    // MARK: - Display strings + symbol names are non-empty

    @Test("Each row carries a non-empty display label")
    func labelsNonEmpty() {
        for row in SelectionPopoverActionRow.allCases {
            #expect(!row.label.isEmpty, "row \(row) has empty label")
        }
    }

    @Test("Each row carries a non-empty SF Symbol name")
    func symbolNamesNonEmpty() {
        for row in SelectionPopoverActionRow.allCases {
            #expect(!row.systemImage.isEmpty, "row \(row) has empty systemImage")
        }
    }

    @Test("SF Symbol names are recognisable (no whitespace, leading-dot, or accidental spaces)")
    func symbolNamesWellFormed() {
        for row in SelectionPopoverActionRow.allCases {
            #expect(!row.systemImage.contains(" "), "row \(row) systemImage contains a space")
            #expect(!row.systemImage.hasPrefix("."), "row \(row) systemImage starts with '.'")
        }
    }

    // MARK: - Stable accessibility identifiers

    @Test("Each row exposes a stable accessibility identifier")
    func accessibilityIdentifiers() {
        // XCUITest + verify-cron snapshots look these up. Stable
        // contract — do not rename without updating every harness.
        #expect(SelectionPopoverActionRow.note.accessibilityIdentifier == "selectionPopoverNote")
        #expect(SelectionPopoverActionRow.translate.accessibilityIdentifier == "selectionPopoverTranslate")
        #expect(SelectionPopoverActionRow.askAI.accessibilityIdentifier == "selectionPopoverAskAI")
        #expect(SelectionPopoverActionRow.read.accessibilityIdentifier == "selectionPopoverRead")
    }
}
