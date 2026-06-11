// Purpose: Feature #56 WI-10 — pin the orchestrator that joins the
// EPUB WKWebView enumerate channel to `BilingualReadingViewModel`
// and emits inject / clear JS for the bridge to evaluate.
//
// The orchestrator is the single host-side type that knows:
//   - When to evaluate enumerate JS (chapter load when bilingual on).
//   - What to do with the `[BilingualBlock]` callback (cache the
//     blocks for the current unit; ask the VM to prefetch via
//     handlePositionChange; build inject JS when translations land).
//   - When to clear (bilingual flips off, unit change).
//
// Tests cover the pure transitions: given a {VM state, blocks,
// translations} input, what JS does the orchestrator emit? Runtime
// WKWebView interaction is exercised at slice-verification time by
// the `vreader-debug://` harness over a fixture book.
//
// @coordinates-with: EPUBBilingualOrchestrator.swift,
//   EPUBBilingualJS.swift, EPUBBilingualPipeline.swift,
//   BilingualReadingViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Testing
@testable import vreader

@Suite("Feature #56 WI-10 — EPUBBilingualOrchestrator")
@MainActor
struct EPUBBilingualOrchestratorTests {

    @Test("emitted enumerate JS is exactly EPUBBilingualJS.bilingualEnumerateJS()")
    func enumerateJSMatchesProducer() {
        let orchestrator = EPUBBilingualOrchestrator()
        #expect(orchestrator.enumerateJS() == EPUBBilingualJS.bilingualEnumerateJS())
    }

    @Test("clear JS emits the bilingualClearJS payload")
    func clearJSMatchesProducer() {
        let orchestrator = EPUBBilingualOrchestrator()
        #expect(orchestrator.clearJS() == EPUBBilingualJS.bilingualClearJS())
    }

    @Test("buildInjectJS returns nil when no blocks are known")
    func buildInjectJSNoBlocks() {
        let orchestrator = EPUBBilingualOrchestrator()
        let js = orchestrator.buildInjectJS(translatedSegments: ["x", "y"])
        #expect(js == nil)
    }

    // MARK: - Feature #100 (Gate-4 Low): the CJK flag flows into the builders

    @Test("targetIsCJK flows into buildLoadingJS and buildInjectJS")
    func cjkFlagFlowsIntoBuilders() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Chapter One")
        ])
        orchestrator.targetIsCJK = true
        #expect(orchestrator.buildLoadingJS()?.contains("var TARGET_CJK = true") == true,
                "the heading shimmer variant needs the live flag BEFORE any inject runs")
        #expect(orchestrator.buildInjectJS(translatedSegments: ["第一章"])?
            .contains("var TARGET_CJK = true") == true)

        orchestrator.targetIsCJK = false
        #expect(orchestrator.buildLoadingJS()?.contains("var TARGET_CJK = false") == true)
    }

    @Test("buildInjectJS returns nil when no translations are cached")
    func buildInjectJSNoTranslations() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
        let js = orchestrator.buildInjectJS(translatedSegments: nil)
        #expect(js == nil)
    }

    @Test("buildInjectJS returns nil when translation array is empty")
    func buildInjectJSEmptyTranslations() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
        let js = orchestrator.buildInjectJS(translatedSegments: [])
        #expect(js == nil)
    }

    @Test("buildInjectJS produces JS containing every block's bid")
    func buildInjectJSContainsBidKeys() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ])
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["Bonjour", "Monde"]))
        #expect(js.contains("b1"))
        #expect(js.contains("b2"))
        // Translations escape through FoliateJSEscaper — pin a
        // representative literal so the source survives the
        // escape pipeline.
        #expect(js.contains("Bonjour"))
        #expect(js.contains("Monde"))
    }

    @Test("buildInjectJS is nil on a count mismatch — source-only, never a wrong pairing (Bug #266)")
    func buildInjectJSMismatchIsSourceOnly() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World"),
            BilingualBlock(bid: "b3", text: "Goodbye")
        ])
        // 3 blocks vs 1 segment: pre-Bug-#266 this mapped segment 0 → block 0
        // and dropped the rest (a partial, position-trusting inject). Now a
        // count mismatch yields no inject at all (source-only) so a divergence
        // can never paint a translation under the wrong paragraph.
        #expect(orchestrator.buildInjectJS(translatedSegments: ["Bonjour"]) == nil)
    }

    @Test("updateBlocks replaces prior blocks")
    func updateBlocksReplaces() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
        // Replace with a different set of blocks (chapter swap).
        orchestrator.updateBlocks([
            BilingualBlock(bid: "x1", text: "Bonjour"),
            BilingualBlock(bid: "x2", text: "Monde")
        ])
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["foo", "bar"]))
        #expect(js.contains("x1"))
        #expect(js.contains("x2"))
        #expect(!js.contains("'b1':"))
    }

    @Test("currentBlocks reflects the last updateBlocks call")
    func currentBlocksObservable() {
        let orchestrator = EPUBBilingualOrchestrator()
        #expect(orchestrator.currentBlocks.isEmpty)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
        #expect(orchestrator.currentBlocks.count == 1)
        orchestrator.updateBlocks([])
        #expect(orchestrator.currentBlocks.isEmpty)
    }
}
