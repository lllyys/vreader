// Purpose: Feature #42 WI-11a (SPIKE) — pin the Readium bilingual
// eval-channel JS builders. The Readium navigator owns its own spine
// WKWebviews and does NOT expose the `bilingualEnumerate`
// WKScriptMessageHandler the legacy EPUB engine posts to. Instead its
// public `evaluateJavaScript(_:) async -> Result<Any,Error>` RETURNS the
// eval value. So the enumerate JS here RETURNS the `[{bid,text}]` array
// (the IIFE's last expression) rather than posting it — the inject / clear
// JS reuse the engine-agnostic `EPUBBilingualJS` bodies verbatim because
// they never depend on the message channel.
//
// These are JS-source-string pins, mirroring `EPUBBilingualJSTests` —
// runtime DOM behavior is proven by the WI-11a device spike-verify against
// a real Readium spine.
//
// @coordinates-with: ReadiumBilingualEvalAdapter.swift, EPUBBilingualJS.swift,
//   FoliateJSEscaper.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Testing
@testable import vreader

@Suite("Feature #42 WI-11a — ReadiumBilingualEvalAdapter")
struct ReadiumBilingualEvalAdapterTests {

    // MARK: - enumerateJS (return-value channel)

    @Test("enumerate JS stamps data-vreader-bid on each translatable block")
    func enumerateStampsStableID() {
        let js = ReadiumBilingualEvalAdapter.enumerateJS()
        #expect(
            js.contains("data-vreader-bid"),
            "enumerate JS must stamp a stable `data-vreader-bid` so inject can key translations back to the same block."
        )
    }

    @Test("enumerate JS produces {bid, text} payload shape")
    func enumerateProducesBidTextShape() {
        let js = ReadiumBilingualEvalAdapter.enumerateJS()
        #expect(js.contains("bid"))
        #expect(js.contains("text"))
    }

    @Test("enumerate JS RETURNS the block array — it does NOT post to the message handler")
    func enumerateReturnsRatherThanPosts() {
        let js = ReadiumBilingualEvalAdapter.enumerateJS()
        // The return-value channel is the whole point of the spike: Readium's
        // evaluateJavaScript yields the IIFE's return value, so the enumerate
        // must `return out;` (the array), NOT post it via
        // webkit.messageHandlers.bilingualEnumerate (which Readium does not
        // expose on its app-owned content controller).
        #expect(
            js.contains("return out"),
            "enumerate JS must RETURN the [{bid,text}] array as the eval result."
        )
        #expect(
            !js.contains("webkit.messageHandlers"),
            "enumerate JS must NOT post via webkit.messageHandlers — Readium owns its content controller; the return-value channel replaces it."
        )
        #expect(
            !js.contains("bilingualEnumerate"),
            "enumerate JS must not reference the legacy message-handler name."
        )
    }

    @Test("enumerate JS counts only LEAF blocks — skips a block containing a block descendant (Bug #266)")
    func enumerateSkipsNonLeafBlocks() {
        let js = ReadiumBilingualEvalAdapter.enumerateJS()
        // Bug #266: enumerate the inner leaf, skip a container that holds
        // another block element. Reuses the exact EPUBBilingualJS DOM walk.
        #expect(js.contains("querySelector(BLOCK_SELECTOR)"))
    }

    @Test("enumerate JS stamping is idempotent — reuses an existing bid")
    func enumerateStampIsIdempotent() {
        let js = ReadiumBilingualEvalAdapter.enumerateJS()
        // A block that already carries data-vreader-bid keeps the existing id
        // (so a re-enumerate after a translation cache hit reuses the bid).
        #expect(js.contains("if (existing)"))
    }

    @Test("enumerate JS skips already-injected decoration siblings")
    func enumerateSkipsDecorationNodes() {
        let js = ReadiumBilingualEvalAdapter.enumerateJS()
        #expect(js.contains("data-vreader-decoration"))
    }

    // MARK: - injectJS (reuses the engine-agnostic body)

    @Test("inject JS appends a decoration div carrying the keystone attribute + class")
    func injectAppendsDecoration() {
        let js = ReadiumBilingualEvalAdapter.injectJS(pairs: ["b1": "译文"])
        #expect(js.contains("data-vreader-decoration"))
        #expect(js.contains("vreader-bilingual"))
        #expect(js.contains("data-vreader-bid"))
    }

    @Test("inject JS escapes a single-quote payload so it cannot break the JS literal")
    func injectEscapesSingleQuote() {
        // A translation with a single quote would break the single-quoted JS
        // literal (or open a JS-injection vector) if not escaped via
        // FoliateJSEscaper. The escaped form must appear; the raw must not.
        let js = ReadiumBilingualEvalAdapter.injectJS(pairs: ["b1": "it's a test"])
        #expect(js.contains("it\\'s a test"))
    }

    @Test("inject JS escapes a newline / line-separator payload")
    func injectEscapesLineTerminators() {
        let js = ReadiumBilingualEvalAdapter.injectJS(pairs: ["b1": "line1\nline2"])
        #expect(js.contains("line1\\nline2"))
    }

    @Test("inject JS escapes the bid key too")
    func injectEscapesBidKey() {
        let js = ReadiumBilingualEvalAdapter.injectJS(pairs: ["b'1": "x"])
        #expect(js.contains("b\\'1"))
    }

    @Test("inject JS is idempotent — replaces an existing decoration sibling in place")
    func injectIsIdempotent() {
        let js = ReadiumBilingualEvalAdapter.injectJS(pairs: ["b1": "x"])
        #expect(js.contains("nextElementSibling"))
    }

    // MARK: - clearJS (reuses the engine-agnostic body)

    @Test("clear JS targets the decoration class + attribute")
    func clearTargetsDecorationNodes() {
        let js = ReadiumBilingualEvalAdapter.clearJS()
        #expect(js.contains("vreader-bilingual"))
        #expect(js.contains("data-vreader-decoration"))
        #expect(js.contains("removeChild"))
    }

    // MARK: - cross-builder contract

    @Test("the same data-vreader-bid attribute spans enumerate + inject")
    func bidAttributeIsSharedAcrossBuilders() {
        let enumerate = ReadiumBilingualEvalAdapter.enumerateJS()
        let inject = ReadiumBilingualEvalAdapter.injectJS(pairs: ["b1": "x"])
        #expect(enumerate.contains("data-vreader-bid"))
        #expect(inject.contains("data-vreader-bid"))
    }
}
