// Purpose: Feature #71 WI-7 — pin the per-section (per stitched
// chapter) bilingual scoping that the EPUB continuous-scroll path
// needs. Continuous mode stitches multiple chapter `<section
// data-vreader-spine-index="N">` blocks into one document; enabling
// bilingual must inject translations PER stitched section with NO
// cross-section `bid` bleed. This mirrors the Foliate per-section
// pattern (`FoliateBilingualJS` / `FoliateBilingualOrchestrator`)
// onto the EPUB renderer.
//
// Three behavioural surfaces are pinned here:
//   - `EPUBBilingualJS.bilingual{Enumerate,Inject,Clear}JS(spineIndex:)`
//     scope the DOM walk to one `[data-vreader-spine-index="N"]`
//     subtree, namespace the stamped bid as `s{N}b{seq}` (so
//     section 0's bids never collide with section 1's), and tag each
//     posted entry with `sectionIndex: N`. The `nil` path is
//     UNCHANGED (paged/global mode).
//   - `EPUBBilingualPipeline.parseEnumerateMessage` reads the
//     optional `sectionIndex` off each payload entry (nil when
//     absent — backward compatible with the paged path).
//   - `EPUBBilingualOrchestrator` keeps a per-section block cache so
//     a re-enumerate of section 0 replaces ONLY section 0's bucket
//     (section 1 intact), and `buildInjectJS(...:forSection:)` emits
//     inject for one section's bids only.
//
// These are JS-source-string + value-type pins, not WKWebView-runtime
// assertions. Runtime DOM behaviour is exercised at slice-verification
// time by the `vreader-debug://` harness over a continuous-scroll EPUB.
//
// @coordinates-with: EPUBBilingualJS.swift, EPUBBilingualPipeline.swift,
//   EPUBBilingualOrchestrator.swift, EPUBContinuousScrollJS.swift,
//   FoliateBilingualJS.swift (the template),
//   dev-docs/plans/...-feature-71-... (WI-7)

import Testing
@testable import vreader

@Suite("Feature #71 WI-7 — EPUB bilingual section scoping")
@MainActor
struct EPUBBilingualSectionScopeTests {

    // MARK: - enumerate JS scoping

