// Purpose: Tests for EPUBContinuousScrollJS — the pure JS-string generators
// that drive the continuous-scroll multi-chapter WKWebView document
// (feature #71, WI-3). No WKWebView here; the test focus is (1) injection
// escaping (every interpolated value routes through FoliateJSEscaper so a
// chapter body / title / search quote cannot break out of its single-quoted
// JS literal), (2) the prepend scroll-compensation transaction, and (3) that
// section-scoped operations target the right `data-vreader-spine-index`
// subtree rather than the whole document.
//
// Quoting convention (matches EPUBBilingualJS): HTML attributes + CSS
// selectors use double quotes; the JS string literals that carry them use
// single quotes, so a double quote sits inertly inside a `'...'` literal and
// `FoliateJSEscaper.escapeForJSString` only has to neutralize `'`, `\`,
// newlines, U+2028/U+2029.
//
// @coordinates-with: EPUBContinuousScrollJS.swift, EPUBChapterBodyRewriter.swift
//   (EPUBChapterBody), FoliateJSEscaper.swift,
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-3)

import Testing
@testable import vreader

@Suite("EPUBContinuousScrollJS")
struct EPUBContinuousScrollJSTests {

    private func body(
        spineIndex: Int = 3,
        href: String = "OEBPS/text/c3.xhtml",
        bodyHTML: String = "<p>hello</p>",
        scopedStyle: String = #"<style>[data-vreader-spine-index="3"] p{color:red}</style>"#
    ) -> EPUBChapterBody {
        EPUBChapterBody(spineIndex: spineIndex, href: href, bodyHTML: bodyHTML, scopedStyleHTML: scopedStyle)
    }

    // MARK: - bootstrap

    @Test("bootstrap document has a scroll root + injects the theme CSS")
    func bootstrapDocument() {
        let html = EPUBContinuousScrollJS.bootstrapDocumentHTML(themeCSS: "body{background:#111}")
        #expect(html.contains("vreader-scroll-root"))
        #expect(html.contains("body{background:#111}"))
        #expect(html.lowercased().contains("overflow"))
    }

    // MARK: - append / prepend section markup + identity

    @Test("appendChapterSectionJS carries the section's spine index + href data attributes")
    func appendCarriesIdentity() {
        let js = EPUBContinuousScrollJS.appendChapterSectionJS(body(), dividerTitle: nil)
        #expect(js.contains("data-vreader-spine-index=\"3\""))
        #expect(js.contains("data-vreader-href=\"OEBPS/text/c3.xhtml\""))
        #expect(js.contains("hello"))
        #expect(js.contains("vreader-scroll-root"))
    }

    @Test("appendChapterSectionJS escapes the body's single-quote + U+2028 (single-quoted literal)")
    func appendEscapesBody() {
        let js = EPUBContinuousScrollJS.appendChapterSectionJS(
            body(bodyHTML: "<p>it's a \u{2028} line</p>"), dividerTitle: nil)
        #expect(js.contains(#"it\'s"#))       // single quote escaped
        #expect(js.contains(#"\u2028"#))       // line separator escaped
    }

