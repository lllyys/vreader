// Purpose: Feature #56 WI-11 — pin the host-side orchestrator that
// joins the Foliate WKWebView's `bilingualEnumerate` channel to
// `BilingualReadingViewModel` and emits inject / clear JS for the
// bridge to evaluate.
//
// The orchestrator is the single host-side type that knows:
//   - When to evaluate enumerate JS (relocate / section load when
//     bilingual is on).
//   - What to do with the `[BilingualBlock]` callback (cache the
//     blocks for the current unit; ask the VM to prefetch via
//     handlePositionChange; build inject JS when translations land).
//   - When to clear (bilingual flips off, section change).
//
// Tests cover the pure transitions: given a {VM state, blocks,
// translations} input, what JS does the orchestrator emit? Runtime
// WKWebView interaction is exercised at slice-verification time by
// the `vreader-debug://` harness over an AZW3 fixture book.
//
// @coordinates-with: FoliateBilingualOrchestrator.swift,
//   FoliateBilingualJS.swift, FoliateBilingualPipeline.swift,
//   BilingualReadingViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Testing
@testable import vreader

@Suite("Feature #56 WI-11 — FoliateBilingualOrchestrator")
@MainActor
struct FoliateBilingualOrchestratorTests {

    @Test("emitted enumerate JS is exactly FoliateBilingualJS.bilingualEnumerateJS()")
    func enumerateJSMatchesProducer() {
        let orchestrator = FoliateBilingualOrchestrator()
        #expect(orchestrator.enumerateJS() == FoliateBilingualJS.bilingualEnumerateJS())
    }

    @Test("clear JS emits the bilingualClearJS payload")
    func clearJSMatchesProducer() {
        let orchestrator = FoliateBilingualOrchestrator()
        #expect(orchestrator.clearJS() == FoliateBilingualJS.bilingualClearJS())
    }

    @Test("buildInjectJS returns nil when no blocks are known")
    func buildInjectJSNoBlocks() {
        let orchestrator = FoliateBilingualOrchestrator()
        let js = orchestrator.buildInjectJS(translatedSegments: ["x", "y"])
        #expect(js == nil)
    }

    @Test("buildInjectJS returns nil when no translations are cached")
    func buildInjectJSNoTranslations() {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
        let js = orchestrator.buildInjectJS(translatedSegments: nil)
        #expect(js == nil)
    }

    @Test("buildInjectJS returns nil when translation array is empty")
    func buildInjectJSEmptyTranslations() {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
        let js = orchestrator.buildInjectJS(translatedSegments: [])
        #expect(js == nil)
    }

    @Test("buildInjectJS produces JS containing every block's bid")
    func buildInjectJSContainsBidKeys() throws {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ])
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["Bonjour", "Monde"]))
        #expect(js.contains("b1"))
        #expect(js.contains("b2"))
        #expect(js.contains("Bonjour"))
        #expect(js.contains("Monde"))
    }

    @Test("buildInjectJS shorter translation array maps a prefix and drops the rest")
    func buildInjectJSShortArrayPartial() throws {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World"),
            BilingualBlock(bid: "b3", text: "Goodbye")
        ])
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["Bonjour"]))
        #expect(js.contains("Bonjour"))
        #expect(js.contains("b1"))
        let occurrences = js.components(separatedBy: "': '").count - 1
        #expect(
            occurrences == 1,
            "Inject JS should carry exactly one bid → translation entry when the translation array has one element and the enumerate had three blocks."
        )
    }

    @Test("updateBlocks replaces prior blocks")
    func updateBlocksReplaces() throws {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
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
        let orchestrator = FoliateBilingualOrchestrator()
        #expect(orchestrator.currentBlocks.isEmpty)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "Hello")
        ])
        #expect(orchestrator.currentBlocks.count == 1)
        orchestrator.updateBlocks([])
        #expect(orchestrator.currentBlocks.isEmpty)
    }

    // MARK: - Per-section scoping (Gate-4 audit H2)

    @Test("buildInjectJS scopes the bid map to the section's blocks")
    func buildInjectJSScopesToSection() throws {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "b2", text: "beta",  sectionIndex: 0),
            BilingualBlock(bid: "b3", text: "gamma", sectionIndex: 1)
        ])
        // Request section 1: only b3 should appear in the inject JS.
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["one"],
            sectionIndex: 1
        ))
        #expect(js.contains("b3"))
        #expect(!js.contains("'b1':"))
        #expect(!js.contains("'b2':"))
        // The emitted JS must carry the section-scope argument so
        // the host helper does not walk section 0's DOM.
        #expect(js.contains("targetSectionIndex: 1"))
    }

    // MARK: - Per-section block caches (Gate-4 round-2 audit fix)

    @Test("updateBlocks(_:forSection:) preserves other sections' caches")
    func perSectionUpdateIsolation() {
        let orchestrator = FoliateBilingualOrchestrator()
        // Section 0 loads first.
        orchestrator.updateBlocks([
            BilingualBlock(bid: "a1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "a2", text: "beta",  sectionIndex: 0)
        ], forSection: 0)
        // Section 1 preloads later (adjacent, off-screen).
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        // Section 0's cache must NOT have been clobbered.
        #expect(orchestrator.blocksBySection[0]?.map(\.bid) == ["a1", "a2"])
        #expect(orchestrator.blocksBySection[1]?.map(\.bid) == ["b1"])
    }

    @Test("inject can target a preloaded section after a different section loaded")
    func injectAgainstPreloadedAdjacent() throws {
        // Simulate the paginated-mode hazard: section 0 is current,
        // section 1 preloads. The user later page-turns into 1.
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "a1", text: "alpha", sectionIndex: 0),
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "gamma", sectionIndex: 1),
            BilingualBlock(bid: "b2", text: "delta", sectionIndex: 1)
        ], forSection: 1)
        // Inject for the preloaded section 1 must surface b1/b2 — not a1.
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["x", "y"], sectionIndex: 1
        ))
        #expect(js.contains("b1"))
        #expect(js.contains("b2"))
        #expect(!js.contains("'a1':"))
    }

    @Test("clearBlocks(forSection:) removes only that section's cache")
    func clearBlocksPerSection() {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "a1", text: "alpha", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        orchestrator.clearBlocks(forSection: 0)
        #expect(orchestrator.blocksBySection[0] == nil)
        #expect(orchestrator.blocksBySection[1]?.count == 1)
    }

    @Test("buildInjectJS with no sectionIndex injects every block")
    func buildInjectJSUnscoped() throws {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "b2", text: "beta",  sectionIndex: 1)
        ])
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["one", "two"]
        ))
        #expect(js.contains("b1"))
        #expect(js.contains("b2"))
        // null targetSectionIndex falls back to walking every loaded section
        #expect(js.contains("targetSectionIndex: null"))
    }

    @Test("buildInjectJS returns nil when no blocks match the section")
    func buildInjectJSEmptyForUnknownSection() {
        let orchestrator = FoliateBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "b1", text: "alpha", sectionIndex: 0)
        ])
        let js = orchestrator.buildInjectJS(
            translatedSegments: ["one"],
            sectionIndex: 7
        )
        #expect(js == nil)
    }
}
