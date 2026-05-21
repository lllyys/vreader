// Purpose: regression guard for Bug #108 REOPEN (GH #224) — AZW3/MOBI Foliate
// center tap must toggle chrome, not turn the page. The Bug #239 fix
// (bd7564c7) made foliate-host.js's content-tap handler post `{x, w}` so
// paged-mode side taps could route through `ReaderTapZoneRouter`. But the
// handler measured `x` as `event.clientX` (the click's coordinate INSIDE the
// section's iframe, which foliate-js renders as a 2-column-wide page shifted
// horizontally to show one column) while reporting `w` as
// `documentElement.clientWidth` (a SINGLE column's width). The two are in
// different coordinate spaces, so on every page whose visible column is the
// right column of the spread, `ReaderTapZoneRouter` saw `x/w > 2/3` and
// classified a center tap as a right-zone tap → `.readerNextPage` instead of
// `.readerContentTapped`. Center tap turned the page (or no-oped at the right
// edge) and never toggled the toolbar.
//
// Device confirmation (iPhone 17 Pro Simulator, AZW3 mini fixture, paginated
// default): the section iframe was 748px wide at `left: -359` over a 402px
// host viewport; a screen-center tap produced `clientX ≈ 560`, and the buggy
// `560 / 374 = 1.50` classified as `right`. The fix maps the click back to the
// host viewport: `hostX = clientX + frameElement.getBoundingClientRect().left`
// (`560 + (-359) = 201`) against the host width 402 → `201 / 402 = 0.50` →
// `center` → toggle. EPUB is unaffected because it renders in the top-level
// document (no nested iframe), so its `clientX`/`clientWidth` are already in
// the same coordinate space.
//
// The mapping runs inside the Foliate WKWebView, so the runtime path is not
// unit-testable directly. This file pins the static contract on BOTH the
// source `foliate-host.js` and the built `foliate-bundle.js` (the file the
// AZW3/MOBI reader actually loads): the content-tap handler must derive its
// posted x/w from the host viewport via the section's `frameElement`, not from
// the iframe-internal `clientX` / `documentElement.clientWidth`.
//
// Pattern: source-text regression guard — same shape as
// FoliatePaginatorScrollBoundaryTests (Bug #235).
//
// @coordinates-with: vreader/Services/Foliate/JS/foliate-host.js,
//   vreader/Services/Foliate/JS/foliate-bundle.js,
//   vreader/Views/Reader/ReaderTapZoneRouter.swift,
//   vreader/Views/Reader/FoliateSpikeView.swift

import Testing
import Foundation
@testable import vreader

@Suite("Foliate host tap coordinate mapping (Bug #108 REOPEN / GH #224)")
struct FoliateHostTapCoordinateTests {

    private enum BundleLoadError: Error { case notFound(String) }
    private final class BundleToken {}

    /// Built bundle the AZW3/MOBI reader actually loads.
    private func loadFoliateBundle() throws -> String {
        let candidates: [Bundle] = [Bundle(for: BundleToken.self), .main]
        for candidate in candidates {
            if let url = candidate.url(forResource: "foliate-bundle", withExtension: "js") {
                return try String(contentsOf: url, encoding: .utf8)
            }
        }
        throw BundleLoadError.notFound("foliate-bundle.js")
    }

    /// Source-of-truth host file (lives in the repo, not the runtime bundle).
    private func loadFoliateHostSource() throws -> String {
        // #filePath: .../vreaderTests/Services/Foliate/FoliateHostTapCoordinateTests.swift
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // Foliate
            .deletingLastPathComponent()  // Services
            .deletingLastPathComponent()  // vreaderTests
            .deletingLastPathComponent()  // repo root
        let hostURL = repoRoot
            .appendingPathComponent("vreader/Services/Foliate/JS/foliate-host.js")
        guard FileManager.default.fileExists(atPath: hostURL.path) else {
            throw BundleLoadError.notFound(hostURL.path)
        }
        return try String(contentsOf: hostURL, encoding: .utf8)
    }

