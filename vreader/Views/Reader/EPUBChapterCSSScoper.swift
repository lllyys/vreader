// Purpose: Scopes one EPUB chapter's CSS so it cannot restyle sibling chapters
// once they share the continuous-scroll document (feature #71, WI-2). Prefixes
// every style-rule selector with `[data-vreader-spine-index="N"]`, maps the
// chapter's root selectors (`html`/`body`/`:root`) onto the section element
// itself, recurses into conditional group at-rules (`@media`/`@supports`/…),
// leaves non-selector at-rules (`@font-face`/`@keyframes`/…) verbatim, and
// absolutizes relative `url(...)` references against the stylesheet's directory.
//
// Key decisions:
// - Hand-rolled, string/comment-aware top-level scanner rather than a regex:
//   CSS nesting + strings make a single regex unsafe; the grammar we need
//   (rule = prelude + balanced `{...}`; or at-statement + `;`) is small.
// - Root selectors map to the section root, not a descendant: a chapter's
//   `<body>` becomes the `<section data-vreader-spine-index="N">`, so
//   `body{…}` scopes to `[…="N"]{…}`, not `[…="N"] body` (matches nothing).
//
// @coordinates-with: EPUBChapterBodyRewriter.swift (caller + EPUBChapterResourceURL)

import Foundation
import OSLog

enum EPUBChapterCSSScoper {

    private static let log = Logger(subsystem: "com.vreader.app", category: "EPUBChapterCSSScoper")

    /// Scopes `css` under `sectionSelector` and absolutizes relative `url(...)`
    /// against `baseDir` (the stylesheet's own directory) prefixed with
    /// `resourceBaseAbsolutePrefix`.
    static func scope(
        css: String,
        sectionSelector: String,
        baseDir: String,
        resourceBaseAbsolutePrefix: String
    ) -> String {
        let urlRewritten = EPUBChapterResourceURL.rewriteCSSURLs(
            in: css, baseDir: baseDir, prefix: resourceBaseAbsolutePrefix
        )
        return scopeStatements(urlRewritten, sectionSelector: sectionSelector)
    }

    // MARK: - selector scoping

    private static func scopeStatements(_ css: String, sectionSelector: String) -> String {
        let chars = Array(css)
        let n = chars.count
        var i = 0
        var prelude = ""
        var out = ""

        while i < n {
            let c = chars[i]

            // comment — copy verbatim into the current prelude
            if c == "/", i + 1 < n, chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < n, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = min(j + 2, n)
                prelude += String(chars[i..<j])
                i = j
                continue
            }

            // string literal inside a prelude (e.g. [title="x{y}"]) — copy whole
            if c == "\"" || c == "'" {
                let end = indexAfterString(chars, openingAt: i)
                prelude += String(chars[i..<end])
                i = end
                continue
            }

            if c == "{" {
                let (inner, next) = captureBlock(chars, openBraceAt: i)
                out += emitRule(prelude: prelude.trimmingCharacters(in: .whitespacesAndNewlines),
                                inner: inner, sectionSelector: sectionSelector)
                prelude = ""
                i = next
                continue
            }

            if c == ";" {
                let trimmed = prelude.trimmingCharacters(in: .whitespacesAndNewlines)
                // Drop @import (Codex Gate-4): an imported sheet is neither
                // inlined nor scoped, so leaving it leaks rules across chapters
                // in the merged DOM. Recursive inlining is a documented
                // follow-up; EPUB chapters overwhelmingly use <link>.
                if trimmed.lowercased().hasPrefix("@import") {
                    log.notice("dropped unscopable @import in continuous-scroll chapter CSS")
                } else if !trimmed.isEmpty {
                    out += trimmed + ";\n"
                }
                prelude = ""
                i += 1
                continue
            }

            prelude.append(c)
            i += 1
        }

