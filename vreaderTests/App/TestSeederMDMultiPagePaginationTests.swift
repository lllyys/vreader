// Purpose: Load-bearing pagination assertion for Feature #45 WI-5's MD
// multi-page fixture. Verifies that the generated content paginates to ≥2
// pages on iPhone 17 Pro Simulator at 18pt — using the EXACT pipeline
// production uses for MD paged-mode reading.
//
// Why a separate file from TestSeederMDMultiPageTests: byte-count and
// chapter-shape checks are cheap and don't need the MD render pipeline; the
// pagination check requires running `MDAttributedStringRenderer.render` and
// then `NativeTextPaginator.paginateAttributed`, mirroring
// `TextReaderUIState.updatePagination(...)` at production line 91.
// Splitting keeps each suite focused on one assertion class.

import Testing
import Foundation
@testable import vreader

#if DEBUG
#if canImport(UIKit)
import UIKit

@Suite("TestSeeder MD multi-page pagination")
struct TestSeederMDMultiPagePaginationTests {

    /// Sanity: the MD renderer produces a non-empty attributed string with
    /// the chapter structure intact. Catches regressions in either the
    /// fixture or `MDAttributedStringRenderer` that would silently break
    /// the load-bearing pagination assertion below.
    @Test @MainActor
    func generatedFixtureRendersToAttributedTextWithChapterHeadings() {
        let doc = MDAttributedStringRenderer.render(
            text: TestSeeder.generateMDMultiPage(),
            config: MDRenderConfig(fontSize: 18)
        )
        #expect(doc.renderedAttributedString.length > 0)
        #expect(doc.headings.count >= 5,
                "expected >=5 detected headings, got \(doc.headings.count)")
    }

    /// Load-bearing assertion. Runs the FULL production pagination pipeline
    /// (render Markdown → paginate the rendered NSAttributedString against
    /// the main screen size) and asserts the fixture spans ≥2 pages.
    ///
    /// Mirrors `TextReaderUIState.swift:91` (`nav.paginateAttributed(
    /// attributedText: attrStr, viewportSize: UIScreen.main.bounds.size)`).
    ///
    /// `UIScreen.main.bounds.size` resolves to the test simulator's logical
    /// size (393×852 on iPhone 17 Pro Sim, the documented project default
    /// per `AGENTS.md` / `.claude/rules/10-tdd.md`). If a future contributor
    /// runs this test on a smaller simulator and the page count drops below
    /// 2, the test fails RED with a clear actionable signal: bump the
    /// generated content size in `TestSeeder.generateMDMultiPage`.
    @Test @MainActor
    func renderedFixturePaginatesToAtLeastTwoPagesOnMainScreenAt18pt() {
        let doc = MDAttributedStringRenderer.render(
            text: TestSeeder.generateMDMultiPage(),
            config: MDRenderConfig(fontSize: 18)
        )
        let paginator = NativeTextPaginator()
        _ = paginator.paginateAttributed(
            attributedText: doc.renderedAttributedString,
            viewportSize: UIScreen.main.bounds.size
        )
        #expect(paginator.totalPages >= 2,
                "expected >=2 pages at 18pt on \(UIScreen.main.bounds.size), got \(paginator.totalPages)")
    }
}

#endif // canImport(UIKit)
#endif // DEBUG
