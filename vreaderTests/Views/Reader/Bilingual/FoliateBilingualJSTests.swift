// Purpose: Feature #56 WI-11 — pin the AZW3/MOBI bilingual
// interlinear JS contracts (`bilingualEnumerateJS`,
// `bilingualInjectJS`, `bilingualClearJS`). The JS calls into
// `readerAPI.bilingual*` helpers defined on the Foliate host so
// the WKWebView-side enumeration walks the foliate-js renderer's
// current section DOM (not a fresh `createDocument()` — the
// rendered DOM is the only place an inject can be visible).
//
// Behavior-level shape pins (mirror the EPUB WI-10 contracts):
// - enumerate stamps `data-vreader-bid` on each translatable block
//   and posts `[{bid, text}]` to the `bilingualEnumerate` channel.
// - inject appends a `<div class="vreader-bilingual"
//   data-vreader-decoration ...>` after each stamped block.
// - inject and clear are idempotent — re-running them is a no-op
//   when the DOM is already in the requested state.
// - All translation interpolation routes through `FoliateJSEscaper`
//   (proves WKWebView injection is hardened against `'` / line-term
//   / newline payloads in cached translations).
//
// These are JS-source-string pins, not WKWebView-runtime assertions.
// They are exactly the same shape `EPUBBilingualJSTests` pin for
// the EPUB renderer — runtime behavior is verified at slice
// verification time (`vreader-debug://` harness, AZW3 fixture).
//
// @coordinates-with: FoliateBilingualJS.swift, FoliateJSEscaper.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Testing
@testable import vreader

@Suite("Feature #56 WI-11 — FoliateBilingualJS")
struct FoliateBilingualJSTests {

    // MARK: - enumerateJS

    @Test("enumerate JS is non-empty and wires the bilingualEnumerate channel")
    func enumerateJSIsNonEmpty() {
        let js = FoliateBilingualJS.bilingualEnumerateJS()
        #expect(!js.isEmpty)
        // The enumerate path must surface results to Swift via the
        // `bilingualEnumerate` message handler so the host receives
        // `[{bid, text}]` for translation.
        #expect(js.contains("bilingualEnumerate"))
    }

