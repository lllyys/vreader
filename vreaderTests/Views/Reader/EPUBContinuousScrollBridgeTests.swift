// Purpose: Feature #71 WI-5 — unit tests for the bridge-side glue that wires the
// continuous-scroll observer into `EPUBWebViewBridge`: the `continuousScrollHandler`
// JS-message parser (`EPUBScrollBoundarySignal.parse`), the windowed-progress
// mapping (`EPUBContinuousScrollConfig.windowedProgress`), and the section-scoped
// selection href carried on `EPUBSelectionMessage`. All pure — no live WKWebView.
//
// @coordinates-with: EPUBContinuousScrollBridge.swift, EPUBContinuousScrollCoordinator.swift,
//   EPUBHighlightBridge.swift, EPUBProgressCalculator.swift

import Testing
import Foundation
@testable import vreader

@Suite("EPUBContinuousScroll bridge glue (Feature #71 WI-5)")
struct EPUBContinuousScrollBridgeTests {

    // MARK: - EPUBScrollBoundarySignal.parse

    private func body(
        visible: Any? = 2,
        intra: Any? = 0.5,
        top: Any? = false,
        bottom: Any? = true
    ) -> [String: Any] {
        var d: [String: Any] = [:]
        if let visible { d["visibleSpineIndex"] = visible }
        if let intra { d["intraFraction"] = intra }
        if let top { d["nearTopBoundary"] = top }
        if let bottom { d["nearBottomBoundary"] = bottom }
        return d
    }

    @Test("parses a well-formed observer message")
    func parsesValid() throws {
        let signal = try #require(EPUBScrollBoundarySignal.parse(body()))
        #expect(signal.visibleSpineIndex == 2)
        #expect(signal.intraFraction == 0.5)
        #expect(signal.nearTopBoundary == false)
        #expect(signal.nearBottomBoundary == true)
    }

    @Test("clamps intraFraction into 0...1")
    func clampsIntraFraction() throws {
        let high = try #require(EPUBScrollBoundarySignal.parse(body(intra: 1.8)))
        #expect(high.intraFraction == 1.0)
        let low = try #require(EPUBScrollBoundarySignal.parse(body(intra: -0.3)))
        #expect(low.intraFraction == 0.0)
    }