    @Test("enumerate JS for spineIndex 0 scopes the walk to that section subtree")
    func enumerateScopesToSectionSubtree() {
        let js = EPUBBilingualJS.bilingualEnumerateJS(spineIndex: 0)
        // The continuous-scroll section wrapper is
        // `<section data-vreader-spine-index="N">`. A section-scoped
        // enumerate must root its DOM walk at that subtree, never the
        // whole stitched document.
        #expect(
            js.contains("data-vreader-spine-index=\"0\""),
            "section-scoped enumerate must query [data-vreader-spine-index=\"0\"] so it never walks adjacent stitched chapters."
        )
    }

    @Test("enumerate JS for spineIndex 1 namespaces the stamped bid as s1b…")
    func enumerateNamespacesBidPerSection() {
        let js = EPUBBilingualJS.bilingualEnumerateJS(spineIndex: 1)
        // Bids must be namespaced by section so section 0's `b1` and
        // section 1's `b1` cannot collide once both sections are
        // stitched into the same document. The Foliate template uses
        // the same `'s' + N + 'b' + seq` shape.
        #expect(
            js.contains("'s' + 1 + 'b'") || js.contains("'s1b'") || js.contains("s' + 1 + 'b"),
            "section-scoped enumerate must namespace bids per section (e.g. `s1b…`) so cross-section bids never collide."
        )
    }

    @Test("enumerate JS for a section reports sectionIndex in each payload entry")
    func enumerateReportsSectionIndexInPayload() {
        let js = EPUBBilingualJS.bilingualEnumerateJS(spineIndex: 2)
        // Each posted `{bid, text, sectionIndex}` entry must carry the
        // section index so the Swift pipeline can bucket blocks by
        // section without trusting the bid prefix.
        #expect(
            js.contains("sectionIndex"),
            "section-scoped enumerate must include `sectionIndex` in each posted entry so the pipeline can bucket blocks per section."
        )
    }

    @Test("enumerate JS nil path is byte-identical to the current global enumerate")
    func enumerateNilPathUnchanged() {
        // The paged/global path must be UNCHANGED — the existing
        // JS-source-string pins in EPUBBilingualJSTests depend on it.
        #expect(
            EPUBBilingualJS.bilingualEnumerateJS(spineIndex: nil)
                == EPUBBilingualJS.bilingualEnumerateJS()
        )
    }

    @Test("enumerate JS nil path emits the ORIGINAL WI-10 body — no WI-7 temp vars or section field (LOW 1)")
    func enumerateNilPathIsOriginalLiteral() {
        // Gate-4 round-2 LOW 1: the nil path must be the byte-identical
        // pre-WI-7 `main` literal, NOT an equivalent-but-restructured body.
        // The WI-7 section-scoping introduced `__vreaderBilingualTargetSection`,
        // `__vreaderBilingualRoot`, the `s{N}b{seq}` bid prefix, and the
        // per-entry `sectionIndex` field — none of these may leak into the
        // paged/global path.
        let js = EPUBBilingualJS.bilingualEnumerateJS(spineIndex: nil)
        #expect(!js.contains("__vreaderBilingualTargetSection"))
        #expect(!js.contains("__vreaderBilingualRoot"))
        #expect(!js.contains("sectionIndex"))
        // The original bare bid + document.body root are preserved.
        #expect(js.contains("var bid = 'b' + seq;"))
        #expect(js.contains("var all = document.body"))
        #expect(js.contains("out.push({ bid: bid, text: text });"))
    }

    @Test("clear JS nil path emits the ORIGINAL WI-10 body — document-rooted, no section root guard (LOW 1)")
    func clearNilPathIsOriginalLiteral() {
        let js = EPUBBilingualJS.bilingualClearJS(spineIndex: nil)
        #expect(!js.contains("data-vreader-spine-index"))
        #expect(!js.contains("var root ="))
        // The original document-rooted querySelectorAll is preserved.
        #expect(js.contains("var nodes = document.querySelectorAll("))
    }

    @Test("clear JS for a section scopes the removal to that section subtree")
    func clearScopesToSectionSubtree() {
        let js = EPUBBilingualJS.bilingualClearJS(spineIndex: 0)
        #expect(js.contains("data-vreader-spine-index=\"0\""))
        // Still enumerates ALL bilingual nodes within that subtree.
        #expect(js.contains("querySelectorAll"))
    }

    @Test("clear JS nil path is byte-identical to the current global clear")
    func clearNilPathUnchanged() {
        #expect(
            EPUBBilingualJS.bilingualClearJS(spineIndex: nil)
                == EPUBBilingualJS.bilingualClearJS()
        )
    }

    @Test("inject JS nil path is byte-identical to the current global inject")
    func injectNilPathUnchanged() {
        let map = ["s0b1": "Bonjour", "s1b1": "Monde"]
        #expect(
            EPUBBilingualJS.bilingualInjectJS(translationsByBid: map, spineIndex: nil)
                == EPUBBilingualJS.bilingualInjectJS(translationsByBid: map)
        )
    }

    @Test("inject JS keyed by namespaced bid still finds each block globally")
    func injectFindsNamespacedBidGlobally() {
        let js = EPUBBilingualJS.bilingualInjectJS(
            translationsByBid: ["s1b1": "Monde"], spineIndex: 1)
        // Namespaced bids are globally unique, so the inject path keeps
        // keying by `data-vreader-bid` (a global querySelector still
        // resolves the right block).
        #expect(js.contains("s1b1"))
        #expect(js.contains("data-vreader-bid"))
    }

    // MARK: - pipeline sectionIndex parsing

    @Test("parseEnumerateMessage reads sectionIndex when present")
    func parseReadsSectionIndex() {
        let body: Any = [
            ["bid": "s0b1", "text": "Hello", "sectionIndex": 0],
            ["bid": "s1b1", "text": "Bonjour", "sectionIndex": 1]
        ]
        let blocks = EPUBBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 2)
        #expect(blocks[0].sectionIndex == 0)
        #expect(blocks[1].sectionIndex == 1)
    }

    @Test("parseEnumerateMessage leaves sectionIndex nil when absent (paged path)")
    func parseSectionIndexNilWhenAbsent() {
        let body: Any = [
            ["bid": "b1", "text": "Hello"]
        ]
        let blocks = EPUBBilingualPipeline.parseEnumerateMessage(body)
        #expect(blocks.count == 1)
        #expect(blocks[0].sectionIndex == nil)
    }

    // MARK: - empty-section envelope (Gate-4 round-3 MEDIUM 1)

    @Test("scoped enumerate JS posts a {sectionIndex, blocks} envelope (not a bare array)")
    func scopedEnumerateJSPostsEnvelope() {
        let js = EPUBBilingualJS.bilingualEnumerateJS(spineIndex: 3)
        // The scoped enumerate must ALWAYS carry the section identity so an
        // EMPTY result (no translatable leaf blocks) still says which section
        // it was for. A bare `postMessage(out)` would lose that on `[]`.
        #expect(js.contains("postMessage("))
        #expect(js.contains("sectionIndex: 3"))
        #expect(js.contains("blocks: out"))
    }

    @Test("paged enumerate JS still posts the bare `out` array (no envelope) — byte-identical")
    func pagedEnumerateJSPostsBareArray() {
        let js = EPUBBilingualJS.bilingualEnumerateJS(spineIndex: nil)
        #expect(js.contains(".postMessage(out);"))
        #expect(!js.contains("blocks: out"))
    }

    @Test("parseEnumeratePayload reads the envelope's requestedSectionIndex + blocks")
    func parsePayloadReadsEnvelope() {
        let body: Any = [
            "sectionIndex": 2,
            "blocks": [
                ["bid": "s2b1", "text": "Hello", "sectionIndex": 2],
                ["bid": "s2b2", "text": "World", "sectionIndex": 2]
            ]
        ]
        let payload = EPUBBilingualPipeline.parseEnumeratePayload(body)
        #expect(payload.requestedSectionIndex == 2)
        #expect(payload.blocks.map(\.bid) == ["s2b1", "s2b2"])
        #expect(payload.blocks.allSatisfy { $0.sectionIndex == 2 })
    }

    @Test("parseEnumeratePayload keeps the section identity on an EMPTY envelope (the MEDIUM 1 fix)")
    func parsePayloadEmptyEnvelopeKeepsSection() {
        // A stitched section with no translatable leaf blocks posts an empty
        // `blocks` array but STILL carries its `sectionIndex` so the handler
        // can clear ONLY that section's bucket, not every bucket.
        let body: Any = ["sectionIndex": 5, "blocks": [Any]()]
        let payload = EPUBBilingualPipeline.parseEnumeratePayload(body)
        #expect(payload.requestedSectionIndex == 5)
        #expect(payload.blocks.isEmpty)
    }

    @Test("parseEnumeratePayload leaves requestedSectionIndex nil for the bare paged array")
    func parsePayloadBareArrayHasNoSection() {
        let body: Any = [["bid": "b1", "text": "Hello"]]
        let payload = EPUBBilingualPipeline.parseEnumeratePayload(body)
        #expect(payload.requestedSectionIndex == nil)
        #expect(payload.blocks.map(\.bid) == ["b1"])
    }

    @Test("parseEnumeratePayload tolerates a non-dict / non-array body")
    func parsePayloadGarbageBody() {
        let payload = EPUBBilingualPipeline.parseEnumeratePayload("garbage" as Any)
        #expect(payload.requestedSectionIndex == nil)
        #expect(payload.blocks.isEmpty)
    }

    @Test("empty scoped enumerate clears ONLY its section bucket — adjacent sections intact")
    func emptyScopedEnumerateClearsOnlyOwnSection() {
        // Simulate the orchestrator-side effect of the handler: an empty
        // envelope for section 1 must call clearBlocks(forSection: 1) and leave
        // sections 0 and 2 untouched. (The handler wiring is continuous-mode
        // runtime; this pins the orchestrator seam the handler drives.)
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "beta", sectionIndex: 1)
        ], forSection: 1)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s2b1", text: "gamma", sectionIndex: 2)
        ], forSection: 2)

        let payload = EPUBBilingualPipeline.parseEnumeratePayload(
            ["sectionIndex": 1, "blocks": [Any]()])
        // The handler's empty-branch contract: clear only requestedSectionIndex.
        #expect(payload.blocks.isEmpty)
        if let section = payload.requestedSectionIndex {
            orchestrator.clearBlocks(forSection: section)
        }
        #expect(orchestrator.blocksBySection[0]?.map(\.bid) == ["s0b1"])
        #expect(orchestrator.blocksBySection[1] == nil)
        #expect(orchestrator.blocksBySection[2]?.map(\.bid) == ["s2b1"])
    }

    // MARK: - orchestrator per-section caches (no cross-section bleed)

    @Test("updateBlocks(_:forSection:) caches two sections and currentBlocks flattens in section order")
    func perSectionCacheFlattensInOrder() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "s0b2", text: "beta", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        #expect(orchestrator.blocksBySection[0]?.map(\.bid) == ["s0b1", "s0b2"])
        #expect(orchestrator.blocksBySection[1]?.map(\.bid) == ["s1b1"])
        // currentBlocks flattens sorted by section key.
        #expect(orchestrator.currentBlocks.map(\.bid) == ["s0b1", "s0b2", "s1b1"])
    }

    @Test("re-updateBlocks(_:forSection: 0) replaces ONLY section 0 — no cross-section bleed")
    func perSectionUpdateNoCrossSectionBleed() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        // Re-enumerate section 0 (e.g. its DOM re-stitched). Section 1
        // must remain untouched — this is the core no-bleed invariant.
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha-2", sectionIndex: 0),
            BilingualBlock(bid: "s0b2", text: "alpha-3", sectionIndex: 0)
        ], forSection: 0)
        #expect(orchestrator.blocksBySection[0]?.map(\.bid) == ["s0b1", "s0b2"])
        #expect(orchestrator.blocksBySection[0]?.map(\.text) == ["alpha-2", "alpha-3"])
        #expect(orchestrator.blocksBySection[1]?.map(\.bid) == ["s1b1"])
    }

    @Test("buildInjectJS(...:forSection: 0) emits inject ONLY for section 0's bids")
    func buildInjectForSectionScopesBids() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "s0b2", text: "beta", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["A", "B"], forSection: 0))
        #expect(js.contains("s0b1"))
        #expect(js.contains("s0b2"))
        // Section 1's bid must NEVER appear in section 0's inject map.
        #expect(!js.contains("s1b1"))
    }

    @Test("buildInjectJS(...:forSection: 1) emits inject ONLY for section 1's bids")
    func buildInjectForOtherSectionScopesBids() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["X"], forSection: 1))
        #expect(js.contains("s1b1"))
        #expect(!js.contains("'s0b1':"))
    }

    @Test("buildInjectJS(...:forSection:) is nil when that section has no blocks")
    func buildInjectForUnknownSectionIsNil() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0)
        ], forSection: 0)
        #expect(orchestrator.buildInjectJS(
            translatedSegments: ["A"], forSection: 9) == nil)
    }

    @Test("buildInjectJS(...:forSection:) is nil on a per-section COUNT MISMATCH (Bug #268 trigger for MEDIUM 2)")
    func buildInjectForSectionCountMismatchIsNil() {
        // The continuous path detects this nil (the plain-text prefetch's
        // segment count diverged from the section's DOM leaf-block count) and
        // routes to `translateBlocksDirectly` so the section pairs 1:1 instead
        // of staying source-only. Two blocks vs three segments → 1:1 guard
        // (Bug #266) yields nil; the section's own block texts get translated
        // directly.
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "alpha", sectionIndex: 1),
            BilingualBlock(bid: "s1b2", text: "beta", sectionIndex: 1)
        ], forSection: 1)
        #expect(orchestrator.buildInjectJS(
            translatedSegments: ["A", "B", "C"], forSection: 1) == nil)
    }

    @Test("buildInjectJS (no section) still injects every cached section's blocks (paged + flatten)")
    func buildInjectUnscopedFlattensAllSections() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        let js = try #require(orchestrator.buildInjectJS(
            translatedSegments: ["A", "B"]))
        #expect(js.contains("s0b1"))
        #expect(js.contains("s1b1"))
    }

    // MARK: - eviction clears only the named section's bucket (MEDIUM 2)

    @Test("clearBlocks(forSection:) drops only the named section — others intact")
    func clearBlocksForSectionScopesToOne() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s2b1", text: "delta", sectionIndex: 2)
        ], forSection: 2)
        // Evict section 1 (e.g. scrolled far out of the continuous window).
        orchestrator.clearBlocks(forSection: 1)
        #expect(orchestrator.blocksBySection[0]?.map(\.bid) == ["s0b1"])
        #expect(orchestrator.blocksBySection[1] == nil)
        #expect(orchestrator.blocksBySection[2]?.map(\.bid) == ["s2b1"])
    }

    @Test("materializedSections lists the cached section keys ascending")
    func materializedSectionsListsCachedKeys() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s2b1", text: "x", sectionIndex: 2)
        ], forSection: 2)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "y", sectionIndex: 0)
        ], forSection: 0)
        #expect(orchestrator.materializedSections == [0, 2])
    }

    @Test("disable-in-continuous contract: clearing every materializedSection empties all buckets (HIGH 2)")
    func disableContinuousClearsEveryBucket() {
        // `disableBilingualContinuous()` iterates `materializedSections` and
        // calls `clearBlocks(forSection:)` for each so a later re-enable
        // re-enumerates from a clean slate. Pin the orchestrator contract the
        // continuous disable path relies on (the live `clearJS()` eval is
        // continuous-mode runtime, CU-gated).
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "a", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "b", sectionIndex: 1)
        ], forSection: 1)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s4b1", text: "c", sectionIndex: 4)
        ], forSection: 4)
        for section in orchestrator.materializedSections {
            orchestrator.clearBlocks(forSection: section)
        }
        #expect(orchestrator.materializedSections.isEmpty)
        #expect(orchestrator.currentBlocks.isEmpty)
    }

    // MARK: - reinject across multiple materialized sections (HIGH 2)

    @Test("buildInjectJS(translationsBySection:) injects EACH section's segments into ITS OWN bids")
    func buildInjectAcrossSectionsScopesPerSection() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "s0b2", text: "beta", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        // Both sections have cached translations of DIFFERENT counts — the
        // combined inject must pair each section's segments to its own bids
        // (the single-pendingHighlightJS overwrite + cross-section flatten bug).
        let js = try #require(orchestrator.buildInjectJS(translationsBySection: [
            0: ["A0", "B0"],
            1: ["G1"]
        ]))
        // Each bid maps to its OWN section's translation.
        #expect(js.contains("'s0b1': 'A0'"))
        #expect(js.contains("'s0b2': 'B0'"))
        #expect(js.contains("'s1b1': 'G1'"))
    }

    @Test("buildInjectJS(translationsBySection:) skips a section whose count mismatches its blocks (Bug #266 1:1)")
    func buildInjectAcrossSectionsHonorsCountGuard() throws {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "s0b2", text: "beta", sectionIndex: 0)
        ], forSection: 0)
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s1b1", text: "gamma", sectionIndex: 1)
        ], forSection: 1)
        // Section 0 has 2 blocks but only 1 segment → Bug #266 guard drops it
        // (source-only). Section 1 pairs 1:1 → injects.
        let js = try #require(orchestrator.buildInjectJS(translationsBySection: [
            0: ["only-one"],
            1: ["G1"]
        ]))
        #expect(!js.contains("s0b1"))
        #expect(!js.contains("s0b2"))
        #expect(js.contains("'s1b1': 'G1'"))
    }

    @Test("buildInjectJS(translationsBySection:) is nil when no section has a 1:1 translation")
    func buildInjectAcrossSectionsNilWhenNothingPairs() {
        let orchestrator = EPUBBilingualOrchestrator()
        orchestrator.updateBlocks([
            BilingualBlock(bid: "s0b1", text: "alpha", sectionIndex: 0),
            BilingualBlock(bid: "s0b2", text: "beta", sectionIndex: 0)
        ], forSection: 0)
        #expect(orchestrator.buildInjectJS(translationsBySection: [0: ["only-one"]]) == nil)
        #expect(orchestrator.buildInjectJS(translationsBySection: [:]) == nil)
    }
}
