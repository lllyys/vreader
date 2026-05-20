// Purpose: regression guard for Bug #235 (GH #983) — AZW3/MOBI Foliate
// paginator must auto-advance to the next/prev section when the user scrolls
// past the current section's boundary in scrolled mode, so reading flow is
// continuous across chapter boundaries (TXT analog of bug #180, EPUB analog
// of bug #165).
//
// The behavior lives in Foliate-js paginator code that runs inside a
// WKWebView, so the runtime path is not unit-testable directly. This file
// pins the static contract: the built `foliate-bundle.js` (the file actually
// loaded by the AZW3/MOBI reader's WebView) and the source `paginator.js`
// (rebuilt-from source-of-truth) BOTH contain the boundary-detect helper and
// its call site. If either drops out, this test fails and prompts the agent
// to rebuild the bundle or restore the source.
//
// @coordinates-with: vreader/Services/Foliate/JS/paginator.js,
// vreader/Services/Foliate/JS/foliate-bundle.js
//
// Pattern: source-text regression guard. Same shape that
// FoliateStyleMapperChapterStartTests uses to pin JS-side invariants the
// Swift layer cannot interrogate directly.

import Testing
import Foundation

@Suite("Foliate paginator — scroll-mode cross-chapter continuity (Bug #235)")
struct FoliatePaginatorScrollBoundaryTests {

    /// Built bundle that the AZW3/MOBI reader actually loads. Lives in the
    /// app's main resource bundle.
    private func loadFoliateBundle() throws -> String {
        let bundle = Bundle(for: BundleToken.self)
        // Test runs inside the test bundle; the host app's resources are
        // copied into the test bundle's path the same way other Foliate
        // tests find them. Try both the test bundle and Bundle.main.
        let candidates: [Bundle] = [bundle, .main]
        for candidate in candidates {
            if let url = candidate.url(forResource: "foliate-bundle", withExtension: "js") {
                return try String(contentsOf: url, encoding: .utf8)
            }
        }
        throw BundleLoadError.notFound("foliate-bundle.js")
    }

    /// Source-of-truth paginator file. Lives in the repo, NOT in the runtime
    /// bundle. We walk up from the test source location (`#file`) to find it.
    private func loadPaginatorSource() throws -> String {
        // #file resolves to .../vreaderTests/Services/Foliate/FoliatePaginatorScrollBoundaryTests.swift
        // Source: .../vreader/Services/Foliate/JS/paginator.js
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // Foliate
            .deletingLastPathComponent()  // Services
            .deletingLastPathComponent()  // vreaderTests
            .deletingLastPathComponent()  // repo root
        let paginatorURL = repoRoot
            .appendingPathComponent("vreader/Services/Foliate/JS/paginator.js")
        guard FileManager.default.fileExists(atPath: paginatorURL.path) else {
            throw BundleLoadError.notFound(paginatorURL.path)
        }
        return try String(contentsOf: paginatorURL, encoding: .utf8)
    }

    // MARK: - Built bundle contains the boundary-detect helper