    @Test("appendChapterSectionJS escapes a backslash in the body (no literal breakout)")
    func appendEscapesBackslash() {
        let js = EPUBContinuousScrollJS.appendChapterSectionJS(
            body(bodyHTML: #"<p>a\b</p>"#), dividerTitle: nil)
        #expect(js.contains(#"a\\b"#))
    }

    @Test("divider title is HTML-escaped then JS-escaped")
    func dividerTitleEscaped() {
        let js = EPUBContinuousScrollJS.appendChapterSectionJS(
            body(), dividerTitle: "Ch <1> & x")
        // HTML-escaped so the title can't inject markup into the divider
        #expect(js.contains("Ch &lt;1&gt; &amp; x"))
        #expect(!js.contains("Ch <1>"))
    }

    @Test("no divider element when dividerTitle is nil; present when supplied")
    func dividerPresence() {
        let withTitle = EPUBContinuousScrollJS.appendChapterSectionJS(body(), dividerTitle: "Chapter 4")
        let without = EPUBContinuousScrollJS.appendChapterSectionJS(body(), dividerTitle: nil)
        #expect(withTitle.contains("vreader-chapter-divider"))
        #expect(withTitle.contains("Chapter 4"))
        #expect(!without.contains("vreader-chapter-divider"))
    }

    // MARK: - prepend scroll-compensation

    @Test("prependChapterSectionJS captures scrollHeight before and restores scrollTop after")
    func prependScrollCompensation() {
        let js = EPUBContinuousScrollJS.prependChapterSectionJS(body(), dividerTitle: "Chapter 2")
        #expect(js.contains("scrollHeight"))   // measure height before insert
        #expect(js.contains("scrollTop"))       // restore offset by the delta
        #expect(js.contains("data-vreader-spine-index=\"3\""))
    }

    // MARK: - remove (eviction)

    @Test("removeChapterSectionJS targets the evicted section by spine index")
    func removeTargetsSpineIndex() {
        let js = EPUBContinuousScrollJS.removeChapterSectionJS(spineIndex: 7)
        #expect(js.contains("data-vreader-spine-index=\"7\""))
        #expect(js.lowercased().contains("remove"))
        // Codex Gate-4: a top-end eviction (section above the viewport) must
        // anchor the viewport, mirroring prepend — so the JS reads scrollHeight
        // + adjusts scrollTop when the removed section was above scrollTop.
        #expect(js.contains("scrollHeight"))
        #expect(js.contains("scrollTop"))
    }

    // MARK: - scroll observer

    @Test("observer reports the section-aware progress fields")
    func observerReportsFields() {
        let js = EPUBContinuousScrollJS.continuousScrollObserverJS
        #expect(js.contains("visibleSpineIndex"))
        #expect(js.contains("intraFraction"))
        #expect(js.contains("nearTopBoundary"))
        #expect(js.contains("nearBottomBoundary"))
    }

    // MARK: - scroll-to-section

    @Test("scrollToSpineFractionJS clamps the fraction to 0...1")
    func scrollToSpineFractionClamps() {
        let over = EPUBContinuousScrollJS.scrollToSpineFractionJS(spineIndex: 2, fraction: 1.8)
        let under = EPUBContinuousScrollJS.scrollToSpineFractionJS(spineIndex: 2, fraction: -0.5)
        let ok = EPUBContinuousScrollJS.scrollToSpineFractionJS(spineIndex: 2, fraction: 0.4)
        #expect(over.contains("1.0"))
        #expect(under.contains("0.0"))
        #expect(ok.contains("0.4"))
        #expect(over.contains("data-vreader-spine-index=\"2\""))
    }

    @Test("scrollToSpineFractionJS coerces a non-finite fraction to 0")
    func scrollToSpineFractionNonFinite() {
        let nan = EPUBContinuousScrollJS.scrollToSpineFractionJS(spineIndex: 1, fraction: .nan)
        #expect(nan.contains("0.0"))
        #expect(!nan.lowercased().contains("nan"))
    }

    // MARK: - find-in-section (scoped, not whole document)

    @Test("findInSectionJS scopes the search to the section subtree, not document")
    func findInSectionScoped() {
        let js = EPUBContinuousScrollJS.findInSectionJS(spineIndex: 5, quote: "needle")
        #expect(js.contains("data-vreader-spine-index=\"5\""))
        #expect(js.contains("needle"))
    }

    @Test("findInSectionJS escapes a single quote in the quote")
    func findInSectionEscapesQuote() {
        let js = EPUBContinuousScrollJS.findInSectionJS(spineIndex: 5, quote: "can't stop")
        #expect(js.contains(#"can\'t"#))
        #expect(!js.contains("can't stop"))
    }

    // MARK: - WI-6b-ii: chapter-content wrapper + sectionMaterialized lifecycle

    private func sectionBody(spineIndex: Int = 3, href: String = "OEBPS/text/c3.xhtml") -> EPUBChapterBody {
        EPUBChapterBody(spineIndex: spineIndex, href: href, bodyHTML: "<p>hello</p>", scopedStyleHTML: "")
    }

    @Test("appended section wraps the body in .vreader-chapter-content after the divider")
    func appendWrapsChapterContent() {
        let js = EPUBContinuousScrollJS.appendChapterSectionJS(sectionBody(), dividerTitle: "Chapter 3")
        #expect(js.contains("vreader-chapter-content"))
        // The wrapper opens AFTER the divider so the divider div stays out of the
        // chapter body's element-index space (WI-6b-ii re-rooting invariant).
        let dividerIdx = js.range(of: "vreader-chapter-divider")
            .map { js.distance(from: js.startIndex, to: $0.lowerBound) }
        let contentIdx = js.range(of: "vreader-chapter-content")
            .map { js.distance(from: js.startIndex, to: $0.lowerBound) }
        #expect(dividerIdx != nil && contentIdx != nil && dividerIdx! < contentIdx!)
    }

    @Test("appended section posts sectionMaterialized with spineIndex + href")
    func appendPostsSectionMaterialized() {
        let js = EPUBContinuousScrollJS.appendChapterSectionJS(
            sectionBody(spineIndex: 3, href: "OEBPS/text/c3.xhtml"), dividerTitle: nil)
        #expect(js.contains("messageHandlers.sectionMaterialized.postMessage"))
        #expect(js.contains("spineIndex: 3"))
        #expect(js.contains("OEBPS/text/c3.xhtml"))
    }

    @Test("prepended section also posts sectionMaterialized + wraps content")
    func prependPostsSectionMaterialized() {
        let js = EPUBContinuousScrollJS.prependChapterSectionJS(
            sectionBody(spineIndex: 2, href: "ch2.xhtml"), dividerTitle: nil)
        #expect(js.contains("messageHandlers.sectionMaterialized.postMessage"))
        #expect(js.contains("spineIndex: 2"))
        #expect(js.contains("vreader-chapter-content"))
    }
}
