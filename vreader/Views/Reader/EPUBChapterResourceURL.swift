// Purpose: EPUB resource-path arithmetic shared by the continuous-scroll
// chapter rewriter and its CSS scoper (feature #71, WI-2). Resolves a relative
// resource path (image / font / `url(...)`) against a chapter or stylesheet
// directory, and decides whether a URL is already self-resolving (has a
// scheme, is protocol-relative, a `data:` URI, or a bare `#fragment`) and so
// must be left untouched.
//
// Pure value math — no I/O, no Foundation URL machinery (EPUB hrefs are
// archive-relative POSIX paths, not file-system URLs, so simple segment
// normalization is both sufficient and predictable across `..`/`.`).
//
// @coordinates-with: EPUBChapterBodyRewriter.swift, EPUBChapterCSSScoper.swift

import Foundation

enum EPUBChapterResourceURL {

    /// The directory portion of an href (everything before the last `/`).
    /// `"OEBPS/text/c1.xhtml"` -> `"OEBPS/text"`; `"c1.xhtml"` -> `""`.
    static func directory(ofHref href: String) -> String {
        guard let slash = href.lastIndex(of: "/") else { return "" }
        return String(href[..<slash])
    }

    /// Joins a relative path onto a directory, normalizing `.`/`..` segments.
    /// `join(dir: "OEBPS/text", relative: "../img/a.png")` -> `"OEBPS/img/a.png"`.
    static func join(dir: String, relative: String) -> String {
        var segments = dir.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for part in relative.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch part {
            case "..": if !segments.isEmpty { segments.removeLast() }
            case ".": continue
            default: segments.append(part)
            }
        }
        return segments.joined(separator: "/")
    }

    /// Absolutizes relative `url(...)` references in a CSS string against
    /// `baseDir`. A hand scanner (not a regex) so quoted URLs containing `)`
    /// or escape sequences (`url("bg(1).png")`) are handled, and CSS strings
    /// (`content: "url(x)"`) + comments (`/* url(x) */`) are copied verbatim
    /// rather than rewritten (Codex Gate-4). Absolute / `data:` / fragment
    /// URLs are emitted verbatim; resolved relative URLs are double-quoted
    /// (always-valid CSS regardless of the characters in the path).
    static func rewriteCSSURLs(in css: String, baseDir: String, prefix: String) -> String {
        let chars = Array(css)
        let n = chars.count
        var out = ""
        var i = 0
        while i < n {
            // copy CSS strings verbatim — a `url(...)` inside them is literal text
            if chars[i] == "\"" || chars[i] == "'" {
                let end = endOfCSSString(chars, openingAt: i)
                out += String(chars[i..<end]); i = end; continue
            }
            // copy comments verbatim
            if chars[i] == "/", i + 1 < n, chars[i + 1] == "*" {
                var k = i + 2
                while k + 1 < n, !(chars[k] == "*" && chars[k + 1] == "/") { k += 1 }
                k = min(k + 2, n)
                out += String(chars[i..<k]); i = k; continue
            }
            guard matchesURLOpen(chars, at: i) else { out.append(chars[i]); i += 1; continue }
            var j = i + 4
            while j < n, chars[j].isWhitespace { j += 1 }
            var url: String?
            var after = i
            if j < n, chars[j] == "\"" || chars[j] == "'" {
                let quote = chars[j]
                var k = j + 1
                var value = ""
                while k < n, chars[k] != quote {
                    if chars[k] == "\\", k + 1 < n { value.append(chars[k]); value.append(chars[k + 1]); k += 2; continue }
                    value.append(chars[k]); k += 1
                }
                var m = k < n ? k + 1 : k
                while m < n, chars[m].isWhitespace { m += 1 }
                if m < n, chars[m] == ")" { url = value; after = m + 1 }
            } else {
                var k = j
                while k < n, chars[k] != ")" { k += 1 }
                if k < n { url = String(chars[j..<k]).trimmingCharacters(in: .whitespaces); after = k + 1 }
            }
            guard let resolved = url else { out.append(chars[i]); i += 1; continue }
            if isAbsoluteOrFragment(resolved) {
                out += String(chars[i..<after]) // leave absolute / data: / fragment verbatim
            } else {
                out += "url(\"\(prefix + join(dir: baseDir, relative: resolved))\")"
            }
            i = after
        }
        return out
    }

    private static func matchesURLOpen(_ chars: [Character], at i: Int) -> Bool {
        guard i + 4 <= chars.count else { return false }
        return String(chars[i..<i + 4]).lowercased() == "url("
    }

    /// Index just past the closing quote of the CSS string opening at `start`
    /// (honoring `\` escapes); `chars.count` if unterminated.
    private static func endOfCSSString(_ chars: [Character], openingAt start: Int) -> Int {
        let quote = chars[start]
        let n = chars.count
        var i = start + 1
        while i < n {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == quote { return i + 1 }
            i += 1
        }
        return n
    }

    /// True when the URL already resolves on its own (scheme, `//`, `data:`,
    /// bare `#fragment`, or empty) and must not be absolutized.
    static func isAbsoluteOrFragment(_ url: String) -> Bool {
        if url.isEmpty || url.hasPrefix("#") || url.hasPrefix("//") { return true }
        // scheme: ^[a-zA-Z][a-zA-Z0-9+.-]*:
        if let colon = url.firstIndex(of: ":") {
            let scheme = url[..<colon]
            if !scheme.isEmpty,
               scheme.first!.isLetter,
               scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }) {
                return true
            }
        }
        return false
    }
}
