// Purpose: Feature #90 WI-2 — pure-pinnable tests for the Summarize tab's
// language-control derivations: the `(Segment → SummaryDisplayMode)` mapping,
// the `activeSegment(for:)` derivation (which segment renders active for a
// given display mode, including the `.originalOnly` default → Single), and the
// popover row-identifier mapping over `BilingualLanguage.all`.
//
// These pin the control contract WI-2 wires into the view model (Single →
// `.translatedOnly`, Bilingual → `.interlinear`) without a SwiftUI render pass
// — the `AISummaryTabView.section(for:)` precedent. Tap UI is covered by the
// Gate-5 XCUITest / DebugBridge pass, not here.
//
// @coordinates-with: AISummaryLangRow.swift, AISummaryLangPopover.swift,
//   AIAssistantViewModel+BilingualSummary.swift, BilingualLanguage.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/bilingual-summarize-artboards.jsx`

import Testing
import Foundation
@testable import vreader

@Suite("AISummaryLangRow derivations — feature #90 WI-2")
struct AISummaryLangRowTests {

    // MARK: - Segment → SummaryDisplayMode mapping (the WI-2 contract)

    @Test func singleSegmentMapsToTranslatedOnly() {
        #expect(AISummaryLangRow.Segment.single.mode == .translatedOnly)
    }

    @Test func bilingualSegmentMapsToInterlinear() {
        #expect(AISummaryLangRow.Segment.bilingual.mode == .interlinear)
    }

    @Test func segmentsAreSingleThenBilingual() {
        #expect(AISummaryLangRow.Segment.allCases == [.single, .bilingual])
    }

    @Test func segmentIdentifiersMatchAccessibilityContract() {
        #expect(AISummaryLangRow.Segment.single.identifier == "summaryModeSingle")
        #expect(AISummaryLangRow.Segment.bilingual.identifier == "summaryModeBilingual")
    }

    @Test func segmentLabels() {
        #expect(AISummaryLangRow.Segment.single.label == "Single")
        #expect(AISummaryLangRow.Segment.bilingual.label == "Bilingual")
    }

    // MARK: - activeSegment(for:) derivation

    @Test func interlinearRendersBilingualSegmentActive() {
        #expect(AISummaryLangRow.activeSegment(for: .interlinear) == .bilingual)
    }

    @Test func translatedOnlyRendersSingleSegmentActive() {
        #expect(AISummaryLangRow.activeSegment(for: .translatedOnly) == .single)
    }

    /// The `.originalOnly` default has no distinct segment — it rests on Single
    /// (the design's default `layout='single'`).
    @Test func originalOnlyDefaultRendersSingleSegmentActive() {
        #expect(AISummaryLangRow.activeSegment(for: .originalOnly) == .single)
    }

    /// Round-trip: a segment's mode derives back to that same segment as active.
    @Test func segmentModeRoundTripsToActiveSegment() {
        for segment in AISummaryLangRow.Segment.allCases {
            #expect(AISummaryLangRow.activeSegment(for: segment.mode) == segment)
        }
    }

    // MARK: - Popover row identifiers

    @Test func popoverRowIdentifierIsKeyNamespaced() {
        let chinese = BilingualLanguage.findOrDefault(key: "Chinese")
        #expect(AISummaryLangPopover.rowIdentifier(chinese) == "summaryLang-Chinese")
    }

    @Test func popoverRowIdentifiersAreUniquePerLanguage() {
        let ids = BilingualLanguage.all.map { AISummaryLangPopover.rowIdentifier($0) }
        #expect(Set(ids).count == BilingualLanguage.all.count)
    }
}
