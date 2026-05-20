// Purpose: Feature #56 WI-10 — pin the EPUB bilingual interlinear
// JS contracts (`bilingualEnumerateJS`, `bilingualInjectJS`,
// `bilingualClearJS`). The JS runs inside an `application/xhtml+xml`
// WKWebView; a regression here would either break R-EPUB-CFI
// anchoring (decoration nodes leak past `data-vreader-decoration`)
// or silently mis-inject/mis-clear translation blocks.
//
// Behavior-level shape pins:
// - enumerate stamps `data-vreader-bid` on each translatable block
//   and posts `[{bid, text}]` for the host to translate.
// - inject appends a `<div class="vreader-bilingual"
//   data-vreader-decoration ...>` after each stamped block. The
//   decoration attribute is the R-EPUB-CFI keystone — every sibling
//   traversal in highlight/selection JS skips it.
// - inject and clear are idempotent — re-running them is a no-op
//   when the DOM is already in the requested state.
// - All interpolation routes through `FoliateJSEscaper.escapeForJSString`
//   (proves WKWebView injection is hardened against ' / line-term /
//   newline payloads in cached translations).
//
// These are JS-source-string pins, not WKWebView-runtime assertions.
// They are exactly the same shape the existing `EPUBHighlightBridge`
// JS pins use (selectionTrackingJS / highlightAPIJS) — runtime
// behavior is verified at slice-verification time by the
// `vreader-debug://` harness driving a fixture book.
//
// @coordinates-with: EPUBBilingualJS.swift, EPUBHighlightJS.swift,
//   FoliateJSEscaper.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Testing
@testable import vreader

@Suite("Feature #56 WI-10 — EPUBBilingualJS")
struct EPUBBilingualJSTests {

    // MARK: - enumerateJS

    @Test("enumerate JS is non-empty and wires the message channel")
    func enumerateJSIsNonEmpty() {
        let js = EPUBBilingualJS.bilingualEnumerateJS()
        #expect(!js.isEmpty)
        // The enumerate path must post results back to Swift via the
        // `bilingualEnumerate` message handler so the host receives
        // `[{bid, text}]` for translation.
        #expect(js.contains("bilingualEnumerate"))
    }

