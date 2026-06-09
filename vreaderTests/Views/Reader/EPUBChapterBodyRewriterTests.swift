// Purpose: Tests for EPUBChapterBodyRewriter — the pure XHTML→merged-DOM
// rewriter that lets one EPUB chapter's body live inside the shared
// continuous-scroll document (feature #71, WI-2).
//
// The rewriter is foundational and pure: given a chapter's XHTML it
// (1) extracts the <body> inner HTML, (2) absolutizes relative resource
// URLs against the chapter's own directory, (3) namespaces `id`s + intra-doc
// `#fragment` references by spine index so stitched chapters don't collide,
// and (4) inlines + scopes each chapter's CSS (inline <style> and linked
// <link rel=stylesheet>, the latter via an injected loader) under a
// per-section attribute selector, rewriting nested CSS url(...) to absolute.
// No WKWebView, no I/O — the loader is a closure so the whole contract is
// unit-tested here before the bridge wiring (WI-5+) consumes it.
//
// @coordinates-with: EPUBChapterBodyRewriter.swift, EPUBChapterCSSScoper.swift,
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-2)

import Testing
@testable import vreader

@Suite("EPUBChapterBodyRewriter")
struct EPUBChapterBodyRewriterTests {

    // Default chapter location used across cases: OEBPS/text/c1.xhtml under
    // a file:// extracted root.
    private let href = "OEBPS/text/c1.xhtml"
    private let prefix = "file:///root/"

    private func rewrite(
        _ xhtml: String,
        spineIndex: Int = 3,
        href: String? = nil,
        loader: @escaping (String) -> String? = { _ in nil }
    ) -> EPUBChapterBody {
        EPUBChapterBodyRewriter.rewrite(
            xhtml: xhtml,
            spineIndex: spineIndex,
            href: href ?? self.href,
            resourceBaseAbsolutePrefix: prefix,
            linkedStylesheetLoader: loader
        )
    }

    // MARK: - <body> extraction

    @Test("extracts <body> inner HTML, drops the body tag and head content")
    func extractsBodyInner() {
        let body = rewrite("""
        <html><head><title>X</title></head><body><p>Hello</p></body></html>
        """)
        #expect(body.bodyHTML.contains("<p>Hello</p>"))
        #expect(!body.bodyHTML.contains("<body"))
        #expect(!body.bodyHTML.contains("</body>"))
        #expect(!body.bodyHTML.contains("<title>"))
    }

