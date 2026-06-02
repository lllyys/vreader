// Purpose: Feature #76 WI-2 — the scrolled-mode `#container` must lay out
// sections along the ACTIVE SCROLL AXIS so the windowed surface (WI-3)
// accumulates in the right direction for vertical-writing AZW3/MOBI (the Bug
// #283 chapter-boundary jump). Horizontal-writing (vertical scroll) keeps the
// default block stacking — byte-identical to Feature #73.
//
// The layout runs inside a WKWebView, so the runtime path is not unit-testable
// directly. Following the FoliatePaginatorScrollBoundaryTests pattern, this file
// pins the static contract: both the source `paginator.js` and the built
// `foliate-bundle.js` declare `#applyScrolledContainerAxis`, invoke it from
// `#display` BEFORE the windowing gate (so it runs for vertical even while
// `#ensureWindow` still returns early — WI-3 removes that gate), and the helper
// orients the container by the ScrollModel axis (flex row / row-reverse for
// vertical-writing; reset to block for horizontal-writing).
//
// @coordinates-with: vreader/Services/Foliate/JS/paginator.js,
//   vreader/Services/Foliate/JS/foliate-bundle.js, FoliateScrollModelTests.swift

import Testing
import Foundation

@Suite("Foliate paginator — WI-2 axis-aware scrolled container layout (Feature #76 / Bug #283)")
struct FoliateVerticalContainerLayoutTests {