    @Test("enumerate JS stamps data-vreader-bid on each translatable block")
    func enumerateStampsStableID() {
        let js = EPUBBilingualJS.bilingualEnumerateJS()
        // The stable-id attribute name is part of the contract; both
        // the inject path AND the highlight XPath decoration-skip
        // rely on `data-vreader-bid` + `data-vreader-decoration`
        // being literal strings the host can search for.
        #expect(
            js.contains("data-vreader-bid"),
            "enumerate JS must stamp a stable `data-vreader-bid` attribute on each translatable block — the inject path keys translations to the same id, and the highlight XPath decoration-skip relies on the literal attribute name."
        )
    }

    @Test("enumerate JS posts an ordered array of {bid, text} payloads")
    func enumerateProducesOrderedBidTextPayloads() {
        let js = EPUBBilingualJS.bilingualEnumerateJS()
        // The payload shape is `[{bid, text}]` — both keys must appear
        // in the source so the parser on the Swift side can decode
        // them as `[BilingualBlock]`.
        #expect(js.contains("bid"))
        #expect(js.contains("text"))
    }

    // MARK: - injectJS

    @Test("inject JS marks translation nodes with data-vreader-decoration")
    func injectMarksDecoration() {
        let js = EPUBBilingualJS.bilingualInjectJS(translationsByBid: [:])
        // R-EPUB-CFI keystone: every sibling-index traversal in
        // highlight/selection JS skips `data-vreader-decoration` nodes
        // (see EPUBHighlightAnchoringRegressionTests). Inject MUST
        // emit this attribute on every translation block, otherwise
        // a future post-WI-10 chapter would shift XPath indices and
        // existing highlights would mis-anchor.
        #expect(
            js.contains("data-vreader-decoration"),
            "inject JS must stamp `data-vreader-decoration` on every translation node — the R-EPUB-CFI fix in EPUBHighlightJS.getXPath skips these nodes when serializing paths."
        )
    }

    @Test("inject JS marks translation nodes as non-selectable")
    func injectIsNonSelectable() {
        let js = EPUBBilingualJS.bilingualInjectJS(translationsByBid: [:])
        // Translation blocks are decorative — selection should target
        // only source paragraphs. `user-select: none` + the matching
        // `-webkit-user-select: none` (WKWebView) achieves this.
        #expect(
            js.contains("user-select"),
            "inject JS must mark translation nodes `user-select: none` so the selection / highlight pipelines never see them as a target range."
        )
    }

    @Test("inject JS carries the vreader-bilingual class on every block")
    func injectUsesStableClassName() {
        let js = EPUBBilingualJS.bilingualInjectJS(translationsByBid: [:])
        // The class is the host-side handle for clear/restyle — pins
        // the literal so future style edits do not orphan blocks.
        #expect(js.contains("vreader-bilingual"))
    }

    @Test("inject JS escapes translated text through FoliateJSEscaper")
    func injectEscapesTranslatedText() {
        // A translation containing characters that break single-quoted
        // JS literals (single quote, newline, U+2028) must be safely
        // emitted. We compare the JS body against a hand-escaped
        // reference: if escape coverage regresses, the comparison breaks.
        let raw = "Bonjour, c'est l'été\nProchaine ligne\u{2028}fin"
        let escaped = FoliateJSEscaper.escapeForJSString(raw)
        let js = EPUBBilingualJS.bilingualInjectJS(translationsByBid: [
            "bid-1": raw
        ])
        #expect(
            js.contains(escaped),
            "Translated text must be routed through FoliateJSEscaper before interpolation — otherwise an `'` in a translation breaks the literal and the inject step silently fails."
        )
        // And the raw payload must NOT appear unescaped — a regression
        // where the bridge falls back to interpolating raw text would
        // re-introduce a JS injection vector.
        #expect(
            !js.contains(raw),
            "Raw, unescaped translated text must not appear in the injected JS — a regression here would re-introduce a JS injection vector for cached translations sourced from a third-party AI provider."
        )
    }

    @Test("inject JS emits per-bid keys for each translation")
    func injectIncludesBidKeysInLookupTable() {
        let js = EPUBBilingualJS.bilingualInjectJS(translationsByBid: [
            "bid-1": "Salut",
            "bid-2": "Bonjour"
        ])
        // The bid keys MUST appear in the emitted JS so the inject
        // walker can find each translation by id. Both bids must
        // be present.
        #expect(js.contains("bid-1"))
        #expect(js.contains("bid-2"))
    }

    @Test("inject JS is idempotent on the DOM — re-running is a no-op")
    func injectIsIdempotent() {
        let js = EPUBBilingualJS.bilingualInjectJS(translationsByBid: [:])
        // The inject path must check for an existing decoration sibling
        // before appending — otherwise a chapter re-render or a second
        // VM enable produces stacked translation blocks. We pin the
        // existence of the guard literal.
        #expect(
            js.contains("data-vreader-decoration") &&
            (js.contains("nextElementSibling") || js.contains("nextSibling")
                || js.contains("querySelector") || js.contains("alreadyInjected")
                || js.contains("hasAttribute")),
            "inject JS must check for an existing decoration sibling (or other idempotency guard) before appending — otherwise a chapter re-load stacks duplicate translation blocks."
        )
    }

    // MARK: - clearJS

    @Test("clear JS removes every vreader-bilingual node")
    func clearTargetsBilingualClass() {
        let js = EPUBBilingualJS.bilingualClearJS()
        #expect(!js.isEmpty)
        // Clear must target the same class inject emits.
        #expect(
            js.contains("vreader-bilingual"),
            "clear JS must target the `vreader-bilingual` class — same class inject emits."
        )
    }

    @Test("clear JS handles repeated runs safely")
    func clearIsIdempotent() {
        let js = EPUBBilingualJS.bilingualClearJS()
        // A `querySelectorAll(...).forEach` (or equivalent) is the
        // standard pattern — an empty NodeList is a no-op. Pin the
        // operator literal so a regression to `querySelector` (single
        // node) is caught here.
        #expect(
            js.contains("querySelectorAll") || js.contains("getElementsByClassName"),
            "clear JS must enumerate ALL bilingual nodes (querySelectorAll / getElementsByClassName) — a single-node query would leave duplicates if the DOM ever got into a multi-injected state."
        )
    }
}