    /// Extracts the content-tap coordinate-mapping region so the assertions
    /// are scoped to the right code (the tap handler + its
    /// `mapTapToHostViewport` helper) rather than matching `frameElement` /
    /// `getBoundingClientRect` anywhere in the 300KB bundle (foliate-js itself
    /// calls `getBoundingClientRect` in dozens of unrelated places).
    ///
    /// The fix (Bug #108 REOPEN) introduces the `mapTapToHostViewport`
    /// function, which is unique to vreader's host shim and sits immediately
    /// after the click handler. We anchor on that function name and take a
    /// window spanning its full body — this proves both that the helper exists
    /// AND that it does the host-viewport coordinate math. If the regression
    /// returns (handler reverts to raw `clientX` / `clientWidth`), the helper
    /// disappears and the anchor falls back to the whole source, where the
    /// `parent`/`ownerDocument`/`frameElement` host-mapping tokens are absent
    /// from the tap path.
    private func tapHandlerRegion(_ source: String) -> String {
        // Anchor on the helper's DEFINITION (`function mapTapToHostViewport`),
        // not its call site — the source separates the call from the
        // definition by a long comment block, so anchoring on the definition
        // guarantees the window covers the body where the host-mapping math
        // lives. The bundle minifies `function mapTapToHostViewport(...)` too,
        // so the same anchor works for both.
        let defAnchors = ["function mapTapToHostViewport", "mapTapToHostViewport(doc, clientX)"]
        var defRange: Range<String.Index>?
        for anchor in defAnchors {
            if let r = source.range(of: anchor) { defRange = r; break }
        }
        guard let fnDef = defRange else {
            // Helper absent → return the click-handler vicinity so the
            // assertions still fail loudly (they look for host-mapping
            // executable patterns the pre-fix handler never had).
            if let postRange = source.range(of: "post(\"tap\"")
                ?? source.range(of: "post('tap'") {
                let lo = source.index(postRange.lowerBound, offsetBy: -400,
                                      limitedBy: source.startIndex) ?? source.startIndex
                let hi = source.index(postRange.upperBound, offsetBy: 200,
                                      limitedBy: source.endIndex) ?? source.endIndex
                return stripComments(String(source[lo..<hi]))
            }
            return stripComments(source)
        }
        // Window covers the helper's full body (the host-mapping math). The
        // source body + the leading comment-free code spans ~1.4KB; the bundle
        // is tighter. 1600 chars covers both through the `return { x: clientX
        // + frameLeft, w: hostW }` line.
        let lower = source.index(fnDef.lowerBound, offsetBy: 0,
                                 limitedBy: source.startIndex) ?? source.startIndex
        let upper = source.index(fnDef.lowerBound, offsetBy: 1600,
                                 limitedBy: source.endIndex) ?? source.endIndex
        // Strip comments so a token in an explanatory comment can never satisfy
        // an assertion — every match must be in EXECUTABLE code (Codex audit
        // round-1 Low: a string-token check that includes comments could pass
        // even if the executable code regressed while the comment still
        // mentioned the token).
        return stripComments(String(source[lower..<upper]))
    }

    /// Removes `// line` and `/* block */` comments so assertions match only
    /// executable JS. The string-literal cases in this handler region never
    /// contain `//` or `/* */`, so a naive strip is safe here.
    private func stripComments(_ s: String) -> String {
        var out = s
        // Block comments first.
        while let start = out.range(of: "/*"),
              let end = out.range(of: "*/", range: start.upperBound..<out.endIndex) {
            out.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // Line comments: drop from `//` to end of line.
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            if let r = line.range(of: "//") { return line[line.startIndex..<r.lowerBound] }
            return line
        }
        return lines.joined(separator: "\n")
    }

