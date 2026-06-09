// Purpose: Feature #96 WI-1 — defense-in-depth secret scrubbing for EXPORTED
// diagnostics. Pure + exhaustively unit-tested — the export-leak guard.
//
// Threat model (Gate-2 High): the FIRST-line barrier is OSLog `privacy:`
// annotations — `.private` interpolations are already `<private>` in the
// read-back and cannot be recovered. This redactor is the SECOND line for
// content logged `.public`, static strings that embed a secret, or error
// descriptions / URLs / paths that were never privacy-tagged.
//
// Strategy (Gate-2 Medium): CONTEXT-DRIVEN — redact known auth contexts +
// well-known secret shapes + filesystem paths. It deliberately does NOT
// blanket-redact long hex/base64 runs (that over-redacts hashes / ids), and a
// keychain ACCOUNT LABEL (`com.vreader.ai.apiKey.<UUID>`) is an identifier, not
// the secret, so it is left intact.
//
// @coordinates-with: DiagnosticsLogStore.swift

import Foundation

/// Scrubs secrets + filesystem paths from a log message before export.
enum DiagnosticsRedactor {
    static let placeholder = "‹redacted›"
    static let pathPlaceholder = "‹path›"

    /// Redacts `message` for safe export. Idempotent.
    static func redact(_ message: String) -> String {
        var out = message
        for rule in rules {
            out = rule.apply(out)
        }
        return out
    }

    // MARK: - Rules (applied in order)

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
        func apply(_ s: String) -> String {
            let range = NSRange(s.startIndex..., in: s)
            return regex.stringByReplacingMatches(
                in: s, range: range, withTemplate: template)
        }
    }

    private static let rules: [Rule] = {
        // group $1 = the keep-prefix (key name / scheme), redacted value dropped.
        func r(_ pattern: String, _ template: String) -> Rule? {
            guard let re = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return Rule(regex: re, template: template)
        }
        let p = placeholder
        let path = pathPlaceholder
        // The secret-key alternation, reused by the quoted + unquoted rules.
        let keys = #"(?:x-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|token|password|secret)"#
        return [
            // Authorization: Bearer/Basic <token> — quoted OR unquoted key, `:` or
            // `=`, optional surrounding quotes; consume the value to a quote / comma
            // / brace / newline (Gate-4 High: serialized "Authorization":"Basic …" shapes).
            r(#"(["']?Authorization["']?\s*[:=]\s*["']?(?:Bearer|Basic)\s+)[^"'\n,}]+"#, "$1\(p)"),
            // Keyed secrets, QUOTED value — consume to the CLOSING quote so a value
            // with whitespace/newlines is fully redacted (Gate-4 High).
            r(#"(["']?\#(keys)["']?\s*[:=]\s*")[^"]*(")"#, "$1\(p)$2"),
            // Keyed secrets, UNQUOTED value (query / kv form).
            r(#"(["']?\#(keys)["']?\s*[:=]\s*)[^\s"',&}]+"#, "$1\(p)"),
            // OpenAI-style keys: sk-… (and sk-proj-…)
            r(#"\bsk-[A-Za-z0-9_-]{12,}"#, p),
            // JWT: three base64url segments
            r(#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, p),
            // URL credentials: scheme://user:pass@host -> scheme://user:‹redacted›@host
            r(#"(\b[a-z][a-z0-9+.-]*://[^\s:/@]+:)[^\s@/]+(@)"#, "$1\(p)$2"),
            // file:// URLs
            r(#"file://[^\s"',)]+"#, path),
            // Filesystem paths — consume the WHOLE path incl. internal spaces
            // (`Application Support`) up to a quote / comma / paren / newline, so the
            // path TAIL never leaks (Gate-4 Medium). Over-redacting a trailing benign
            // word is the safe direction.
            r(#"/(?:private/var/mobile/Containers|var/mobile|Users)/[^"'\n,)]*"#, path),
        ].compactMap { $0 }
    }()
}
