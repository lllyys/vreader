// Purpose: Pure XHTML→merged-DOM rewriter for feature #71 (EPUB scroll-mode
// continuous cross-chapter scroll, WI-2). Rewrites one chapter's XHTML so it
// can live as a `<section>` inside the shared continuous-scroll WKWebView
// document without colliding with sibling chapters.
//
// Background: today each EPUB chapter is its own `loadFileURL` document with
// its own base URL, so relative asset refs, local `#fragment` anchors, `id`s,
// and per-chapter CSS all resolve in isolation. Stitching N chapters into one
// document collapses them onto a single base URL and a single id space — so
// before a chapter body is appended it must be rewritten:
//   1. extract the `<body>` inner HTML (drop `<html>`/`<head>`/`<body>` tags);
//   2. absolutize relative resource URLs (`src`, CSS `url(...)`) against the
//      chapter's own directory so images/fonts still load;
//   3. namespace `id` attributes + intra-doc `#fragment` references (href /
//      xlink:href / aria-labelledby / aria-describedby) by spine index so two
//      chapters that both define `id="n1"` don't collide;
//   4. inline + scope each chapter's CSS (inline `<style>` and linked
//      `<link rel=stylesheet>`) under a `[data-vreader-spine-index="N"]`
//      selector so one chapter's `p{...}` can't restyle another.
//
// Key decisions:
// - Pure + closure-injected I/O (Gate-2 round-2 [C2-residual]): linked
//   stylesheets are fetched through `linkedStylesheetLoader`, a caller-supplied
//   closure, so the rewriter stays a pure function unit-tested with a stub
//   loader. A stylesheet the loader can't resolve is skipped (logged), never a
//   crash.
// - Cross-document `href`s are deliberately left untouched (Gate-2 [C1] note):
//   only `#fragment` hrefs are namespaced; `chapter2.xhtml` links stay as-is.
//   Cross-section navigation is the bridge's concern (WI-5+), not this contract.
// - Regex-based rewriting (no XML DOM): iOS has no `XMLDocument`, and the
//   transformations are attribute/selector-local, so targeted regexes match
//   the existing parser style in this codebase without a third-party lib.
// - Trust boundary (Codex Gate-4): this rewriter does NOT sanitize active
//   content (`<script>`, `on*=` handlers, `javascript:` URLs). That is
//   deliberate and introduces no new surface: the existing single-chapter
//   path already loads chapter XHTML verbatim into the same WKWebView via
//   `loadFileURL` (content JS at default), so EPUB content is the same
//   trusted-local-file model continuous mode inherits. Adding sanitization
//   here would diverge from the paged path and could break legitimate EPUB3
//   scripted content; if a uniform sanitization policy is ever wanted it
//   belongs at the bridge level, applied to both modes, not silently in this
//   foundational shape-transformer. JS-string escaping for the append/prepend
//   injection is a separate concern handled by FoliateJSEscaper in WI-3.
//
// @coordinates-with: EPUBChapterCSSScoper.swift (CSS selector scoping + url()),
//   EPUBContinuousScrollCoordinator.swift (WI-4 consumer),
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-2)

import Foundation
import OSLog

/// A chapter's body rewritten so it can be appended into the shared
/// continuous-scroll document. Value type — no WKWebView, no I/O.
struct EPUBChapterBody: Equatable {
    /// The chapter's spine index (used to namespace ids + scope CSS).
    let spineIndex: Int
    /// The chapter's href relative to the extracted root (identity / locator).
    let href: String
    /// The rewritten `<body>` inner HTML (no `<style>` / `<link>` — those are
    /// hoisted into `scopedStyleHTML`).
    let bodyHTML: String
    /// A single `<style>` element carrying all of the chapter's CSS, scoped
    /// under `[data-vreader-spine-index="N"]`. Empty when the chapter has no CSS.
    let scopedStyleHTML: String
}

enum EPUBChapterBodyRewriter {

    private static let log = Logger(subsystem: "com.vreader.app", category: "EPUBChapterBodyRewriter")