    /// Normalizes whitespace so an executable expression can be matched
    /// regardless of esbuild's spacing / line wrapping (`clientX + frameLeft`
    /// in source vs `clientX + frameLeft` / `clientX+frameLeft` in the bundle).
    private func collapseSpaces(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    // MARK: - Source foliate-host.js maps to host viewport coordinates

    @Test("Source foliate-host.js offsets clientX by the section frame rect to reach host coords")
    func sourceMapsTapToHostViewport() throws {
        let region = tapHandlerRegion(try loadFoliateHostSource())
        #expect(region.contains("frameElement"),
                "foliate-host.js's tap-mapping helper must read `doc.defaultView.frameElement` to reach the section iframe (Bug #108 REOPEN). Without it, paged-mode center taps on right-column pages misclassify as right-zone next-page.")
        #expect(region.contains("getBoundingClientRect"),
                "foliate-host.js's tap-mapping helper must read the section frame's getBoundingClientRect().left as the column shift.")
        // The actual transform — executable, not a comment token: the posted x
        // must be `clientX + frameLeft` (offset the iframe-internal clientX by
        // the frame's signed left). Whitespace-collapsed so spacing can't break
        // the match.
        #expect(collapseSpaces(region).contains("clientX+frameLeft"),
                "foliate-host.js must compute the host-viewport x as `clientX + frameLeft` — the executable transform, not just a comment mentioning it. Reverting to raw event.clientX reintroduces Bug #108.")
    }

    @Test("Source foliate-host.js takes width from the host window, not the iframe column")
    func sourceUsesHostViewportWidth() throws {
        let region = tapHandlerRegion(try loadFoliateHostSource())
        // The width must come from the frame's OWNING window
        // (`frameEl.ownerDocument.defaultView.innerWidth`), not the iframe's
        // own documentElement.clientWidth (a single column — the buggy value).
        #expect(region.contains("ownerDocument"),
                "foliate-host.js's tap-mapping helper must reach the host window via `frameEl.ownerDocument` for the tap-zone width.")
        #expect(collapseSpaces(region).contains("ownerDocument&&frameEl.ownerDocument.defaultView")
                || collapseSpaces(region).contains("ownerDocument.defaultView"),
                "foliate-host.js must read the HOST window (frameEl.ownerDocument.defaultView) — its innerWidth is the on-screen width. The iframe column width was the buggy `w`.")
        #expect(region.contains("innerWidth"),
                "foliate-host.js must use the host window innerWidth for the tap-zone width.")
    }

    @Test("Source foliate-host.js no longer posts raw event.clientX with documentElement.clientWidth")
    func sourceTapHandlerDoesNotPostRawClientCoords() throws {
        // Scope to the click-handler region (the `view.addEventListener('load'`
        // block that calls post('tap', ...)). The regressing shape posted
        // `{ x: x, w: w }` where `w = doc.documentElement.clientWidth`. The
        // fixed handler posts `{ x: mapped.x, w: mapped.w }`.
        let source = try loadFoliateHostSource()
        guard let postIdx = source.range(of: "post('tap', { x")
            ?? source.range(of: "post(\"tap\", { x") else {
            // No coordinate-bearing tap post at all — acceptable (bare tap
            // only), the bug can't manifest.
            return
        }
        // Extend the window PAST the post call so the `{ x: mapped.x, w:
        // mapped.w }` argument is inside the region.
        let lo = source.index(postIdx.lowerBound, offsetBy: -300,
                              limitedBy: source.startIndex) ?? source.startIndex
        let hi = source.index(postIdx.upperBound, offsetBy: 120,
                              limitedBy: source.endIndex) ?? source.endIndex
        let region = stripComments(String(source[lo..<hi]))
        #expect(region.contains("mapped.x") && region.contains("mapped.w"),
                "foliate-host.js's coordinate-bearing tap post must use the host-mapped `{ x: mapped.x, w: mapped.w }`, not the raw iframe `{ x: x, w: w }` (Bug #108 regression shape).")
    }

    // MARK: - Built bundle stays in sync (must be rebuilt after editing source)

    @Test("Built foliate-bundle.js offsets clientX by the section frame rect")
    func bundleMapsTapToHostViewport() throws {
        let region = tapHandlerRegion(try loadFoliateBundle())
        #expect(region.contains("frameElement"),
                "foliate-bundle.js's tap-mapping helper must read the section frameElement (Bug #108 REOPEN). If you edited foliate-host.js, run vreader/Services/Foliate/JS/build-bundle.sh and commit the rebuilt bundle.")
        #expect(region.contains("getBoundingClientRect"),
                "foliate-bundle.js's tap-mapping helper must read the frame's getBoundingClientRect().left. Rebuild the bundle from foliate-host.js if this fails.")
        #expect(collapseSpaces(region).contains("clientX+frameLeft"),
                "foliate-bundle.js must compute `clientX + frameLeft`. Rebuild the bundle from foliate-host.js if this fails.")
    }

    @Test("Built foliate-bundle.js takes width from the host window")
    func bundleUsesHostViewportWidth() throws {
        let region = tapHandlerRegion(try loadFoliateBundle())
        #expect(region.contains("ownerDocument"),
                "foliate-bundle.js's tap-mapping helper must reach the host window via ownerDocument. Rebuild from foliate-host.js if this fails.")
        #expect(region.contains("innerWidth"),
                "foliate-bundle.js must use the host window innerWidth for the tap-zone width. Rebuild from foliate-host.js if this fails.")
    }
}
