// Purpose: Feature #56 WI-10 — pin the R-EPUB-CFI fix in
// `EPUBHighlightBridge.selectionTrackingJS` / `highlightAPIJS`.
// Bilingual mode injects `<div data-vreader-decoration>` siblings
// after each translatable block; without skipping them, the XPath
// `getXPath` serializer would count them in `parent.childNodes`,
// shifting every sibling index and breaking persisted highlight
// anchoring (Feature #11).
//
// This is the regression-source pin gating WI-10's merge. The plan's
// `EPUBHighlightAnchoringRegressionTests (extend Feature #11 coverage)`
// row says this test must prove the `getXPath` decoration-skip works.
// We pin the JS source pattern — the runtime XPath behavior is
// verified at slice verification time by the `vreader-debug://`
// harness over a fixture book with both highlights and bilingual on.
//
// @coordinates-with: EPUBHighlightJS.swift, EPUBBilingualJS.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (R-EPUB-CFI)

#if canImport(UIKit)
import Foundation
import Testing
@testable import vreader

@Suite("Feature #56 WI-10 — EPUB highlight anchoring regression (R-EPUB-CFI)")
struct EPUBHighlightAnchoringRegressionTests {

    @Test("selection tracking JS skips data-vreader-decoration siblings")
    func selectionTrackingJSSkipsDecorationSiblings() {
        // The fix lives in `getXPath` inside `selectionTrackingJS`:
        // every `parent.childNodes` traversal must skip nodes
        // carrying `data-vreader-decoration`. Without this, the
        // XPath sibling index counts bilingual translation blocks,
        // shifting persisted-highlight anchoring under bilingual on.
        let js = EPUBHighlightBridge.selectionTrackingJS
        #expect(
            js.contains("data-vreader-decoration"),
            "selectionTrackingJS must reference `data-vreader-decoration` so its XPath sibling-index traversal skips bilingual translation blocks. Otherwise turning bilingual on shifts every persisted highlight by N siblings."
        )
    }

    @Test("XPath resolver matches paths via document.evaluate (no manual sibling walk)")
    func highlightAPIJSUsesDocumentEvaluate() {
        // The decoration-skip lives ONLY in the producer
        // (`selectionTrackingJS.getXPath`). The resolver
        // (`highlightAPIJS.resolveNodeFromXPath`) delegates path
        // matching to `document.evaluate`, so it does NOT need its
        // own decoration filter — the XPath engine matches the path
        // the producer serialized verbatim.
        //
        // What this test pins is the resolver staying delegated:
        // a regression that replaced `document.evaluate` with a
        // manual sibling-index walk on the resolver side would
        // re-introduce the decoration-shift bug, since that walk
        // would need its OWN decoration filter to stay in sync.
        // Keeping the resolver index-walk-free is the contract.
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(
            js.contains("document.evaluate"),
            "highlightAPIJS must resolve XPath via `document.evaluate` (not a manual sibling-index walk). The engine matches the path the producer (selectionTrackingJS) serialized; the producer's decoration-skip is then sufficient for R-EPUB-CFI. A manual resolver walk would need its own decoration filter and re-introduce the two-place-update fragility we just removed."
        )
    }

    @Test("selectionTrackingJS preserves the text() axis token after the fix")
    func selectionTrackingJSPreservesTextAxis() {
        // R-EPUB-CFI's decoration-skip MUST NOT corrupt the text-node
        // path serializer. The pre-fix code emits `/text()[N]` for
        // text-node boundaries; the fix only adds a filter on the
        // element sibling counter — text-node handling is untouched.
        // Pin the `/text()` token survives.
        let js = EPUBHighlightBridge.selectionTrackingJS
        #expect(
            js.contains("text()"),
            "selectionTrackingJS must still emit `/text()[N]` after the R-EPUB-CFI decoration-skip; the skip applies only to element siblings, not to text-node serialization."
        )
    }
}
#endif
