// Purpose: Feature #65 WI-1 — composition tests for the re-skinned
// Summarize summary card (`AISummaryCard`). The v2 re-skin replaces
// the bare `ScrollView { Text }` + native "New Request" button with an
// accent-bordered card (sparkle uppercase label, serif body) carrying
// a Share + Regenerate chip footer.
//
// `AISummaryCard` is a pure presentational view — its honest
// unit-testable surface is composition, not closure plumbing. These
// tests force SwiftUI to materialise `body` for representative summary
// inputs (empty, long, CJK) across every `ReaderThemeV2` case so a
// re-skin regression that breaks the layout under a particular theme
// or input is caught without a render pass. The button-tap wiring
// (Share / Regenerate) is exercised by the Gate-5 XCUITest — the
// repo's standard unit-vs-UI split — so it is intentionally not
// re-asserted here with a closure-echo test.
//
// @coordinates-with: AISummaryCard.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("AI Summarize card re-skin — feature #65 WI-1")
@MainActor
struct AISummaryCardTests {

    // MARK: - Composition across themes

    /// Representative summary-body inputs the card must lay out:
    /// an empty string (no response yet rendered into the card),
    /// a long multi-paragraph string, and CJK text (no-space
    /// line-breaking — exercises the serif body's wrapping path).
    private static let summaryInputs: [String] = [
        "",
        String(repeating: "The novel opens with a famous declaration "
            + "about wealth and marriage, then widens to the Bennet "
            + "household. ", count: 24),
        "小说以一句关于财富与婚姻的著名宣言开篇，随后展开对班纳特一家的描写。",
    ]

    @Test(
        "The card body builds for every summary input across every theme",
        arguments: ReaderThemeV2.allCases
    )
    func cardBodyBuildsForEveryThemeAndInput(_ theme: ReaderThemeV2) {
        // A re-skin regression that breaks the card under a specific
        // theme/input combination (e.g. a token that traps, a layout
        // that crashes on empty text) surfaces here. All five themes ×
        // three inputs must materialise `body` without trapping.
        for summary in Self.summaryInputs {
            let card = AISummaryCard(
                summaryText: summary,
                theme: theme,
                onRegenerate: {},
                onShare: {}
            )
            _ = card.body
        }
    }

    @Test("The card body builds for an empty summary string")
    func cardBodyBuildsForEmptySummary() {
        // The summary card section can be reached while `.streaming`
        // before the first chunk arrives — `responseText` is "" then.
        // The card must still compose (the sparkle label + chip footer
        // render around an empty body).
        let card = AISummaryCard(
            summaryText: "",
            theme: .paper,
            onRegenerate: {},
            onShare: {}
        )
        _ = card.body
    }

    @Test("The card body builds for a long multi-paragraph summary")
    func cardBodyBuildsForLongSummary() {
        let long = String(
            repeating: "Netherfield Park is let at last, and the news "
                + "ripples through the neighbourhood. ",
            count: 40
        )
        let card = AISummaryCard(
            summaryText: long,
            theme: .dark,
            onRegenerate: {},
            onShare: {}
        )
        _ = card.body
    }

    @Test("The card body builds for CJK summary text")
    func cardBodyBuildsForCJKSummary() {
        // CJK has no inter-word spaces; the serif body's wrapping must
        // not trap. Pin that the card composes under a dark theme too.
        let card = AISummaryCard(
            summaryText: "小说以一句关于财富与婚姻的著名宣言开篇。",
            theme: .oled,
            onRegenerate: {},
            onShare: {}
        )
        _ = card.body
    }

    // MARK: - Save chip absence (plan §2.2)

    @Test("AISummaryCard exposes no Save callback (Save chip omitted)")
    func saveChipIsAbsent() {
        // The committed design's `SummaryView` draws three footer chips
        // (Save / Share / Regenerate). VReader has no saved-summaries
        // store, so plan §2.2 omits Save. `AISummaryCard`'s public
        // surface is exactly `summaryText` + `theme` + `onRegenerate`
        // + `onShare` — there is no `onSave`. This compile-time-shaped
        // test pins that the card was not built with a Save hook.
        let card = AISummaryCard(
            summaryText: "x",
            theme: .paper,
            onRegenerate: {},
            onShare: {}
        )
        // Exhaustive Mirror over the card's stored properties: assert
        // none is named `onSave`, and the four expected slots exist.
        let labels = Mirror(reflecting: card).children.compactMap { $0.label }
        #expect(!labels.contains("onSave"))
        #expect(labels.contains("summaryText"))
        #expect(labels.contains("theme"))
        #expect(labels.contains("onRegenerate"))
        #expect(labels.contains("onShare"))
    }
}