    private func loadBundle() throws -> String {
        let candidates: [Bundle] = [Bundle(for: BundleToken.self), .main]
        for c in candidates {
            if let url = c.url(forResource: "foliate-bundle", withExtension: "js") {
                return try String(contentsOf: url, encoding: .utf8)
            }
        }
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "foliate-bundle.js not found"])
    }

    private func loadSource() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("vreader/Services/Foliate/JS/paginator.js")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Declaration + call wired (source + bundle parity)

    @Test("source + bundle both declare #applyScrolledContainerAxis")
    func declaresHelper() throws {
        let src = try loadSource(), bundle = try loadBundle()
        #expect(src.contains("#applyScrolledContainerAxis"),
                "paginator.js must declare #applyScrolledContainerAxis (WI-2).")
        #expect(bundle.contains("#applyScrolledContainerAxis"),
                "foliate-bundle.js must declare #applyScrolledContainerAxis — run build-bundle.sh after editing paginator.js.")
    }

    @Test("source + bundle both invoke this.#applyScrolledContainerAxis()")
    func invokesHelper() throws {
        let src = try loadSource(), bundle = try loadBundle()
        #expect(src.contains("this.#applyScrolledContainerAxis()"),
                "paginator.js must call #applyScrolledContainerAxis — declaring without calling is dead code.")
        #expect(bundle.contains("this.#applyScrolledContainerAxis()"),
                "foliate-bundle.js must call #applyScrolledContainerAxis — rebuild the bundle.")
    }

    // MARK: - Helper body: axis-aware orientation

    @Test("helper orients the container by explicit DIRECTION (not row-reverse) for vertical-writing")
    func helperOrientsVerticalWriting() throws {
        let body = extractHelperBody(try loadSource(), name: "#applyScrolledContainerAxis")
        #expect(!body.isEmpty, "could not locate #applyScrolledContainerAxis body")
        #expect(body.contains("'horizontal'") || body.contains("\"horizontal\""),
                "helper must branch on the ScrollModel axis === 'horizontal' (vertical-writing).")
        #expect(body.contains("flexDirection") && body.contains("'row'"),
                "helper must use a plain flex `row` (direction handles the reversal).")
        // Gate-4 High: the host already forces dir=rtl for every vertical book, so
        // `row-reverse` would double-reverse vertical-rl. The helper must instead
        // set an EXPLICIT direction (rtl for vertical-rl, ltr for vertical-lr).
        // Check the string LITERAL (quoted), not prose — the explanatory comment
        // legitimately mentions row-reverse to say why it's avoided.
        #expect(!body.contains("'row-reverse'") && !body.contains("\"row-reverse\""),
                "helper must NOT set flexDirection to row-reverse — the host's blanket dir=rtl would double-reverse vertical-rl.")
        #expect(body.contains("direction") && body.contains("'rtl'") && body.contains("'ltr'"),
                "helper must set container direction explicitly: rtl for directionSign<0 (vertical-rl), ltr otherwise (vertical-lr).")
        #expect(body.contains("directionSign"),
                "helper must pick rtl vs ltr from the ScrollModel directionSign.")
    }

    @Test("helper RESETS display + flex-direction + direction for horizontal-writing (byte-identical to #73)")
    func helperResetsHorizontalWriting() throws {
        // Horizontal-writing must NOT leave any inline style — it removes ALL three
        // so the CSS default (block flow, inherited direction) stays exactly as #73
        // shipped. Assert the exact strings in BOTH source and bundle (Gate-4 Low).
        // esbuild rewrites the source's single quotes to double quotes in the
        // bundle, so assert quote-agnostically.
        func removesProperty(_ body: String, _ prop: String) -> Bool {
            body.contains("removeProperty('\(prop)')") || body.contains("removeProperty(\"\(prop)\")")
        }
        for (label, text) in [("source", try loadSource()), ("bundle", try loadBundle())] {
            let body = extractHelperBody(text, name: "#applyScrolledContainerAxis")
            #expect(!body.isEmpty, "\(label): could not locate #applyScrolledContainerAxis body")
            #expect(removesProperty(body, "display"),
                    "\(label) helper must removeProperty('display') for horizontal-writing.")
            #expect(removesProperty(body, "flex-direction"),
                    "\(label) helper must removeProperty('flex-direction') for horizontal-writing.")
            #expect(removesProperty(body, "direction"),
                    "\(label) helper must removeProperty('direction') for horizontal-writing.")
        }
    }

    // MARK: - Call site runs BEFORE the windowing gate, gated on scrolled only

    @Test("in #display, the layout call runs before #ensureWindow, gated on scrolled only")
    func layoutRunsBeforeWindowingGate() throws {
        let src = try loadSource()
        // Scope the ordering assertion to the #display body specifically (the flow
        // attributeChangedCallback ALSO calls the helper, so a global search would
        // match that first and leave #display's ordering unpinned — Gate-4 r2 Low).
        let display = extractHelperBody(src, name: "#display")
        #expect(!display.isEmpty, "could not locate #display body")
        guard let callRange = display.range(of: "this.#applyScrolledContainerAxis()"),
              let ensureRange = display.range(of: "this.#ensureWindow()", range: callRange.upperBound..<display.endIndex)
        else {
            Issue.record("expected #applyScrolledContainerAxis() before #ensureWindow() inside #display")
            return
        }
        #expect(callRange.lowerBound < ensureRange.lowerBound,
                "WI-2 layout must apply BEFORE the windowing math in #display (it must run for vertical even while #ensureWindow gates it out).")
        // The guard immediately preceding the call is `this.scrolled` (not
        // `#windowedScroll`) — so the container is oriented even in the
        // non-windowed vertical fallback.
        #expect(display.contains("if (this.scrolled) this.#applyScrolledContainerAxis()"),
                "the #display layout call must be gated on `this.scrolled` only (not #windowedScroll), so vertical-writing books orient the container even while windowing is gated out.")
    }

    // MARK: - Helpers (balanced-brace body extractor, mirrors ScrollBoundary tests)

    private func extractHelperBody(_ source: String, name: String) -> String {
        var searchStart = source.startIndex
        while let nameRange = source.range(of: name, range: searchStart..<source.endIndex) {
            let afterName = source[nameRange.upperBound...]
            guard let openParen = afterName.firstIndex(where: { !$0.isWhitespace }),
                  afterName[openParen] == "(" else { searchStart = nameRange.upperBound; continue }
            var pDepth = 0
            var afterParen: String.Index? = nil
            for i in afterName[openParen...].indices {
                let ch = afterName[i]
                if ch == "(" { pDepth += 1 }
                else if ch == ")" { pDepth -= 1; if pDepth == 0 { afterParen = afterName.index(after: i); break } }
            }
            guard let afterClose = afterParen else { searchStart = nameRange.upperBound; continue }
            let tail = afterName[afterClose...]
            guard let braceIdx = tail.firstIndex(where: { !$0.isWhitespace }),
                  tail[braceIdx] == "{" else { searchStart = nameRange.upperBound; continue }
            var depth = 0
            var end: String.Index = braceIdx
            for i in tail[braceIdx...].indices {
                let ch = tail[i]
                if ch == "{" { depth += 1 }
                else if ch == "}" { depth -= 1; if depth == 0 { end = i; break } }
            }
            return String(tail[braceIdx...end])
        }
        return ""
    }

    private final class BundleToken {}
}