    @Test("body tag with attributes is handled")
    func bodyWithAttributes() {
        let body = rewrite(#"<html><body class="chap" id="root"><p>Hi</p></body></html>"#)
        #expect(body.bodyHTML.contains("<p>Hi</p>"))
        #expect(!body.bodyHTML.contains("<body"))
    }

    @Test("returns spineIndex + href on the result")
    func carriesIdentity() {
        let body = rewrite("<html><body><p>x</p></body></html>", spineIndex: 7, href: "a/b.xhtml")
        #expect(body.spineIndex == 7)
        #expect(body.href == "a/b.xhtml")
    }

    // MARK: - relative resource URL absolutization

    @Test("relative img src is absolutized against the chapter dir")
    func relativeSrcAbsolutized() {
        let body = rewrite(#"<html><body><img src="../img/a.png"/></body></html>"#)
        // OEBPS/text + ../img/a.png  ->  OEBPS/img/a.png
        #expect(body.bodyHTML.contains(#"src="file:///root/OEBPS/img/a.png""#))
    }

    @Test("same-dir relative src resolves without a leading ./")
    func sameDirSrc() {
        let body = rewrite(#"<html><body><img src="pic.png"/></body></html>"#)
        #expect(body.bodyHTML.contains(#"src="file:///root/OEBPS/text/pic.png""#))
    }

    @Test("nested chapter dir resolves multi-level ../")
    func nestedChapterDir() {
        let body = rewrite(
            #"<html><body><img src="../../img/a.png"/></body></html>"#,
            href: "OEBPS/xhtml/sub/c.xhtml"
        )
        // OEBPS/xhtml/sub + ../../img/a.png -> OEBPS/img/a.png
        #expect(body.bodyHTML.contains(#"src="file:///root/OEBPS/img/a.png""#))
    }

    @Test("absolute-scheme src is left untouched")
    func schemeSrcUntouched() {
        let body = rewrite(#"""
        <html><body><img src="https://x.com/a.png"/><img src="data:image/png;base64,AAAA"/></body></html>
        """#)
        #expect(body.bodyHTML.contains(#"src="https://x.com/a.png""#))
        #expect(body.bodyHTML.contains(#"src="data:image/png;base64,AAAA""#))
    }

    // MARK: - id + intra-doc fragment namespacing

    @Test("id attributes are namespaced by spine index")
    func idNamespaced() {
        let body = rewrite(#"<html><body><p id="n1">x</p><span id="n2"/></body></html>"#)
        #expect(body.bodyHTML.contains(#"id="s3-n1""#))
        #expect(body.bodyHTML.contains(#"id="s3-n2""#))
        #expect(!body.bodyHTML.contains(#"id="n1""#))
    }

    @Test("intra-doc #fragment href is namespaced")
    func intraDocFragmentNamespaced() {
        let body = rewrite(##"<html><body><a href="#n1">note</a></body></html>"##)
        #expect(body.bodyHTML.contains(##"href="#s3-n1""##))
    }

    @Test("cross-document href is NOT touched")
    func crossDocumentHrefUntouched() {
        let body = rewrite(#"""
        <html><body><a href="chapter2.xhtml">next</a><a href="chapter2.xhtml#sec">sec</a></body></html>
        """#)
        #expect(body.bodyHTML.contains(#"href="chapter2.xhtml""#))
        #expect(body.bodyHTML.contains(#"href="chapter2.xhtml#sec""#))
    }

    @Test("external href is NOT touched")
    func externalHrefUntouched() {
        let body = rewrite(#"<html><body><a href="https://x.com/p">x</a></body></html>"#)
        #expect(body.bodyHTML.contains(#"href="https://x.com/p""#))
    }

    @Test("SVG use href + xlink:href fragments are namespaced")
    func svgUseNamespaced() {
        let body = rewrite(#"""
        <html><body><svg><use href="#sym"/><use xlink:href="#sym2"/></svg></body></html>
        """#)
        #expect(body.bodyHTML.contains(##"href="#s3-sym""##))
        #expect(body.bodyHTML.contains(##"xlink:href="#s3-sym2""##))
    }

    // Bug #332: an SVG cover/title-page image's RELATIVE xlink:href must be
    // absolutized against the chapter dir (like `src`) so it resolves on the #71
    // continuous-scroll stitch's single shared base URL, instead of 404'ing into a
    // broken-image glyph.
    @Test("relative SVG xlink:href image is absolutized against the chapter dir")
    func svgImageXlinkHrefAbsolutized() {
        let body = rewrite(#"<html><body><svg><image xlink:href="../img/cover.jpg"/></svg></body></html>"#)
        #expect(body.bodyHTML.contains(#"xlink:href="file:///root/OEBPS/img/cover.jpg""#))
    }

    @Test("same-dir SVG xlink:href image is absolutized without a leading ./")
    func svgImageXlinkHrefSameDir() {
        let body = rewrite(#"<html><body><svg><image xlink:href="cover.jpg"/></svg></body></html>"#)
        #expect(body.bodyHTML.contains(#"xlink:href="file:///root/OEBPS/text/cover.jpg""#))
    }

    @Test("absolute-scheme SVG xlink:href is left untouched")
    func svgImageXlinkHrefAbsoluteUntouched() {
        let body = rewrite(#"<html><body><svg><image xlink:href="https://x.com/c.jpg"/></svg></body></html>"#)
        #expect(body.bodyHTML.contains(#"xlink:href="https://x.com/c.jpg""#))
    }

    // Regression guard: a cross-document <a href> stays a navigation ref — it must
    // NOT be absolutized into a resource URL (that would break spine navigation).
    @Test("cross-document <a href> is still NOT absolutized")
    func anchorHrefNotAbsolutized() {
        let body = rewrite(#"<html><body><a href="chapter2.xhtml">next</a></body></html>"#)
        #expect(body.bodyHTML.contains(#"href="chapter2.xhtml""#))
    }

    // Bug #332 (Codex audit): SVG2 `<image href>` (no xlink:) is a resource ref too
    // (WebKit supports it). A relative href INSIDE <image>/<use> is absolutized;
    // <a href> stays untouched.
    @Test("relative SVG2 <image href> is absolutized")
    func svg2ImageHrefAbsolutized() {
        let body = rewrite(#"<html><body><svg><image href="../img/cover.jpg"/></svg></body></html>"#)
        #expect(body.bodyHTML.contains(#"href="file:///root/OEBPS/img/cover.jpg""#))
    }

    @Test("relative SVG2 <use href> is absolutized")
    func svg2UseHrefAbsolutized() {
        let body = rewrite(#"<html><body><svg><use href="defs.svg"/></svg></body></html>"#)
        #expect(body.bodyHTML.contains(#"href="file:///root/OEBPS/text/defs.svg""#))
    }

    @Test("absolute SVG2 <image href> is left untouched")
    func svg2ImageHrefAbsoluteUntouched() {
        let body = rewrite(#"<html><body><svg><image href="https://x.com/c.jpg"/></svg></body></html>"#)
        #expect(body.bodyHTML.contains(#"href="https://x.com/c.jpg""#))
    }

    // The SVG2-href pass must not touch an <a href> that happens to sit near an
    // <image> — only hrefs inside <image>/<use> tags are absolutized.
    @Test("<a href> next to an <image href> stays a navigation ref")
    func anchorHrefNearImageUntouched() {
        let body = rewrite(#"<html><body><a href="next.xhtml">x</a><svg><image href="c.jpg"/></svg></body></html>"#)
        #expect(body.bodyHTML.contains(#"href="next.xhtml""#))
        #expect(body.bodyHTML.contains(#"href="file:///root/OEBPS/text/c.jpg""#))
    }

    @Test("ARIA labelledby + describedby id references are namespaced (space-separated list)")
    func ariaReferencesNamespaced() {
        let body = rewrite(#"""
        <html><body><div aria-labelledby="lbl1 lbl2" aria-describedby="desc1">x</div></body></html>
        """#)
        #expect(body.bodyHTML.contains(#"aria-labelledby="s3-lbl1 s3-lbl2""#))
        #expect(body.bodyHTML.contains(#"aria-describedby="s3-desc1""#))
    }

    // MARK: - inline <style> scoping

    @Test("inline <style> is scoped under the section selector and removed from body")
    func inlineStyleScoped() {
        let body = rewrite(#"""
        <html><head><style>p { color: red; }</style></head><body><p>x</p></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] p"#))
        #expect(body.scopedStyleHTML.contains("color: red"))
        // the <style> must not remain duplicated in the body
        #expect(!body.bodyHTML.contains("<style"))
    }

    @Test("body/html selectors map to the section root, not a descendant")
    func rootSelectorMapsToSection() {
        let body = rewrite(#"""
        <html><head><style>body { margin: 0; }</style></head><body><p>x</p></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"]"#))
        #expect(body.scopedStyleHTML.contains("margin: 0"))
        // must NOT produce a descendant "... body" selector (there is no body in the section)
        #expect(!body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] body"#))
    }

    @Test("multiple comma-separated selectors each get the scope prefix")
    func commaSelectorsScoped() {
        let body = rewrite(#"""
        <html><head><style>h1, .note { font-weight: bold; }</style></head><body><h1>x</h1></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] h1"#))
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] .note"#))
    }

    @Test("@font-face / @keyframes at-rules are NOT selector-prefixed")
    func atRulesNotPrefixed() {
        let body = rewrite(#"""
        <html><head><style>@font-face { font-family: F; src: url(x.woff); } p { color: blue; }</style></head><body><p>x</p></body></html>
        """#)
        // the @font-face block survives without a scope prefix in front of it
        #expect(body.scopedStyleHTML.contains("@font-face"))
        #expect(!body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] @font-face"#))
        // but normal rules are still scoped
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] p"#))
    }

    @Test("@media inner selectors are scoped while the @media query is preserved")
    func mediaInnerScoped() {
        let body = rewrite(#"""
        <html><head><style>@media screen { p { color: green; } }</style></head><body><p>x</p></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains("@media screen"))
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] p"#))
    }

    // MARK: - linked stylesheet inlining

    @Test("linked stylesheet is loaded, inlined, scoped, and the link removed")
    func linkedStylesheetInlined() {
        // The loader is handed the CHAPTER-RESOLVED href, not the bare `<link>`
        // href: chapter dir OEBPS/text + ../css/style.css -> OEBPS/css/style.css.
        let body = rewrite(
            #"""
            <html><head><link rel="stylesheet" href="../css/style.css"/></head><body><p>x</p></body></html>
            """#,
            loader: { rel in rel == "OEBPS/css/style.css" ? "p { color: red; }" : nil }
        )
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] p"#))
        #expect(body.scopedStyleHTML.contains("color: red"))
        #expect(!body.bodyHTML.contains("<link"))
    }

    @Test("linked stylesheet href is resolved against the chapter dir before the loader sees it")
    func linkedStylesheetResolvedAgainstChapterDir() {
        // Regression for the feature-#71 flag-flip Gate-4 Medium: a nested chapter
        // with a cross-directory `<link href="../css/style.css">` must resolve the
        // href against the chapter's directory (NOT the resource root) before the
        // loader fetches it — otherwise the loader gets a root-escaping path and
        // the chapter renders unstyled. Capture exactly what the loader receives.
        nonisolated(unsafe) var seen: [String] = []
        let body = rewrite(
            #"""
            <html><head><link rel="stylesheet" href="../css/style.css"/></head><body><p>x</p></body></html>
            """#,
            href: "OEBPS/text/sub/c.xhtml",
            loader: { rel in seen.append(rel); return "p { color: blue; }" }
        )
        // OEBPS/text/sub + ../css/style.css -> OEBPS/text/css/style.css
        #expect(seen == ["OEBPS/text/css/style.css"])
        #expect(body.scopedStyleHTML.contains("color: blue"))
    }

    @Test("flat-EPUB linked stylesheet href is unchanged (no chapter dir)")
    func flatLinkedStylesheetUnchanged() {
        // A flat EPUB (chapter at the root) must keep passing the bare href — the
        // fix must not regress the common case. chapterDir == "" so the resolved
        // href equals the bare href.
        nonisolated(unsafe) var seen: [String] = []
        _ = rewrite(
            #"""
            <html><head><link rel="stylesheet" href="style.css"/></head><body><p>x</p></body></html>
            """#,
            href: "chapter1.xhtml",
            loader: { rel in seen.append(rel); return "p { color: red; }" }
        )
        #expect(seen == ["style.css"])
    }

    @Test("nested CSS url(...) in a linked stylesheet is absolutized against the stylesheet dir")
    func nestedCssUrlAbsolutized() {
        let body = rewrite(
            #"""
            <html><head><link rel="stylesheet" href="../css/style.css"/></head><body><p>x</p></body></html>
            """#,
            loader: { _ in "@font-face { font-family: F; src: url(../fonts/x.woff); }" }
        )
        // stylesheet dir = OEBPS/css ; ../fonts/x.woff -> OEBPS/fonts/x.woff
        #expect(body.scopedStyleHTML.contains(#"url("file:///root/OEBPS/fonts/x.woff")"#))
    }

    @Test("inline <style> url(...) is absolutized against the chapter dir")
    func inlineStyleUrlAbsolutized() {
        let body = rewrite(#"""
        <html><head><style>div { background: url("bg.png"); }</style></head><body><div>x</div></body></html>
        """#)
        // chapter dir = OEBPS/text ; bg.png -> OEBPS/text/bg.png
        #expect(body.scopedStyleHTML.contains(#"url("file:///root/OEBPS/text/bg.png")"#))
    }

    @Test("quoted CSS url() containing ) is absolutized correctly")
    func cssUrlWithParensInQuotes() {
        let body = rewrite(#"""
        <html><head><style>div { background: url("bg(1).png"); }</style></head><body><div>x</div></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"url("file:///root/OEBPS/text/bg(1).png")"#))
    }

    @Test("url(...) inside a CSS string value is left literal, not absolutized")
    func cssUrlInsideStringNotRewritten() {
        let body = rewrite(#"""
        <html><head><style>p::before { content: "url(bg.png)"; }</style></head><body><p>x</p></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"content: "url(bg.png)""#))
        #expect(!body.scopedStyleHTML.contains("file://"))
    }

    @Test("url(...) inside a CSS comment is left literal, not absolutized")
    func cssUrlInsideCommentNotRewritten() {
        let body = rewrite(#"""
        <html><head><style>/* url(bg.png) */ p { color: red; }</style></head><body><p>x</p></body></html>
        """#)
        // the url inside the comment must stay literal (not absolutized) …
        #expect(!body.scopedStyleHTML.contains("file://"))
        #expect(body.scopedStyleHTML.contains("url(bg.png)"))
        // … and the rule is still scoped (a leading comment is whitespace-equivalent
        // in the selector, so it may sit between the scope prefix and `p`).
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"]"#))
        #expect(body.scopedStyleHTML.contains("color: red"))
    }

    @Test("a <link> whose attribute merely contains 'stylesheet' is NOT treated as a stylesheet")
    func nonStylesheetLinkIgnored() {
        let body = rewrite(
            #"""
            <html><head><link rel="icon" href="foo-stylesheet.png"/></head><body><p>x</p></body></html>
            """#,
            loader: { _ in "p { color: red; }" }
        )
        // loader must not have been consulted (rel is "icon", not "stylesheet")
        #expect(body.scopedStyleHTML.isEmpty)
        #expect(!body.bodyHTML.contains("<link"))
    }

    @Test("a stylesheet the loader cannot resolve is skipped without crashing")
    func missingStylesheetSkipped() {
        let body = rewrite(
            #"""
            <html><head><link rel="stylesheet" href="missing.css"/></head><body><p>x</p></body></html>
            """#,
            loader: { _ in nil }
        )
        #expect(body.bodyHTML.contains("<p>x</p>"))
        #expect(!body.scopedStyleHTML.contains("missing.css"))
        #expect(!body.bodyHTML.contains("<link"))
    }

    // MARK: - degenerate input

    @Test("XHTML with no <body> returns an empty body without crashing")
    func malformedNoBody() {
        let body = rewrite("<html><head><title>x</title></head></html>")
        #expect(body.bodyHTML.isEmpty)
    }

    @Test("empty input returns empty body and empty style")
    func emptyInput() {
        let body = rewrite("")
        #expect(body.bodyHTML.isEmpty)
        #expect(body.scopedStyleHTML.isEmpty)
    }

    // MARK: - Unicode / CJK

    @Test("CJK body text and CJK fragment ids are preserved + namespaced")
    func cjkPreserved() {
        let body = rewrite(#"""
        <html><body><p id="章节">你好世界</p><a href="#章节">跳转</a></body></html>
        """#)
        #expect(body.bodyHTML.contains("你好世界"))
        #expect(body.bodyHTML.contains(#"id="s3-章节""#))
        #expect(body.bodyHTML.contains(##"href="#s3-章节""##))
    }

    // MARK: - Codex Gate-4 hardening

    @Test("attribute with whitespace around = is still namespaced")
    func attrWhitespaceAroundEquals() {
        let body = rewrite(#"<html><body><p id = "n1">x</p><img src = "a.png"/></body></html>"#)
        #expect(body.bodyHTML.contains(#"id="s3-n1""#))
        #expect(body.bodyHTML.contains(#"src="file:///root/OEBPS/text/a.png""#))
    }

    @Test("@import is dropped (would otherwise leak unscoped across chapters)")
    func atImportDropped() {
        let body = rewrite(#"""
        <html><head><style>@import url(other.css); p { color: red; }</style></head><body><p>x</p></body></html>
        """#)
        #expect(!body.scopedStyleHTML.contains("@import"))
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] p"#))
    }

    // WI-6b-ii: root selectors now collapse onto the chapter-content wrapper
    // (`[section] > .vreader-chapter-content`), the synthetic <body> in the
    // stitched document, so child-combinator root selectors resolve through the
    // wrapper that holds the chapter body's children.
    @Test("leading root-selector chain collapses onto the content wrapper (html body p -> [section] > .vreader-chapter-content p)")
    func rootChainCollapsed() {
        let body = rewrite(#"""
        <html><head><style>html body p { color: red; }</style></head><body><p>x</p></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] > .vreader-chapter-content p"#))
        #expect(!body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] body"#))
    }

    @Test("root element with a direct qualifier attaches to the wrapper (body.x -> [section] > .vreader-chapter-content.x)")
    func rootDirectQualifier() {
        let body = rewrite(#"""
        <html><head><style>body.theme { background: white; }</style></head><body class="theme"><p>x</p></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] > .vreader-chapter-content.theme"#))
    }

    @Test("child combinator after root is preserved (html > body > img -> [section] > .vreader-chapter-content > img)")
    func rootChildCombinator() {
        let body = rewrite(#"""
        <html><head><style>html > body > img { width: 100%; }</style></head><body><img/></body></html>
        """#)
        #expect(body.scopedStyleHTML.contains(#"[data-vreader-spine-index="3"] > .vreader-chapter-content > img"#))
    }

    @Test("multiple <body> tags: only the first body's content is taken")
    func multipleBodyTakesFirst() {
        let body = rewrite("<html><body>a</body>junk<body>b</body></html>")
        #expect(body.bodyHTML == "a")
    }
}