        let leftover = prelude.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty { out += leftover }
        return out
    }

    /// Emits one rule: a style rule gets its selector list scoped; a
    /// conditional group at-rule recurses; any other at-rule is verbatim.
    private static func emitRule(prelude: String, inner: String, sectionSelector: String) -> String {
        guard !prelude.isEmpty else { return "" }
        if prelude.hasPrefix("@") {
            let keyword = atKeyword(prelude)
            let conditional: Set<String> = ["media", "supports", "document", "-moz-document", "container", "layer"]
            if conditional.contains(keyword) {
                let scopedInner = scopeStatements(inner, sectionSelector: sectionSelector)
                return "\(prelude) {\n\(scopedInner)\n}\n"
            }
            return "\(prelude) {\(inner)}\n"
        }
        let selectors = scopeSelectorList(prelude, sectionSelector: sectionSelector)
        return "\(selectors) {\(inner)}\n"
    }

    private static func atKeyword(_ prelude: String) -> String {
        var word = ""
        for ch in prelude.dropFirst() { // drop the '@'
            if ch.isLetter || ch == "-" { word.append(ch) } else { break }
        }
        return word.lowercased()
    }

    private static func scopeSelectorList(_ list: String, sectionSelector: String) -> String {
        splitTopLevel(list, separator: ",")
            .map { scopeOne($0.trimmingCharacters(in: .whitespacesAndNewlines), sectionSelector: sectionSelector) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Scopes one comma-free selector under the section. A LEADING run of root
    /// compounds (`html`/`body`/`:root`, with their qualifiers + inter-root
    /// combinators) collapses onto the section element — in the merged DOM the
    /// chapter's `<body>` IS the section, so `html body p` must become
    /// `[section] p`, `body.x` → `[section].x`, `html > body > img` →
    /// `[section] > img`, never a `body` descendant that matches nothing
    /// (Codex Gate-4). Non-root selectors become `[section] <selector>`.
    private static func scopeOne(_ selector: String, sectionSelector: String) -> String {
        let chars = Array(selector.trimmingCharacters(in: .whitespaces))
        guard !chars.isEmpty else { return "" }
        let n = chars.count
        var i = 0
        var consumedRoot = false
        var qualifiers = ""        // qualifiers on the FINAL root compound (.x, #y, …)
        var connector: String?     // combinator to the remainder; nil = direct attach

        while i < n, let token = rootTokenPrefix(chars, at: i) {
            let end = i + token.count
            if end < n, chars[end].isLetter || chars[end].isNumber || chars[end] == "-" || chars[end] == "_" {
                break // e.g. "bodywrap" — not the body element
            }
            consumedRoot = true
            i = end
            qualifiers = consumeQualifiers(chars, from: &i)
            let (combinator, advanced) = consumeCombinator(chars, from: &i)
            if i < n, rootTokenPrefix(chars, at: i) != nil {
                qualifiers = ""; connector = nil; continue // inter-root combinator
            }
            connector = combinator ?? (advanced ? " " : nil)
            break
        }

        guard consumedRoot else { return sectionSelector + " " + String(chars) }
        let remainder = String(chars[i..<n])
        if remainder.isEmpty { return sectionSelector + qualifiers }
        return sectionSelector + qualifiers + (connector ?? "") + remainder
    }

    private static func rootTokenPrefix(_ chars: [Character], at index: Int) -> String? {
        for token in ["html", "body", ":root"] {
            let t = Array(token)
            if index + t.count <= chars.count, Array(chars[index..<index + t.count]) == t { return token }
        }
        return nil
    }

    /// Consumes `.class` / `#id` / `[attr]` / `:pseudo(...)` directly attached
    /// (no combinator) to the current compound, honoring `[]`/`()` nesting.
    private static func consumeQualifiers(_ chars: [Character], from i: inout Int) -> String {
        let n = chars.count
        var out = ""
        var depth = 0
        while i < n {
            let c = chars[i]
            if c == "[" || c == "(" { depth += 1 }
            else if c == "]" || c == ")" { depth = max(0, depth - 1) }
            else if depth == 0, c == " " || c == "\t" || c == "\n" || c == ">" || c == "+" || c == "~" || c == "," { break }
            out.append(c); i += 1
        }
        return out
    }

    /// Consumes a combinator (whitespace + optional single `>`/`+`/`~` + ws).
    /// Returns the canonical combinator (` > ` etc.) when an explicit combinator
    /// char was present, and whether any whitespace/combinator was consumed.
    private static func consumeCombinator(_ chars: [Character], from i: inout Int) -> (String?, Bool) {
        let n = chars.count
        let start = i
        while i < n, chars[i] == " " || chars[i] == "\t" || chars[i] == "\n" { i += 1 }
        if i < n, chars[i] == ">" || chars[i] == "+" || chars[i] == "~" {
            let cc = chars[i]; i += 1
            while i < n, chars[i] == " " || chars[i] == "\t" || chars[i] == "\n" { i += 1 }
            return (" \(cc) ", true)
        }
        return (nil, i > start)
    }

    // MARK: - scanning helpers

    /// Splits a string on `separator` ignoring separators nested inside
    /// (), [], "", or '' — so `:not(a, b)` stays one selector.
    private static func splitTopLevel(_ string: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for c in string {
            if let q = quote {
                current.append(c)
                if c == q { quote = nil }
                continue
            }
            switch c {
            case "\"", "'": quote = c; current.append(c)
            case "(", "[": depth += 1; current.append(c)
            case ")", "]": depth = max(0, depth - 1); current.append(c)
            case separator where depth == 0: parts.append(current); current = ""
            default: current.append(c)
            }
        }
        parts.append(current)
        return parts
    }

    /// Given `chars[openBraceAt] == "{"`, returns the inner content (between the
    /// outer braces) and the index just past the matching `}`.
    private static func captureBlock(_ chars: [Character], openBraceAt start: Int) -> (inner: String, next: Int) {
        let n = chars.count
        var i = start + 1
        var depth = 1
        var inner = ""
        while i < n {
            let c = chars[i]
            if c == "/", i + 1 < n, chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < n, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = min(j + 2, n)
                inner += String(chars[i..<j]); i = j; continue
            }
            if c == "\"" || c == "'" {
                let end = indexAfterString(chars, openingAt: i)
                inner += String(chars[i..<end]); i = end; continue
            }
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return (inner, i + 1) }
            }
            inner.append(c)
            i += 1
        }
        return (inner, n) // unbalanced — consume the rest
    }

    /// Given `chars[openingAt]` is a quote, returns the index just past the
    /// matching close quote (honoring `\` escapes).
    private static func indexAfterString(_ chars: [Character], openingAt start: Int) -> Int {
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
}