    /// Rewrites a chapter's XHTML into an `EPUBChapterBody`.
    ///
    /// - Parameters:
    ///   - xhtml: the chapter's full XHTML source.
    ///   - spineIndex: the chapter's spine index — namespaces ids/fragments and
    ///     scopes CSS.
    ///   - href: the chapter's href relative to the extracted root
    ///     (e.g. `OEBPS/text/c1.xhtml`); its directory is the base for
    ///     resolving relative resource URLs.
    ///   - resourceBaseAbsolutePrefix: absolute prefix the resolved path is
    ///     appended to (e.g. `file:///<extractedRoot>/`).
    ///   - linkedStylesheetLoader: resolves a `<link>`'s href (relative to the
    ///     chapter dir) to its CSS source, or `nil` to skip it.
    static func rewrite(
        xhtml: String,
        spineIndex: Int,
        href: String,
        resourceBaseAbsolutePrefix: String,
        linkedStylesheetLoader: (_ relativeHref: String) -> String?
    ) -> EPUBChapterBody {
        let sectionSelector = "[data-vreader-spine-index=\"\(spineIndex)\"]"
        let chapterDir = EPUBChapterResourceURL.directory(ofHref: href)

        // 1. Collect CSS from the whole document (inline <style> + linked
        //    <link rel=stylesheet>) BEFORE we slice out the body, since EPUBs
        //    most often declare them in <head>.
        var cssBlocks: [String] = []

        for inlineCSS in matchInlineStyles(in: xhtml) {
            cssBlocks.append(
                EPUBChapterCSSScoper.scope(
                    css: inlineCSS,
                    sectionSelector: sectionSelector,
                    baseDir: chapterDir,
                    resourceBaseAbsolutePrefix: resourceBaseAbsolutePrefix
                )
            )
        }
        for linkHref in matchStylesheetLinks(in: xhtml) {
            guard let css = linkedStylesheetLoader(linkHref) else {
                log.notice("skipped unresolved stylesheet \(linkHref, privacy: .public)")
                continue
            }
            let linkDir = EPUBChapterResourceURL.directory(
                ofHref: EPUBChapterResourceURL.join(dir: chapterDir, relative: linkHref)
            )
            cssBlocks.append(
                EPUBChapterCSSScoper.scope(
                    css: css,
                    sectionSelector: sectionSelector,
                    baseDir: linkDir,
                    resourceBaseAbsolutePrefix: resourceBaseAbsolutePrefix
                )
            )
        }

        // 2. Extract the <body> inner HTML, then strip any <style>/<link> that
        //    lived inside the body (already hoisted above).
        var body = extractBodyInner(from: xhtml)
        body = stripStyleAndLinkElements(from: body)

        // 3. Rewrite attributes on the body markup: namespace ids + intra-doc
        //    fragment refs, absolutize relative resource srcs.
        body = rewriteAttributes(in: body, spineIndex: spineIndex,
                                 chapterDir: chapterDir,
                                 resourceBaseAbsolutePrefix: resourceBaseAbsolutePrefix)

        let scopedStyle = cssBlocks.isEmpty ? "" : "<style>\(cssBlocks.joined(separator: "\n"))</style>"

        return EPUBChapterBody(
            spineIndex: spineIndex,
            href: href,
            bodyHTML: body,
            scopedStyleHTML: scopedStyle
        )
    }

    // MARK: - <body> extraction