    @Test("enumerate JS invokes readerAPI.bilingualEnumerate")
    func enumerateJSCallsHostAPI() {
        let js = FoliateBilingualJS.bilingualEnumerateJS()
        // Must call the Foliate host's bilingual enumeration helper —
        // the DOM walk runs on the host page where view.renderer is in
        // scope. A regression that walked `document` directly would
        // operate on the empty outer host HTML and produce zero
        // blocks.
        #expect(
            js.contains("readerAPI.bilingualEnumerate"),
            "enumerate JS must call `readerAPI.bilingualEnumerate()` — the bilingual enumeration logic lives on the Foliate host page where `view.renderer.getContents()` exposes the current section DOM."
        )
    }

    @Test("enumerate JS posts blocks via the bilingualEnumerate handler")
    func enumeratePostsToHandler() {
        let js = FoliateBilingualJS.bilingualEnumerateJS()
        // The payload must reach Swift via messageHandlers, not via the
        // evaluateJavaScript completion — `callAsyncJavaScript` would
        // need a different code path, and `evaluateJavaScript` returns
        // a Promise object reference for async expressions, not the
        // awaited value.
        #expect(js.contains("messageHandlers"))
    }

    // MARK: - injectJS

    @Test("inject JS marks translation nodes with data-vreader-decoration")
    func injectMarksDecoration() {
        let js = FoliateBilingualJS.bilingualInjectJS(translationsByBid: [:])
        // The decoration attribute is the cross-format keystone for
        // sibling traversal — Foliate's overlay annotations sit on a
        // separate SVG layer, but the DOM-mutating bilingual inject
        // shares the same attribute name as the EPUB renderer for
        // consistency + future cross-format highlight code.
        #expect(
            js.contains("data-vreader-decoration"),
            "inject JS must stamp `data-vreader-decoration` on every translation node — same keystone the EPUB renderer uses for cross-format consistency."
        )
    }

    @Test("inject JS marks translation nodes as non-selectable")
    func injectIsNonSelectable() {
        let js = FoliateBilingualJS.bilingualInjectJS(translationsByBid: [:])
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
        let js = FoliateBilingualJS.bilingualInjectJS(translationsByBid: [:])
        // The class is the host-side handle for clear/restyle — pins
        // the literal so future style edits do not orphan blocks.
        #expect(js.contains("vreader-bilingual"))
    }

    @Test("inject JS invokes readerAPI.bilingualInject")
    func injectJSCallsHostAPI() {
        let js = FoliateBilingualJS.bilingualInjectJS(translationsByBid: [
            "b1": "Bonjour"
        ])
        #expect(
            js.contains("readerAPI.bilingualInject"),
            "inject JS must call `readerAPI.bilingualInject(...)` — the inject runs on the Foliate host page where `view.renderer.getContents()` returns the current section DOM."
        )
    }

    @Test("inject JS escapes translated text through FoliateJSEscaper")
    func injectEscapesTranslatedText() {
        // A translation containing characters that break single-quoted
        // JS literals (single quote, newline, U+2028) must be safely
        // emitted. Compare against a hand-escaped reference: if escape
        // coverage regresses, the comparison breaks.
        let raw = "Bonjour, c'est l'été\nProchaine ligne\u{2028}fin"
        let escaped = FoliateJSEscaper.escapeForJSString(raw)
        let js = FoliateBilingualJS.bilingualInjectJS(translationsByBid: [
            "bid-1": raw
        ])
        #expect(
            js.contains(escaped),
            "Translated text must route through FoliateJSEscaper before interpolation — otherwise an `'` in a translation breaks the literal and the inject step silently fails."
        )
        // And the raw payload must NOT appear unescaped — a regression
        // that bypassed the escape pipeline would re-introduce a JS
        // injection vector for cached translations sourced from a
        // third-party AI provider.
        #expect(
            !js.contains(raw),
            "Raw, unescaped translated text must not appear in the injected JS — a regression here would re-introduce a JS injection vector for cached translations sourced from a third-party AI provider."
        )
    }

    @Test("inject JS emits per-bid keys for each translation")
    func injectIncludesBidKeysInLookupTable() {
        let js = FoliateBilingualJS.bilingualInjectJS(translationsByBid: [
            "bid-1": "Salut",
            "bid-2": "Bonjour"
        ])
        #expect(js.contains("bid-1"))
        #expect(js.contains("bid-2"))
    }

    // MARK: - clearJS

    @Test("clear JS invokes readerAPI.bilingualClear")
    func clearJSCallsHostAPI() {
        let js = FoliateBilingualJS.bilingualClearJS()
        #expect(!js.isEmpty)
        #expect(
            js.contains("readerAPI.bilingualClear"),
            "clear JS must call `readerAPI.bilingualClear()` — the clear walk runs on the Foliate host page over `view.renderer.getContents()` to reach every loaded section's DOM."
        )
    }

    // MARK: - Per-section scoping (Gate-4 audit H2)

    @Test("enumerate JS passes the targetSectionIndex argument to the host helper")
    func enumerateJSScopesToSection() {
        let scoped = FoliateBilingualJS.bilingualEnumerateJS(
            targetSectionIndex: 3)
        // The integer literal must appear in the readerAPI call so
        // the host helper can scope its DOM walk.
        #expect(
            scoped.contains("bilingualEnumerate(3)"),
            "scoped enumerate JS must call `readerAPI.bilingualEnumerate(3)` so the host helper walks only section 3's DOM."
        )
    }

    @Test("enumerate JS without a section index emits the null fallback")
    func enumerateJSUnscoped() {
        let unscoped = FoliateBilingualJS.bilingualEnumerateJS()
        #expect(
            unscoped.contains("bilingualEnumerate(null)"),
            "unscoped enumerate JS must call `readerAPI.bilingualEnumerate(null)` so the host helper falls back to every loaded section (the legacy / clear-path semantics)."
        )
    }

    @Test("inject JS carries the targetSectionIndex argument in its payload")
    func injectJSScopesToSection() {
        let scoped = FoliateBilingualJS.bilingualInjectJS(
            translationsByBid: ["b1": "Bonjour"],
            targetSectionIndex: 5
        )
        #expect(
            scoped.contains("targetSectionIndex: 5"),
            "scoped inject JS must carry `targetSectionIndex: 5` so the host helper scopes its inject walk to one section's DOM."
        )
    }

    @Test("clear JS passes the targetSectionIndex argument")
    func clearJSScopesToSection() {
        let scoped = FoliateBilingualJS.bilingualClearJS(
            targetSectionIndex: 2)
        #expect(
            scoped.contains("bilingualClear(2)"),
            "scoped clear JS must call `readerAPI.bilingualClear(2)` so the host helper scopes its clear walk to section 2."
        )
    }
}
