// Purpose: Unit tests for the EPUB DebugBridge highlight-driver JS builder
// (Bug #220 / GH #845 — verification harness highlight-creator for EPUB).
// The helper builds the JS expression that the observer evaluates in the
// active EPUB WKWebView to resolve `[start, end)` UTF-16 offsets into a
// real DOM range, returning the resulting serialized range to Swift for
// persistence. Paint is done by `HighlightCoordinator.create` →
// `EPUBHighlightRenderer.apply(record:)` using the canonical persisted
// UUID, so this JS deliberately does NOT call `__vreader_createHighlight`
// (Codex Gate-4 Round-1 High fix).
//
// Mirrors `DebugBridgeHighlightObserverTests` (TXT/MD) but the unit
// surface here is JS construction + result parsing, since the EPUB path
// goes through the WKWebView.

#if DEBUG

import XCTest
@testable import vreader

final class EPUBDebugBridgeHighlightJSTests: XCTestCase {

    // MARK: - JS construction — start/end inlined as integers

    func test_buildJS_inlinesStartEndAsIntegers() {
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 10, endUTF16: 42
        )
        XCTAssertTrue(
            js.contains("var TARGET_START = 10;"),
            "start must be inlined as an integer literal"
        )
        XCTAssertTrue(
            js.contains("var TARGET_END = 42;"),
            "end must be inlined as an integer literal"
        )
    }

    func test_buildJS_startZero_inlinedCorrectly() {
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 0, endUTF16: 5
        )
        XCTAssertTrue(
            js.contains("var TARGET_START = 0;"),
            "start=0 must be honored, not treated as missing"
        )
        XCTAssertTrue(js.contains("var TARGET_END = 5;"))
    }

    // MARK: - JS construction — does NOT paint (the gesture-parity fix)

    func test_buildJS_doesNotCallCreateHighlight() {
        // Codex Gate-4 Round-1 High fix: the JS resolves the DOM range
        // only. Paint goes through the Swift-side coordinator → renderer
        // → JS pipeline with the canonical persisted UUID, so a transient
        // JS-side ID can never leak onto the live page.
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 0, endUTF16: 5
        )
        XCTAssertFalse(
            js.contains("__vreader_createHighlight"),
            "the resolve-only JS must NOT paint — paint happens via the renderer with the canonical persisted UUID"
        )
    }

    func test_buildJS_returnsResultObject() {
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 0, endUTF16: 5
        )
        // The JS must end with a `return` that produces the result payload —
        // the caller (Swift) reads this back from evaluateJavaScript.
        XCTAssertTrue(
            js.contains("startPath") && js.contains("endPath"),
            "JS must surface startPath/endPath in its return value so Swift can build a EPUBSerializedRange"
        )
        XCTAssertTrue(
            js.contains("startOffset") && js.contains("endOffset"),
            "JS must surface startOffset/endOffset"
        )
        XCTAssertTrue(
            js.contains("selectedText"),
            "JS must surface selectedText so persistence carries the highlighted phrase"
        )
    }

    func test_buildJS_isWrappedInIIFE() {
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 0, endUTF16: 5
        )
        // IIFE pattern (function() { ... })() ensures local vars don't leak
        // into window scope across repeated invocations.
        XCTAssertTrue(
            js.hasPrefix("(function()") || js.hasPrefix("(function ()"),
            "the JS must be wrapped in an IIFE so locals (TARGET_START, etc.) don't pollute window"
        )
    }

    // MARK: - JS construction — gesture-parity checks

    func test_buildJS_snapsSurrogatePairBoundaries() {
        // Codex Gate-4 Round-1 Medium fix: a UTF-16 offset landing
        // between the surrogate halves of a non-BMP scalar would split
        // the scalar. The JS must include a snap step around `locate`.
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 0, endUTF16: 5
        )
        XCTAssertTrue(
            js.contains("snapToScalarBoundary"),
            "JS must include surrogate-pair boundary snapping"
        )
        XCTAssertTrue(
            js.contains("0xD800") && js.contains("0xDC00"),
            "JS must check both high+low surrogate code-unit ranges"
        )
    }

    func test_buildJS_rejectsWhitespaceOnlySelection() {
        // Codex Gate-4 Round-1 Medium fix: the gesture path rejects
        // `!text.trim()`. The bridge JS must match that semantic.
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 0, endUTF16: 5
        )
        // Look for `\S` regex test in the JS body — that's the
        // non-whitespace-only check.
        XCTAssertTrue(
            js.contains("\\S"),
            "JS must reject whitespace-only selections to match gesture-path semantics"
        )
    }

    func test_buildJS_skipsBilingualDecorationNodes() {
        // The XPath builder and node walker must skip `data-vreader-decoration`
        // (bilingual mode) so the offset math matches the production
        // selection-tracking XPath serializer.
        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: 0, endUTF16: 5
        )
        XCTAssertTrue(
            js.contains("data-vreader-decoration"),
            "JS must skip bilingual decoration nodes to preserve XPath parity with selectionTrackingJS"
        )
    }

    // MARK: - Result parsing — JS result → EPUBSerializedRange

    func test_parseResult_validDict_returnsRange() {
        let dict: [String: Any] = [
            "startPath": "/html/body/p[1]/text()[1]",
            "startOffset": 10,
            "endPath": "/html/body/p[1]/text()[1]",
            "endOffset": 15,
            "selectedText": "hello",
        ]
        let parsed = EPUBDebugBridgeHighlightJS.parseResult(dict)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.range.startContainerPath, "/html/body/p[1]/text()[1]")
        XCTAssertEqual(parsed?.range.startOffset, 10)
        XCTAssertEqual(parsed?.range.endContainerPath, "/html/body/p[1]/text()[1]")
        XCTAssertEqual(parsed?.range.endOffset, 15)
        XCTAssertEqual(parsed?.selectedText, "hello")
    }

    func test_parseResult_missingStartPath_returnsNil() {
        let dict: [String: Any] = [
            "startOffset": 10,
            "endPath": "/html/body/p[1]/text()[1]",
            "endOffset": 15,
            "selectedText": "hello",
        ]
        XCTAssertNil(EPUBDebugBridgeHighlightJS.parseResult(dict))
    }

    func test_parseResult_emptySelectedText_returnsNil() {
        // An out-of-range request leaves the JS returning `null` from the
        // top level; if for any reason it returns a result with empty
        // selectedText, treat it as invalid — a zero-length range was
        // already rejected by the parser, so empty here means the JS
        // didn't find anything.
        let dict: [String: Any] = [
            "startPath": "/html/body/p[1]/text()[1]",
            "startOffset": 10,
            "endPath": "/html/body/p[1]/text()[1]",
            "endOffset": 10,
            "selectedText": "",
        ]
        XCTAssertNil(EPUBDebugBridgeHighlightJS.parseResult(dict))
    }

    func test_parseResult_offsetsAsDouble_areAccepted() {
        // WKWebView's `evaluateJavaScript` returns JS Number values as
        // `NSNumber` which can deserialize as either `Int` or `Double`
        // depending on the value. The parser must accept both.
        let dict: [String: Any] = [
            "startPath": "/html/body/p[1]/text()[1]",
            "startOffset": Double(10),
            "endPath": "/html/body/p[1]/text()[1]",
            "endOffset": Double(15),
            "selectedText": "hello",
        ]
        let parsed = EPUBDebugBridgeHighlightJS.parseResult(dict)
        XCTAssertEqual(parsed?.range.startOffset, 10)
        XCTAssertEqual(parsed?.range.endOffset, 15)
    }

    func test_parseResult_notADictionary_returnsNil() {
        XCTAssertNil(EPUBDebugBridgeHighlightJS.parseResult(NSNull()))
        XCTAssertNil(EPUBDebugBridgeHighlightJS.parseResult("not a dict"))
        XCTAssertNil(EPUBDebugBridgeHighlightJS.parseResult([Int]()))
    }
}

#endif
