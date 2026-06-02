// Purpose: Feature #76 WI-3 — the windowed continuous-scroll primitives are now
// ScrollModel-axis-aware and the `!this.#vertical` gates are REMOVED, so K=3
// windowing runs for vertical-writing AZW3/MOBI (the Bug #283 chapter-boundary
// jump). horizontal-tb stays byte-identical (directionSign +1 → identical
// expressions). The runtime path is inside a WKWebView, so this file pins the
// static contract in BOTH source `paginator.js` and built `foliate-bundle.js`,
// following the FoliatePaginatorScrollBoundaryTests pattern.
//
// @coordinates-with: vreader/Services/Foliate/JS/paginator.js,
//   vreader/Services/Foliate/JS/foliate-bundle.js, FoliateScrollModelTests.swift

import Testing
import Foundation

@Suite("Foliate paginator — WI-3 vertical windowing gates removed + axis-aware (Feature #76 / Bug #283)")
struct FoliateVerticalWindowBundleTests {

    private func loadBundle() throws -> String {
        for c in [Bundle(for: BundleToken.self), .main] {
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
        return try String(contentsOf: repoRoot.appendingPathComponent("vreader/Services/Foliate/JS/paginator.js"), encoding: .utf8)
    }

    // MARK: - The #ensureWindow vertical gate is REMOVED

    @Test("#ensureWindow no longer early-returns on this.#vertical (windowing runs for vertical-writing)")
    func ensureWindowGateRemoved() throws {
        let body = extractHelperBody(try loadSource(), name: "#ensureWindow")
        #expect(!body.isEmpty, "could not locate #ensureWindow body")
        // The guard must be the windowing-flag + scrolled-mode check, with NO
        // `this.#vertical` term (that gate falling back to per-section swap is gone).
        #expect(body.contains("if (!this.#windowedScroll || !this.scrolled) return"),
                "#ensureWindow guard must be `!#windowedScroll || !scrolled` with no `#vertical` term (WI-3 enables vertical windowing).")
        // First statement of the method must not re-introduce a #vertical early return.
        let firstLine = body.split(separator: "\n").first(where: { $0.contains("return") }) ?? ""
        #expect(!firstLine.contains("#vertical"),
                "#ensureWindow's guard must not gate on #vertical.")
    }

    // MARK: - Windowed scroll uses axis-aware container offset/size (not raw scrollTop/Height)

    @Test("#scrollNext windowed branch uses axis-aware size + offset, not raw scrollHeight/scrollTop/clientHeight")
    func scrollNextAxisAware() throws {
        let body = extractHelperBody(try loadSource(), name: "#scrollNext")
        #expect(body.contains("#axisScrollSize()") && body.contains("#axisClientSize()") && body.contains("#axisScrollOffset()"),
                "#scrollNext windowed remaining-room must use #axisScrollSize/#axisClientSize/#axisScrollOffset.")
        // The windowed branch must NOT be gated on #vertical anymore.
        #expect(!body.contains("this.#windowedScroll && !this.#vertical"),
                "#scrollNext windowed branch must not gate on `!this.#vertical`.")
    }

    @Test("#scrollPrev windowed branch uses #axisScrollOffset, not container.scrollTop")
    func scrollPrevAxisAware() throws {
        let body = extractHelperBody(try loadSource(), name: "#scrollPrev")
        #expect(body.contains("#axisScrollOffset()"),
                "#scrollPrev windowed branch must read #axisScrollOffset (axis-aware).")
        #expect(!body.contains("this.#windowedScroll && !this.#vertical"),
                "#scrollPrev windowed branch must not gate on `!this.#vertical`.")
    }

    // MARK: - The scroll sign is direction-aware (vertical-rl only), fixing the FIXME

    @Test("#scrollTo negates the offset by ScrollModel directionSign, not a blanket this.#vertical")
    func scrollSignUsesDirectionSign() throws {
        let body = extractHelperBody(try loadSource(), name: "#scrollTo")
        #expect(body.contains("this.#activeScrollModel.directionSign < 0"),
                "#scrollTo must negate by directionSign < 0 (vertical-rl only), not the old `this.#vertical` (which wrongly negated vertical-lr).")
        #expect(!body.contains("this.scrolled && this.#vertical) offset = -offset"),
                "the old `this.scrolled && this.#vertical) offset = -offset` (vertical-rl-only FIXME) must be gone.")
    }

    // MARK: - #maybeCrossSectionBoundary windowed branch is no longer #vertical-gated

    @Test("#maybeCrossSectionBoundary windowed swap-free branch runs for vertical too")
    func boundaryWindowedUngated() throws {
        let body = extractHelperBody(try loadSource(), name: "#maybeCrossSectionBoundary")
        #expect(!body.contains("this.#windowedScroll && !this.#vertical"),
                "#maybeCrossSectionBoundary windowed branch must not gate on `!this.#vertical`.")
    }

    // MARK: - The other windowed sites are ungated + axis-aware (Gate-4 r1 Low-2)

    @Test("#viewRelativeStart uses #axisScrollOffset and is no longer #vertical-gated")
    func viewRelativeStartAxisAware() throws {
        let body = extractHelperBody(try loadSource(), name: "#viewRelativeStart")
        #expect(body.contains("#axisScrollOffset()"),
                "#viewRelativeStart must read #axisScrollOffset (not container.scrollTop).")
        #expect(!body.contains("|| this.#vertical"),
                "#viewRelativeStart must not gate on #vertical.")
    }

    @Test("#scrollToRect, #scrollToAnchor, #afterScroll windowed offset-adds are no longer #vertical-gated")
    func windowedOffsetAddsUngated() throws {
        let src = try loadSource()
        for name in ["#scrollToRect", "#scrollToAnchor", "#afterScroll"] {
            let body = extractHelperBody(src, name: name)
            #expect(!body.isEmpty, "could not locate \(name) body")
            #expect(!body.contains("&& !this.#vertical"),
                    "\(name) windowed branch must not gate on `!this.#vertical` (WI-3 enables vertical).")
        }
    }

    // MARK: - vertical-rl logical start uses the RIGHT edge (Gate-4 r1 High)

    @Test("scrollModelFor vertical-rl uses rectStartProp 'right' in source + bundle")
    func verticalRLRightEdge() throws {
        for (label, text) in [("source", try loadSource()), ("bundle", try loadBundle())] {
            // The vertical-rl model entry must carry rectStartProp 'right' (the
            // reading-order start under WebKit's negative scrollLeft).
            #expect(text.contains("rectStartProp: 'right'") || text.contains("rectStartProp: \"right\""),
                    "\(label) scrollModelFor vertical-rl must use rectStartProp 'right' (WI-3 High).")
        }
    }

    @Test("#getRectMapper scrolled vertical branch is direction-aware (directionSign, not blanket #vertical)")
    func rectMapperDirectionAware() throws {
        let body = extractHelperBody(try loadSource(), name: "#getRectMapper")
        #expect(body.contains("directionSign < 0"),
                "#getRectMapper scrolled-vertical must branch on directionSign (vertical-rl mirrors, vertical-lr does not) — Gate-4 Medium.")
    }

    // MARK: - source↔bundle parity for the new axis helpers

    @Test("source + bundle both declare the axis container-size helpers")
    func axisHelpersInBundle() throws {
        for (label, text) in [("source", try loadSource()), ("bundle", try loadBundle())] {
            #expect(text.contains("#axisScrollSize"), "\(label) must declare #axisScrollSize (rebuild bundle if missing).")
            #expect(text.contains("#axisClientSize"), "\(label) must declare #axisClientSize.")
        }
    }

    @Test("bundle has the directionSign-based scroll sign (rebuilt from source)")
    func bundleHasDirectionSign() throws {
        let bundle = try loadBundle()
        #expect(bundle.contains("directionSign < 0"),
                "foliate-bundle.js must carry the directionSign-based scroll sign — run build-bundle.sh.")
    }

    // MARK: - Helpers (balanced-brace extractor, mirrors ScrollBoundary tests)

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
