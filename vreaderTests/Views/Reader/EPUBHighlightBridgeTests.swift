// Purpose: Tests for EPUBHighlightBridge — JS message parsing, JS generation,
// notification posting, and edge cases.
//
// @coordinates-with: EPUBHighlightBridge.swift, AnnotationAnchor.swift,
//   ReaderNotifications.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("EPUBHighlightBridge")
struct EPUBHighlightBridgeTests {

    // MARK: - Selection Message Parsing

    @Test("parses selection message with all fields")
    func selectionMessageParsesCorrectly() {
        let body: [String: Any] = [
            "selectedText": "Hello World",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 5,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 16,
            "rectX": 100.0,
            "rectY": 200.0,
            "rectWidth": 150.0,
            "rectHeight": 20.0
        ]

        let result = EPUBHighlightBridge.parseSelectionMessage(body)
        #expect(result != nil)
        let parsed = result!
        #expect(parsed.selectedText == "Hello World")
        #expect(parsed.range.startContainerPath == "/html/body/p[1]/text()")
        #expect(parsed.range.startOffset == 5)
        #expect(parsed.range.endContainerPath == "/html/body/p[1]/text()")
        #expect(parsed.range.endOffset == 16)
        #expect(parsed.sourceRect.origin.x == 100.0)
        #expect(parsed.sourceRect.origin.y == 200.0)
        #expect(parsed.sourceRect.size.width == 150.0)
        #expect(parsed.sourceRect.size.height == 20.0)
    }

    @Test("parses selection message with CJK text")
    func selectionMessageWithCJKText() {
        let body: [String: Any] = [
            "selectedText": "你好世界",
            "startPath": "/html/body/div[@class='中文']/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/div[@class='中文']/p[1]/text()",
            "endOffset": 4,
            "rectX": 10.0, "rectY": 20.0, "rectWidth": 80.0, "rectHeight": 20.0
        ]

        let result = EPUBHighlightBridge.parseSelectionMessage(body)
        #expect(result != nil)
        #expect(result!.selectedText == "你好世界")
        #expect(result!.range.startContainerPath == "/html/body/div[@class='中文']/p[1]/text()")
    }