    @Test("Built foliate-bundle.js declares the maybeCrossSectionBoundary helper")
    func bundleDeclaresBoundaryHelper() throws {
        let text = try loadFoliateBundle()
        #expect(text.contains("#maybeCrossSectionBoundary"),
                "foliate-bundle.js must declare #maybeCrossSectionBoundary so the scrolled-mode reader can auto-advance across section boundaries (Bug #235). If you edited paginator.js, run vreader/Services/Foliate/JS/build-bundle.sh and commit the rebuilt bundle.")
    }

    @Test("Built foliate-bundle.js invokes maybeCrossSectionBoundary from afterScroll")
    func bundleInvokesBoundaryHelperFromScrollListener() throws {
        let text = try loadFoliateBundle()
        // The call site lives inside the scrolled-mode scroll listener
        // (after #afterScroll fires for reason='scroll'). The helper must
        // be wired in or the user never crosses a section boundary by
        // scrolling.
        #expect(text.contains("this.#maybeCrossSectionBoundary()"),
                "foliate-bundle.js must invoke #maybeCrossSectionBoundary() — declaring it without calling it is dead code and reintroduces Bug #235.")
    }

    // MARK: - Source paginator.js stays in sync with the bundle

    @Test("Source paginator.js declares the maybeCrossSectionBoundary helper")
    func sourceDeclaresBoundaryHelper() throws {
        let text = try loadPaginatorSource()
        #expect(text.contains("#maybeCrossSectionBoundary"),
                "paginator.js (source of truth) must declare #maybeCrossSectionBoundary. The bundle is generated from this file — if it disagrees, build-bundle.sh would re-introduce Bug #235 on the next rebuild.")
    }

    @Test("Source paginator.js invokes maybeCrossSectionBoundary from afterScroll")
    func sourceInvokesBoundaryHelperFromScrollListener() throws {
        let text = try loadPaginatorSource()
        #expect(text.contains("this.#maybeCrossSectionBoundary()"),
                "paginator.js (source of truth) must invoke #maybeCrossSectionBoundary() — declaring it without calling it would reintroduce Bug #235 on the next bundle rebuild.")
    }

    // MARK: - Helper behavior: gates on scrolled mode + adjacent section

    @Test("Helper gates on scrolled mode (no-op in paginated mode)")
    func helperGatesOnScrolledMode() throws {
        let text = try loadPaginatorSource()
        // The helper should only act in scrolled mode (paged mode already
        // has cross-section advancement via #scrollNext / #scrollPrev's
        // page-bound exhaustion path through next() / prev()). Guard
        // against paged-mode firing is a `this.scrolled` check.
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        #expect(helperBody.contains("this.scrolled"),
                "Boundary helper must check this.scrolled; otherwise paged mode would double-advance.")
    }

    @Test("Helper consults adjacentIndex before crossing")
    func helperConsultsAdjacentIndex() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        #expect(helperBody.contains("#adjacentIndex"),
                "Boundary helper must check #adjacentIndex(dir) before crossing — otherwise it would attempt to load a non-existent section past the first/last chapter.")
    }

    @Test("Helper respects the #locked re-entrancy guard")
    func helperRespectsLockedGuard() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        #expect(helperBody.contains("#locked"),
                "Boundary helper must read #locked so it doesn't fire while a section transition is already in progress (would double-advance / drop user position).")
    }

    // MARK: - Direction-specific edge logic (Codex audit round-1 hardening)

    @Test("Helper crosses forward by calling #turnPage(1) on atEnd")
    func helperForwardCrossesWithTurnPagePositiveOne() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        #expect(helperBody.contains("#turnPage(1)"),
                "Forward edge crossing must call #turnPage(1) (the same path next() uses). Calling nextSection() directly bypasses #turnPage's #locked re-entrancy guard.")
    }

    @Test("Helper crosses backward by calling #turnPage(-1) on atStart")
    func helperBackwardCrossesWithTurnPageNegativeOne() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        #expect(helperBody.contains("#turnPage(-1)"),
                "Backward edge crossing must call #turnPage(-1) (the same path prev() uses). Calling prevSection() directly bypasses #turnPage's #locked re-entrancy guard.")
    }

    @Test("Helper edge math uses viewSize/end and start (not pages/page)")
    func helperEdgeMathUsesScrolledModeAccessors() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        // Paged mode uses page/pages; scrolled mode uses start/end/viewSize.
        // The helper is scrolled-mode-only — verify it uses the right
        // accessors so future refactors don't silently break the math.
        #expect(helperBody.contains("this.viewSize") && helperBody.contains("this.end"),
                "atEnd must compare this.viewSize to this.end (scrolled-mode accessors).")
        #expect(helperBody.contains("this.start"),
                "atStart must read this.start (scrolled-mode accessor).")
    }

    @Test("Helper checks #adjacentIndex in both directions")
    func helperChecksAdjacentBothDirections() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        #expect(helperBody.contains("#adjacentIndex(1)"),
                "Forward edge must guard on #adjacentIndex(1) — otherwise the user crashes past the last chapter.")
        #expect(helperBody.contains("#adjacentIndex(-1)"),
                "Backward edge must guard on #adjacentIndex(-1) — otherwise the user crashes past the first chapter.")
    }

    // MARK: - Listener wiring (Codex audit round-1 hardening)

    @Test("Source paginator.js wires helper into IMMEDIATE scroll listener, not debounced")
    func sourceWiresHelperIntoImmediateListener() throws {
        let text = try loadPaginatorSource()
        // Continuous scroll requires the boundary detect to fire while
        // the user is still flinging — NOT 250ms after the gesture has
        // already stopped. The Codex audit (thread 019e4407) round 1
        // flagged the debounced-only wiring as a Medium finding
        // ("jump-after-stop"). Pin the immediate wiring here so a
        // future cleanup pass doesn't accidentally collapse the two
        // listeners back together.
        //
        // The immediate listener is the FIRST scroll registration on
        // #container; the debounced one is the second. Find the first
        // .addEventListener('scroll' that does NOT pass `debounce(`.
        guard let firstScroll = text.range(of: "addEventListener('scroll'") else {
            Issue.record("paginator.js must have at least one scroll listener")
            return
        }
        // Scan from the first scroll listener up to the next
        // `.addEventListener(` call so the window grows naturally with
        // however much explanatory comment lives inside the first
        // listener's callback. The window stops at the SECOND scroll
        // registration (the debounced one), so we never falsely match
        // the helper call from the debounced block.
        let afterFirst = text[firstScroll.upperBound...]
        let nextListener = afterFirst.range(of: ".addEventListener(") ?? afterFirst.range(of: "addEventListener(")
        let scanEnd = nextListener?.lowerBound ?? text.endIndex
        let firstBlock = String(text[firstScroll.upperBound..<scanEnd])
        #expect(firstBlock.contains("this.#maybeCrossSectionBoundary()"),
                "The IMMEDIATE scroll listener (not the 250ms-debounced one) must invoke the boundary helper, so cross-chapter advance happens during the fling rather than a quarter-second after it stops.")
        #expect(!firstBlock.contains("debounce("),
                "The immediate scroll listener block must not be the debounced one; check the test's scan window.")
    }

    @Test("Built bundle wires helper into IMMEDIATE scroll listener, not debounced")
    func bundleWiresHelperIntoImmediateListener() throws {
        let text = try loadFoliateBundle()
        guard let firstScroll = text.range(of: "addEventListener(\"scroll\"") else {
            Issue.record("foliate-bundle.js must have at least one scroll listener")
            return
        }
        let afterFirst = text[firstScroll.upperBound...]
        let nextListener = afterFirst.range(of: ".addEventListener(") ?? afterFirst.range(of: "addEventListener(")
        let scanEnd = nextListener?.lowerBound ?? text.endIndex
        let firstBlock = String(text[firstScroll.upperBound..<scanEnd])
        #expect(firstBlock.contains("this.#maybeCrossSectionBoundary()"),
                "Built bundle's IMMEDIATE scroll listener must invoke the boundary helper. If you edited paginator.js but didn't rebuild the bundle, this test fires — run vreader/Services/Foliate/JS/build-bundle.sh.")
    }

    // MARK: - Epsilon symmetry with upstream Foliate (audit round-1)

    @Test("atEnd epsilon matches #scrollNext's 2px threshold")
    func atEndEpsilonMatchesScrollNext() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        // #scrollNext checks `this.viewSize - this.end > 2` to determine
        // there's still scroll room in this section. Our atEnd should be
        // the negation: "viewSize - end <= 2". Asserting the literal
        // expression prevents a future tweak from introducing a wider
        // (premature) auto-advance.
        #expect(helperBody.contains("this.viewSize - this.end <= 2"),
                "atEnd must use the same 2px epsilon as #scrollNext — `this.viewSize - this.end <= 2`. A wider threshold would advance sections before the user actually reaches the bottom.")
    }

    @Test("atStart epsilon matches #scrollPrev's 0px threshold")
    func atStartEpsilonMatchesScrollPrev() throws {
        let text = try loadPaginatorSource()
        let helperBody = extractHelperBody(text, name: "#maybeCrossSectionBoundary")
        // #scrollPrev checks `this.start > 0` — no epsilon, because
        // native scroll clamps start to >= 0. Match it exactly: a
        // loose `start <= 2` could fire when the user simply stopped
        // a few pixels below the top.
        #expect(helperBody.contains("this.start <= 0"),
                "atStart must use the same 0px threshold as #scrollPrev — `this.start <= 0`. A wider threshold would auto-advance backward when the user merely stopped scrolling near the top.")
    }

    // MARK: - Helpers

    /// Locate a private method's body by its declaration signature
    /// (`#name() {` — declaration, NOT a call site like `this.#name()`).
    /// Walks balanced braces forward from the opening `{` to find the
    /// method body's closing `}`. Returns the body text between them.
    private func extractHelperBody(_ source: String, name: String) -> String {
        // The declaration is `<name>() {` at indented-method position.
        // A call site has the form `this.<name>()` or `else <name>()`;
        // distinguish by requiring the next non-whitespace char after
        // `()` to be `{`. Search across the source for that pattern.
        var searchStart = source.startIndex
        while let nameRange = source.range(of: name, range: searchStart..<source.endIndex) {
            let afterName = source[nameRange.upperBound...]
            // Expect `(` immediately, then balanced `)`, then `{`.
            guard let openParen = afterName.firstIndex(where: { !$0.isWhitespace }),
                  afterName[openParen] == "(" else {
                searchStart = nameRange.upperBound
                continue
            }
            // Walk past matching `)`.
            var pDepth = 0
            var afterParen: String.Index? = nil
            for i in afterName[openParen...].indices {
                let ch = afterName[i]
                if ch == "(" { pDepth += 1 }
                else if ch == ")" {
                    pDepth -= 1
                    if pDepth == 0 {
                        afterParen = afterName.index(after: i)
                        break
                    }
                }
            }
            guard let afterClose = afterParen else {
                searchStart = nameRange.upperBound
                continue
            }
            // Skip whitespace; if next non-ws is `{`, this is a method body.
            let tail = afterName[afterClose...]
            guard let braceIdx = tail.firstIndex(where: { !$0.isWhitespace }),
                  tail[braceIdx] == "{" else {
                searchStart = nameRange.upperBound
                continue
            }
            // Walk balanced braces from braceIdx to find closing `}`.
            var depth = 0
            var end: String.Index = braceIdx
            for i in tail[braceIdx...].indices {
                let ch = tail[i]
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { end = i; break }
                }
            }
            return String(tail[braceIdx...end])
        }
        return ""
    }

    private final class BundleToken {}

    private enum BundleLoadError: Error, CustomStringConvertible {
        case notFound(String)
        var description: String {
            switch self {
            case .notFound(let name): return "Resource not found: \(name)"
            }
        }
    }
}