    private static func extractBodyInner(from xhtml: String) -> String {
        // First `<body>` and the FIRST `</body>` after it: for a well-formed
        // single-body document this is the whole body; for pathological
        // multi-body input it yields just the first body's content rather than
        // stitching an embedded `</body>…<body>` seam into the merged DOM
        // (Codex Gate-4: multi-body robustness).
        guard let openRange = rangeOfFirstMatch(#"<body\b[^>]*>"#, in: xhtml),
              let closeRange = xhtml.range(of: "</body>", options: [.caseInsensitive],
                                           range: openRange.upperBound..<xhtml.endIndex)
        else { return "" }
        let inner = xhtml[openRange.upperBound..<closeRange.lowerBound]
        return String(inner)
    }

    private static func stripStyleAndLinkElements(from html: String) -> String {
        var out = removeMatches(#"<style\b[^>]*>[\s\S]*?</style>"#, in: html)
        out = removeMatches(#"<link\b[^>]*>"#, in: out)
        return out
    }

    // MARK: - CSS collection

    /// Inner text of every `<style>...</style>` block in the document.
    private static func matchInlineStyles(in xhtml: String) -> [String] {
        captureGroups(#"<style\b[^>]*>([\s\S]*?)</style>"#, group: 1, in: xhtml)
    }

    /// The `href` of every stylesheet `<link>`. Matches on the `rel`
    /// attribute's space-separated token list (Codex Gate-4) — NOT a substring
    /// scan of the whole tag, so `<link rel="icon" href="x-stylesheet.png">`
    /// is correctly ignored.
    private static func matchStylesheetLinks(in xhtml: String) -> [String] {
        var hrefs: [String] = []
        for tag in captureGroups(#"<link\b[^>]*>"#, group: 0, in: xhtml) {
            guard let rel = attributeValue("rel", in: tag) else { continue }
            let tokens = rel.lowercased().split { $0 == " " || $0 == "\t" || $0 == "\n" }
            guard tokens.contains("stylesheet") else { continue }
            if let href = attributeValue("href", in: tag) { hrefs.append(href) }
        }
        return hrefs
    }

    // MARK: - attribute rewriting

    private static func rewriteAttributes(
        in html: String,
        spineIndex: Int,
        chapterDir: String,
        resourceBaseAbsolutePrefix: String
    ) -> String {
        let ns = "s\(spineIndex)-"
        var out = html

        // id="x" -> id="s{N}-x"
        out = rewriteAttribute(out, attr: "id") { ns + $0 }

        // aria-labelledby / aria-describedby reference space-separated id lists.
        let nsList: (String) -> String = { value in
            value.split(separator: " ").map { ns + $0 }.joined(separator: " ")
        }
        out = rewriteAttribute(out, attr: "aria-labelledby", transform: nsList)
        out = rewriteAttribute(out, attr: "aria-describedby", transform: nsList)

        // href / xlink:href: only intra-doc #fragments are namespaced; every
        // other href (cross-document, external) is left untouched.
        let nsFragment: (String) -> String = { value in
            value.hasPrefix("#") ? "#" + ns + value.dropFirst() : value
        }
        out = rewriteAttribute(out, attr: "href", transform: nsFragment)
        out = rewriteAttribute(out, attr: "xlink:href", transform: nsFragment)

        // src: absolutize relative resource URLs against the chapter dir.
        out = rewriteAttribute(out, attr: "src") { value in
            EPUBChapterResourceURL.isAbsoluteOrFragment(value)
                ? value
                : resourceBaseAbsolutePrefix + EPUBChapterResourceURL.join(dir: chapterDir, relative: value)
        }

        return out
    }

    /// Rewrites every `attr="value"` / `attr='value'` occurrence (attribute
    /// preceded by whitespace so `href` does not match inside `xlink:href`).
    private static func rewriteAttribute(
        _ html: String,
        attr: String,
        transform: (String) -> String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: attr)
        // Allow XML whitespace around `=` (`id = "x"`); the `(?<=\s)` lookbehind
        // keeps `href` from matching inside `xlink:href` (Codex Gate-4).
        let pattern = "(?<=\\s)\(escaped)\\s*=\\s*([\"'])([^\"']*)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return html }
        let nsString = html as NSString
        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
        for match in matches.reversed() {
            let quote = nsString.substring(with: match.range(at: 1))
            let value = nsString.substring(with: match.range(at: 2))
            let replacement = "\(attr)=\(quote)\(transform(value))\(quote)"
            let r = Range(match.range, in: result)!
            result.replaceSubrange(r, with: replacement)
        }
        return result
    }

    // MARK: - small regex helpers

    private static func attributeValue(_ attr: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: attr)
        return captureGroups("(?<=\\s)\(escaped)\\s*=\\s*[\"']([^\"']*)[\"']", group: 1, in: tag).first
    }

    private static func rangeOfFirstMatch(_ pattern: String, in string: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(location: 0, length: (string as NSString).length)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        return Range(match.range, in: string)
    }

    private static func captureGroups(_ pattern: String, group: Int, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match in
            let r = match.range(at: group)
            return r.location == NSNotFound ? nil : nsString.substring(with: r)
        }
    }

    private static func removeMatches(_ pattern: String, in string: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return string }
        let nsString = string as NSString
        return regex.stringByReplacingMatches(
            in: string, range: NSRange(location: 0, length: nsString.length), withTemplate: ""
        )
    }
}