    @Test("coerces NSNumber bool flags (JS booleans arrive as NSNumber)")
    func coercesNSNumberBools() throws {
        let signal = try #require(EPUBScrollBoundarySignal.parse(
            body(top: NSNumber(value: 1), bottom: NSNumber(value: 0))
        ))
        #expect(signal.nearTopBoundary == true)
        #expect(signal.nearBottomBoundary == false)
    }

    @Test("coerces an integer-valued Double visibleSpineIndex")
    func coercesDoubleIndex() throws {
        let signal = try #require(EPUBScrollBoundarySignal.parse(body(visible: 3.0)))
        #expect(signal.visibleSpineIndex == 3)
    }

    @Test("non-dictionary body is rejected")
    func rejectsNonDict() {
        #expect(EPUBScrollBoundarySignal.parse("not a dict") == nil)
        #expect(EPUBScrollBoundarySignal.parse(42) == nil)
    }

    @Test("missing visibleSpineIndex is rejected")
    func rejectsMissingIndex() {
        #expect(EPUBScrollBoundarySignal.parse(body(visible: nil)) == nil)
    }

    @Test("missing intraFraction is rejected")
    func rejectsMissingFraction() {
        #expect(EPUBScrollBoundarySignal.parse(body(intra: nil)) == nil)
    }

    @Test("negative visibleSpineIndex is rejected (a section index can't be negative)")
    func rejectsNegativeIndex() {
        #expect(EPUBScrollBoundarySignal.parse(body(visible: -1)) == nil)
    }

    @Test("fractional visibleSpineIndex is rejected (3.9 is malformed, not index 3)")
    func rejectsFractionalIndex() {
        #expect(EPUBScrollBoundarySignal.parse(body(visible: 3.9)) == nil)
    }

    @Test("boolean visibleSpineIndex is rejected (a JS true is not index 1)")
    func rejectsBoolIndex() {
        #expect(EPUBScrollBoundarySignal.parse(body(visible: true)) == nil)
        #expect(EPUBScrollBoundarySignal.parse(body(visible: NSNumber(value: true))) == nil)
    }

    @Test("boolean intraFraction is rejected (not coerced to 1.0)")
    func rejectsBoolFraction() {
        #expect(EPUBScrollBoundarySignal.parse(body(intra: true)) == nil)
    }

    @Test("missing boundary flags default to false (a missing flag means 'not near')")
    func missingFlagsDefaultFalse() throws {
        let signal = try #require(EPUBScrollBoundarySignal.parse(body(top: nil, bottom: nil)))
        #expect(signal.nearTopBoundary == false)
        #expect(signal.nearBottomBoundary == false)
    }

    // MARK: - windowedProgress

    @Test("windowed progress maps (spineIndex + intraFraction) / spineCount")
    func windowedProgressMapping() {
        // spine 2 at 50% of a 10-chapter book → (2 + 0.5)/10 = 0.25
        let signal = EPUBScrollBoundarySignal(
            visibleSpineIndex: 2, intraFraction: 0.5,
            nearTopBoundary: false, nearBottomBoundary: false
        )
        let p = EPUBContinuousScrollConfig.windowedProgress(signal: signal, totalSpineCount: 10)
        #expect(abs(p - 0.25) < 1e-9)
    }

    @Test("windowed progress is clamped + safe for a zero spine count")
    func windowedProgressGuards() {
        let signal = EPUBScrollBoundarySignal(
            visibleSpineIndex: 9, intraFraction: 1.0,
            nearTopBoundary: false, nearBottomBoundary: false
        )
        // last chapter, fully scrolled, 10 chapters → 1.0
        #expect(EPUBContinuousScrollConfig.windowedProgress(signal: signal, totalSpineCount: 10) == 1.0)
        // zero spine count → 0 (no divide-by-zero)
        #expect(EPUBContinuousScrollConfig.windowedProgress(signal: signal, totalSpineCount: 0) == 0.0)
    }

    // MARK: - section-scoped selection href (Gate-2 Critical [C1])

    @Test("selection message carries the section href when present")
    func selectionCarriesSectionHref() throws {
        let dict: [String: Any] = [
            "selectedText": "hello",
            "startPath": "/p[1]/text()[1]", "endPath": "/p[1]/text()[1]",
            "startOffset": 0, "endOffset": 5,
            "sectionHref": "OEBPS/ch3.xhtml",
        ]
        let msg = try #require(EPUBHighlightBridge.parseSelectionMessage(dict))
        #expect(msg.sectionHref == "OEBPS/ch3.xhtml")
    }

    @Test("selection message section href is nil in legacy single-chapter mode (key absent)")
    func selectionSectionHrefNilWhenAbsent() throws {
        let dict: [String: Any] = [
            "selectedText": "hello",
            "startPath": "/p[1]/text()[1]", "endPath": "/p[1]/text()[1]",
            "startOffset": 0, "endOffset": 5,
        ]
        let msg = try #require(EPUBHighlightBridge.parseSelectionMessage(dict))
        #expect(msg.sectionHref == nil)
    }

    @Test("empty sectionHref string is treated as nil (degenerate clamp → no section)")
    func selectionEmptySectionHrefIsNil() throws {
        let dict: [String: Any] = [
            "selectedText": "hello",
            "startPath": "/p[1]/text()[1]", "endPath": "/p[1]/text()[1]",
            "startOffset": 0, "endOffset": 5,
            "sectionHref": "",
        ]
        let msg = try #require(EPUBHighlightBridge.parseSelectionMessage(dict))
        #expect(msg.sectionHref == nil)
    }
}