    @Test("returns nil for missing selectedText")
    func selectionMessageMissingText() {
        let body: [String: Any] = [
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for missing startPath")
    func selectionMessageMissingStartPath() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for missing endPath")
    func selectionMessageMissingEndPath() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for non-dictionary body")
    func selectionMessageNonDictionary() {
        let body = "not a dictionary"
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("returns nil for non-integer offsets")
    func selectionMessageNonIntegerOffsets() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": "not a number",
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("defaults rect to zero when rect fields missing")
    func selectionMessageMissingRectDefaultsToZero() {
        let body: [String: Any] = [
            "selectedText": "Hello",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5
        ]
        let result = EPUBHighlightBridge.parseSelectionMessage(body)
        #expect(result != nil)
        #expect(result!.sourceRect == .zero)
    }

    // MARK: - Empty Selection Filtering

    @Test("empty selectedText returns nil")
    func emptySelectionIgnored() {
        let body: [String: Any] = [
            "selectedText": "",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 0,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    @Test("whitespace-only selectedText returns nil")
    func whitespaceOnlySelectionIgnored() {
        let body: [String: Any] = [
            "selectedText": "   \n\t  ",
            "startPath": "/html/body/p[1]/text()",
            "startOffset": 0,
            "endPath": "/html/body/p[1]/text()",
            "endOffset": 5,
            "rectX": 0.0, "rectY": 0.0, "rectWidth": 0.0, "rectHeight": 0.0
        ]
        #expect(EPUBHighlightBridge.parseSelectionMessage(body) == nil)
    }

    // MARK: - Anchor Construction

    @Test("makeAnchor creates epub anchor with correct fields")
    func makeAnchorCreatesEPUBAnchor() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 5,
            endContainerPath: "/html/body/p[2]/text()",
            endOffset: 10
        )
        let anchor = EPUBHighlightBridge.makeAnchor(
            href: "chapter1.xhtml",
            cfi: "/6/4",
            range: range
        )
        if case .epub(let href, let cfi, let serializedRange) = anchor {
            #expect(href == "chapter1.xhtml")
            #expect(cfi == "/6/4")
            #expect(serializedRange == range)
        } else {
            Issue.record("Expected epub anchor")
        }
    }

    @Test("makeAnchor with empty cfi")
    func makeAnchorWithEmptyCFI() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 5
        )
        let anchor = EPUBHighlightBridge.makeAnchor(href: "ch.xhtml", cfi: "", range: range)
        if case .epub(_, let cfi, _) = anchor {
            #expect(cfi == "")
        } else {
            Issue.record("Expected epub anchor")
        }
    }

    // MARK: - Highlight Injection JS

    @Test("createHighlightJS produces valid JavaScript")
    func highlightInjectionProducesValidJS() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 5,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 16
        )
        let js = EPUBHighlightBridge.createHighlightJS(
            id: "highlight-123",
            range: range,
            color: "yellow"
        )
        #expect(js.contains("highlight-123"))
        #expect(js.contains("yellow"))
        #expect(js.contains("/html/body/p[1]/text()"))
        #expect(js.contains("5"))
        #expect(js.contains("16"))
        #expect(js.contains("createHighlight"))
    }

    @Test("createHighlightJS escapes special characters in ID")
    func highlightJSEscapesSpecialCharsInID() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 5
        )
        let js = EPUBHighlightBridge.createHighlightJS(
            id: "id-with'quotes\"and\\backslash",
            range: range,
            color: "blue"
        )
        // Bug #135: jsEscape now delegates to FoliateJSEscaper. Single
        // quotes (the delimiter) and backslashes are escaped; double
        // quotes inside a single-quoted string don't need escaping per
        // ECMAScript and are passed through. Assert that the apostrophe
        // is escaped (the only one that would actually break the string
        // literal) rather than over-asserting on `"`.
        #expect(js.contains("\\'quotes"))
        #expect(js.contains("createHighlight"))
    }

    @Test("createHighlightJS with CJK XPath")
    func highlightJSWithCJKXPath() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/div[@class='中文']/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/div[@class='中文']/p[1]/text()",
            endOffset: 4
        )
        let js = EPUBHighlightBridge.createHighlightJS(
            id: "cjk-hl",
            range: range,
            color: "yellow"
        )
        #expect(js.contains("createHighlight"))
    }

    // MARK: - Remove Highlight JS

    @Test("removeHighlightJS produces valid script")
    func removeHighlightJSIsValid() {
        let js = EPUBHighlightBridge.removeHighlightJS(id: "highlight-456")
        #expect(js.contains("highlight-456"))
        #expect(js.contains("removeHighlight"))
    }

    @Test("removeHighlightJS escapes special characters")
    func removeHighlightJSEscapesSpecialChars() {
        let js = EPUBHighlightBridge.removeHighlightJS(id: "id'with\"quotes")
        #expect(js.contains("removeHighlight"))
        // Bug #135: only the apostrophe needs escaping inside a single-
        // quoted string literal. Double-quote pass-through is correct
        // per ECMAScript.
        #expect(js.contains("id\\'with\"quotes"))
    }

    @Test("searchHighlightJS escapes U+2028 / U+2029 / tab — bug #135")
    func searchHighlightEscapesECMAScriptLineTerminators() {
        // Per ECMAScript, U+2028 and U+2029 terminate string literals.
        // A search query containing one of these (legit in some CJK
        // ebooks) would have produced a SyntaxError in the embedded
        // window.find() call. Bug #135 fixes it by routing through
        // FoliateJSEscaper.
        let queryWith2028 = "before\u{2028}after"
        let queryWith2029 = "before\u{2029}after"
        let queryWithTab = "before\tafter"
        let js2028 = EPUBHighlightBridge.searchHighlightJS(textQuote: queryWith2028)
        let js2029 = EPUBHighlightBridge.searchHighlightJS(textQuote: queryWith2029)
        let jsTab = EPUBHighlightBridge.searchHighlightJS(textQuote: queryWithTab)
        // Raw separator chars must NOT appear in the generated JS;
        // their escape sequences must.
        #expect(!js2028.contains("\u{2028}"))
        #expect(js2028.contains("\\u2028"))
        #expect(!js2029.contains("\u{2029}"))
        #expect(js2029.contains("\\u2029"))
        #expect(!jsTab.contains("\t"))
        #expect(jsTab.contains("\\t"))
    }

    // MARK: - Search Highlight Retry (bug #182 round-3)

    @Test("searchHighlightJS retries window.find() until the chapter settles — bug #182")
    func searchHighlightJSRetriesWindowFind() {
        // Bug #182 round-3: a cross-chapter search-result tap defers the
        // highlight JS to `webView(_:didFinish:)`, but at that instant the
        // freshly-loaded EPUB chapter has not finished its post-load
        // relayout — foliate-js `cssPreprocessJS` rewrites every `-epub-*`
        // / `page-break-*` rule `atDocumentEnd`. A single `window.find()`
        // there returns false, so the `.vreader_search_highlight` span is
        // never created (the user-visible "navigates but no highlight"
        // symptom). The generated JS must poll `window.find()` on a short
        // cadence until the rendered text tree is searchable.
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "navigation")
        #expect(js.contains("window.find("), "must still locate text via window.find()")
        #expect(
            js.contains("setTimeout(attempt"),
            "a failed window.find() must reschedule another attempt — not give up after one"
        )
    }

    @Test("searchHighlightJS retry is bounded and self-terminates — bug #182 round-3")
    func searchHighlightJSRetryIsBounded() {
        // A genuinely-absent quote must not poll forever: each failed
        // attempt decrements a counter and rescheduling is gated on it.
        // The success path returns before that decrement-and-reschedule
        // tail, so a found highlight is never re-found.
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "navigation")
        #expect(js.contains("attemptsLeft--"), "each failed attempt must decrement the counter")
        #expect(js.contains("if (attemptsLeft > 0)"), "rescheduling must be gated on the counter")
        #expect(js.contains("return;"), "the success path must return before the reschedule tail")
    }

    @Test("searchHighlightJS supersedes a prior in-flight retry loop — bug #182 round-3")
    func searchHighlightJSSupersedesConcurrentLoops() {
        // Two rapid same-chapter search taps must not leave two retry
        // loops racing and double-wrapping spans: each invocation bumps a
        // generation token and bails once a newer invocation supersedes it.
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "navigation")
        #expect(
            js.contains("__vreaderSearchHighlightGen"),
            "must guard against concurrent retry loops via a generation token"
        )
    }

    @Test("searchHighlightJS retry preserves the 3s auto-clear — bug #182 round-3")
    func searchHighlightJSRetryKeepsAutoClear() {
        // The retry rewrite must not drop the temporary-highlight contract:
        // once the span is wrapped it still auto-clears after 3 seconds.
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "navigation")
        #expect(js.contains("3000"), "the temporary search highlight must still auto-clear after 3s")
    }

    // MARK: - Restore Highlights JS

    @Test("restoreHighlightsJS produces valid script for multiple highlights")
    func highlightRestoreJSProducesValidScript() {
        let range1 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let range2 = EPUBSerializedRange(
            startContainerPath: "/html/body/p[2]/text()",
            startOffset: 5,
            endContainerPath: "/html/body/p[2]/text()",
            endOffset: 20
        )

        let highlights: [(id: String, range: EPUBSerializedRange, color: String)] = [
            ("hl-1", range1, "yellow"),
            ("hl-2", range2, "blue")
        ]

        let js = EPUBHighlightBridge.restoreHighlightsJS(highlights: highlights)
        #expect(js.contains("hl-1"))
        #expect(js.contains("hl-2"))
        #expect(js.contains("yellow"))
        #expect(js.contains("blue"))
        #expect(js.contains("createHighlight"))
    }

    @Test("restoreHighlightsJS with empty array produces no-op")
    func highlightRestoreJSEmptyArray() {
        let js = EPUBHighlightBridge.restoreHighlightsJS(highlights: [])
        // Should be empty or a minimal no-op, not crash
        #expect(js.isEmpty || js.contains("(function"))
    }

    // MARK: - Clear All Highlights JS

    @Test("clearAllHighlightsJS produces valid script")
    func clearAllHighlightsJSIsValid() {
        let js = EPUBHighlightBridge.clearAllHighlightsJS
        #expect(js.contains("clearAllHighlights") || js.contains("CSS.highlights"))
    }

    // MARK: - Selection Event Construction

    @Test("makeSelectionEvent creates event with correct fields")
    func selectionEventConstructedCorrectly() {
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let event = EPUBHighlightBridge.makeSelectionEvent(
            selectedText: "Hello World",
            href: "chapter1.xhtml",
            cfi: "/6/4",
            range: range,
            sourceRect: CGRect(x: 100, y: 200, width: 150, height: 20)
        )
        #expect(event.selectedText == "Hello World")
        if case .epub(let href, let cfi, let serializedRange) = event.anchor {
            #expect(href == "chapter1.xhtml")
            #expect(cfi == "/6/4")
            #expect(serializedRange == range)
        } else {
            Issue.record("Expected epub anchor")
        }
        #expect(event.sourceRect.origin.x == 100)
    }

    // MARK: - JS Source Validation

    @Test("selection tracking JS is non-empty and valid")
    func selectionTrackingJSIsValid() {
        let js = EPUBHighlightBridge.selectionTrackingJS
        #expect(!js.isEmpty)
        #expect(js.contains("selectionchange") || js.contains("selectionChanged"))
        #expect(js.contains("webkit.messageHandlers"))
    }

    @Test("highlight API JS is non-empty and contains key functions")
    func highlightAPIJSIsValid() {
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(!js.isEmpty)
        #expect(js.contains("createHighlight"))
        #expect(js.contains("removeHighlight"))
        #expect(js.contains("clearAllHighlights"))
    }

    @Test("highlightAPIJS rewrites XPath for XHTML namespace (bug #159 / GH #472)")
    func highlightAPIJS_rewritesXPathForXHTMLNamespace() {
        // Bug #159 / GH #472: EPUB content is loaded as `application/xhtml+xml`,
        // which means `documentElement.namespaceURI` is
        // `http://www.w3.org/1999/xhtml`. XPath 1.0 element names without a
        // namespace prefix do NOT match elements in a non-null default
        // namespace, so `document.evaluate("/html/body/p[3]", ...)` returns
        // null on EPUB pages. The selection-tracking JS produced unqualified
        // paths and the highlight resolver couldn't find the nodes again.
        // The fix rewrites unqualified element segments to `*[local-name()=...]`
        // when the document has a namespace, so the same path matches the
        // XHTML-namespaced elements regardless of their default namespace.
        let js = EPUBHighlightBridge.highlightAPIJS
        // The fix MUST add a `local-name()` predicate translation in the
        // resolver. Pinning this token forces a deliberate review if anyone
        // tries to remove the fix; the alternative (verifying behavior in JS
        // runtime) requires a WKWebView + XHTML doc — out of scope for unit
        // tests.
        #expect(
            js.contains("local-name()"),
            "highlightAPIJS must rewrite XPath element names to use local-name() predicate so XHTML-namespaced EPUB pages can resolve selection paths back to nodes (bug #159)."
        )
    }

    @Test("highlightAPIJS preserves text() and attribute axis steps when rewriting (bug #159)")
    func highlightAPIJS_preservesNonElementSteps() {
        // The XPath rewrite must NOT touch `/text()`, `/comment()`, etc. —
        // those are namespace-agnostic XPath axes. If the rewrite blanket-
        // replaces every `/<word>` with `*[local-name()=...]`, selection
        // paths like `/html/body/p[3]/text()[1]` (the typical shape produced
        // by `getXPath` for selected text nodes) would be corrupted into
        // `*[local-name()="text"]()` — invalid XPath. This test pins that
        // the source explicitly carries the `text()` token through.
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(
            js.contains("text()"),
            "highlightAPIJS must reference `text()` (the selection-path axis) so the XPath rewrite path can preserve it (bug #159)."
        )
    }

    @Test("highlightAPIJS handles prefix-qualified element names (Codex audit, bug #159)")
    func highlightAPIJS_handlesPrefixedElementNames() {
        // Codex audit (round 1, Medium): EPUBs with mixed-namespace inline
        // content (e.g. inline SVG declared via `xmlns:svg=...`) can produce
        // selection paths whose element names carry a prefix like
        // `/html/body/svg:svg/svg:text/text()[1]`. A naive regex that only
        // accepts `[A-Za-z][A-Za-z0-9_-]*` for the captured name would
        // consume only `/svg` and leave a stray `:svg` segment in the
        // output, breaking the path. The fix accepts a single optional
        // `:prefix` within the captured name and strips the prefix before
        // emitting `*[local-name()="..."]`. This test pins the source
        // pattern that enables that handling — both the colon in the
        // character class and the `indexOf(':')` strip step must be present.
        let js = EPUBHighlightBridge.highlightAPIJS
        #expect(
            js.contains("indexOf(':')"),
            "highlightAPIJS must strip the namespace prefix from prefix-qualified element names so XPath like `/html/body/svg:svg` resolves to the SVG element regardless of its namespace (Codex audit, bug #159)."
        )
        #expect(
            js.contains(":[A-Za-z"),
            "highlightAPIJS regex must accept a `:prefix` segment inside the captured element name; otherwise prefixed steps like `/svg:svg` are corrupted by the rewrite (Codex audit, bug #159)."
        )
    }
}
#endif
