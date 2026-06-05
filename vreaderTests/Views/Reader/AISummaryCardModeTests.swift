// Purpose: Feature #90 WI-3 — pure-pinnable tests for the bilingual summary
// card's body-mode selector: given `(SummaryDisplayMode, SummaryTranslationState)`
// it resolves which sub-view the card renders (original / target / interlinear /
// skeleton / dual-skeleton / error). This pins the render contract from the
// design's `SummaryCard` / `SummarySkeleton` / `SummaryError` artboards
// (`bilingual-summarize-artboards.jsx` :103-181) without a SwiftUI render pass —
// the `AISummaryTabView.section(for:)` / `AISummaryLangRow.activeSegment`
// precedent.
//
// @coordinates-with: AISummaryCard+Bilingual.swift, AISummaryCard.swift,
//   AIAssistantViewModel+BilingualSummary.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/bilingual-summarize-artboards.jsx`

import Testing
import Foundation
@testable import vreader

@Suite("AISummaryCard body-mode selector — feature #90 WI-3")
struct AISummaryCardModeTests {

    private func body(
        _ mode: SummaryDisplayMode,
        _ translation: SummaryTranslationState
    ) -> AISummaryCardBody {
        AISummaryCardBody.resolve(displayMode: mode, translation: translation)
    }

    // MARK: - .originalOnly — always the original, regardless of translation

    @Test func originalOnlyAlwaysRendersOriginal() {
        let states: [SummaryTranslationState] = [
            .none, .translating, .translated("译文"), .failed,
        ]
        for state in states {
            #expect(body(.originalOnly, state) == .original)
        }
    }

    // MARK: - .translatedOnly

    @Test func translatedOnlyTranslatedRendersTarget() {
        #expect(body(.translatedOnly, .translated("译文")) == .target)
    }

    @Test func translatedOnlyTranslatingRendersSkeleton() {
        #expect(body(.translatedOnly, .translating) == .skeleton)
    }

    @Test func translatedOnlyFailedRendersError() {
        #expect(body(.translatedOnly, .failed) == .error)
    }

    /// `.none` before a translation kicks → fall back to the original summary so
    /// the card never renders blank (the #56 silent-source-fallback precedent).
    @Test func translatedOnlyNoneFallsBackToOriginal() {
        #expect(body(.translatedOnly, .none) == .original)
    }

    // MARK: - .interlinear — original ALWAYS shows; the target half varies

    @Test func interlinearTranslatedRendersInterlinear() {
        #expect(body(.interlinear, .translated("译文")) == .interlinear)
    }

    @Test func interlinearTranslatingRendersDualSkeleton() {
        #expect(body(.interlinear, .translating) == .interlinearSkeleton)
    }

    @Test func interlinearFailedRendersInterlinearError() {
        #expect(body(.interlinear, .failed) == .interlinearError)
    }

    /// `.none` before a translation kicks → original only (no divider, no
    /// target) so the layout does not show an empty target slot.
    @Test func interlinearNoneRendersOriginalOnly() {
        #expect(body(.interlinear, .none) == .original)
    }

    // MARK: - Every (mode, state) pair resolves (no trap / exhaustiveness)

    @Test func everyPairResolvesToABody() {
        let modes: [SummaryDisplayMode] = [.originalOnly, .translatedOnly, .interlinear]
        let states: [SummaryTranslationState] = [
            .none, .translating, .translated("x"), .failed,
        ]
        for mode in modes {
            for state in states {
                _ = body(mode, state) // must not trap
            }
        }
    }

    // MARK: - The interlinear family always keeps the original visible

    @Test func interlinearBodiesAllKeepOriginalVisible() {
        #expect(AISummaryCardBody.interlinear.showsOriginal)
        #expect(AISummaryCardBody.interlinearSkeleton.showsOriginal)
        #expect(AISummaryCardBody.interlinearError.showsOriginal)
        #expect(AISummaryCardBody.original.showsOriginal)
        #expect(!AISummaryCardBody.target.showsOriginal)
        #expect(!AISummaryCardBody.skeleton.showsOriginal)
        #expect(!AISummaryCardBody.error.showsOriginal)
    }

    // MARK: - Translated-text extraction (Gate-4 Medium)

    /// The `.translated(String)` associated value drives the rendered target
    /// paragraph; pin the extraction so a broken pattern-match is caught (the
    /// selector tests alone never exercise the payload).
    @Test func translatedTextExtractsOnlyFromTranslated() {
        #expect(AISummaryCardBody.translatedText(from: .translated("译文")) == "译文")
        #expect(AISummaryCardBody.translatedText(from: .translated("")) == "")
        #expect(AISummaryCardBody.translatedText(from: .none) == nil)
        #expect(AISummaryCardBody.translatedText(from: .translating) == nil)
        #expect(AISummaryCardBody.translatedText(from: .failed) == nil)
    }

    // MARK: - CJK-font decision (Gate-4 Medium)

    /// The target paragraph uses the serif CJK stack for `.cjk` ONLY (design
    /// `useCjk`); `.rtl` / `.latin` / `.cyrillic` use the body serif. A wrong
    /// branch here would be invisible to the selector tests.
    @Test func cjkScriptSelectsTheCJKFont() {
        #expect(AISummaryCardBody.usesCJKFont(for: .cjk))
        #expect(!AISummaryCardBody.usesCJKFont(for: .latin))
        #expect(!AISummaryCardBody.usesCJKFont(for: .rtl))
        #expect(!AISummaryCardBody.usesCJKFont(for: .cyrillic))
    }
}
