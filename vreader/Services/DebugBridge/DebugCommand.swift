// Purpose: Parser and value type for the vreader-debug:// URL grammar
// (feature #44 DebugBridge). Pure value-type parsing, no OS dependencies.
// DEBUG-only — entire file compiled out of Release builds.

#if DEBUG

import Foundation

/// A command parsed from a `vreader-debug://` URL.
///
/// Grammar: `vreader-debug://<command>[?<params>]`
///
/// - `reset` — wipe library and reset settings.
/// - `seed?fixture=<name>` — seed a bundled fixture book.
/// - `open?bookId=<uuid>[&position=<value>]` — open a book at an optional
///   position. Position format depends on the book format; a future feature
///   #49 WI ships a `DebugPositionResolver` for native-mode TXT/EPUB/PDF.
///   The legacy `?cfi=<value>` parameter is rejected — feature #49 WI-0
///   reconciled the grammar to use `position` consistently across all formats.
/// - `theme?mode=<dark|light|paper|sepia|oled|photo>[&fontSize=<int>]` — set the
///   reader appearance. `light` is a backward-compatible alias for `paper`.
/// - `settle?token=<id>` — write `Caches/ready-<id>.json` after layout settles.
/// - `snapshot?dest=<file>` — write semantic state JSON to the app container.
/// - `eval?bridge=<name>&js=<base64>` — evaluate JS in the named webview bridge.
/// - `tts?action=<start|stop>` — drive TTS from outside the reader (Feature #45
///   WI-4c-b). XCUITest's gesture path cannot reliably activate
///   `AVSpeechSynthesizer`'s audio session, so verification tests fire this URL
///   after opening a book to bypass the play-button tap.
/// - `search?query=<str>[&index=<int>]` — drive the in-reader search sheet
///   (Bug #238 verification harness). `query` opens the search sheet and runs
///   the query; the optional `index` (0-indexed, ≥0) taps result N once
///   results arrive. The harness uses this to drive search-result-tap repros
///   (e.g. Bug #182 cross-chapter EPUB search highlight verification) without
///   computer-use. No-op when no reader is presented.
/// - `highlight?start=<int>&end=<int>[&color=<name>]` — create a highlight
///   over a UTF-16 range in the active TXT/MD reader (Bug #237 verification
///   harness). The harness uses this to bypass the long-press +
///   `SelectionPopoverView` gesture, which XCUITest cannot synthesize
///   reliably on iOS 26. `start` < `end` (inclusive-exclusive), both
///   non-negative. `color` is optional; one of `NamedHighlightColor`'s four
///   rawValues (`yellow` / `pink` / `green` / `blue`). No-op when no reader
///   is presented.
enum DebugCommand: Equatable {
    case reset
    case seed(fixture: String)
    case open(bookId: String, position: String?)
    case theme(mode: ThemeMode, fontSize: Int?)
    case settle(token: String)
    case snapshot(dest: String)
    case eval(bridge: String, js: String)
    case tts(action: String)
    case search(query: String, index: Int?)
    case highlight(startUTF16: Int, endUTF16: Int, color: String?)

    /// Reader theme selector for the `theme` command.
    ///
    /// Feature #60 WI-11 migrated the reader to `ReaderThemeV2`'s
    /// 5-theme palette (paper / sepia / dark / oled / photo). `light`
    /// is retained as a backward-compatible alias for `paper` so older
    /// `mode=light` callers and verification scripts keep working.
    enum ThemeMode: String, Equatable, CaseIterable {
        case dark
        case light
        case paper
        case sepia
        case oled
        case photo
    }
}

/// Errors produced by `DebugCommand.parse(_:)`.
enum DebugCommandError: Error, Equatable {
    case invalidScheme
    case unknownCommand(String)
    case missingParam(String)
    case invalidParam(String, reason: String)
}

extension DebugCommand {

    /// Expected URL scheme. The URL host names the command.
    static let scheme = "vreader-debug"

    /// Parse a URL into a `DebugCommand`, or throw a `DebugCommandError`.
    ///
    /// Validates scheme, command name, and required/typed parameters. Empty-string
    /// values for required params are treated as missing.
    static func parse(_ url: URL) throws -> DebugCommand {
        guard url.scheme == scheme else {
            throw DebugCommandError.invalidScheme
        }
        guard let host = url.host, !host.isEmpty else {
            throw DebugCommandError.unknownCommand("")
        }
        // A test-control URL has no meaningful path. Reject `vreader-debug://settle/extra/path?token=x`
        // so a typo never silently dispatches the wrong command.
        guard url.path.isEmpty || url.path == "/" else {
            throw DebugCommandError.unknownCommand(host)
        }
        let params = try queryParams(url)

        switch host {
        case "reset":
            return .reset

        case "seed":
            let fixture = try requireParam("fixture", in: params)
            return .seed(fixture: fixture)

        case "open":
            let bookId = try requireParam("bookId", in: params)
            // Parameter is named `position` to match the documented grammar
            // and the public `DebugCommand.open(bookId:position:)` shape.
            // Reject the legacy `cfi` parameter explicitly so any caller still
            // using the old grammar gets a clear error rather than silently
            // opening at the start (feature #49 WI-0 grammar reconciliation).
            if params["cfi"] != nil {
                throw DebugCommandError.invalidParam(
                    "cfi",
                    reason: "Use 'position' — 'cfi' was renamed in feature #49 WI-0 grammar reconciliation"
                )
            }
            let position = nonEmpty(params["position"])
            return .open(bookId: bookId, position: position)

        case "theme":
            let modeRaw = try requireParam("mode", in: params)
            guard let mode = ThemeMode(rawValue: modeRaw) else {
                let valid = ThemeMode.allCases.map(\.rawValue).joined(separator: "|")
                throw DebugCommandError.invalidParam("mode", reason: "expected \(valid), got \(modeRaw)")
            }
            let fontSize: Int?
            if let raw = nonEmpty(params["fontSize"]) {
                guard let parsed = Int(raw) else {
                    throw DebugCommandError.invalidParam("fontSize", reason: "expected integer, got \(raw)")
                }
                fontSize = parsed
            } else {
                fontSize = nil
            }
            return .theme(mode: mode, fontSize: fontSize)

        case "settle":
            let token = try requireParam("token", in: params)
            try validateBasename(token, paramName: "token")
            return .settle(token: token)

        case "snapshot":
            let dest = try requireParam("dest", in: params)
            try validateBasename(dest, paramName: "dest")
            return .snapshot(dest: dest)

        case "eval":
            let bridge = try requireParam("bridge", in: params)
            // bridge becomes a filename ("eval-<bridge>.json"); validate as
            // a basename to prevent path traversal in the eval output path.
            try validateBasename(bridge, paramName: "bridge")
            let encoded = try requireParam("js", in: params)
            guard let data = Data(base64Encoded: encoded),
                  let js = String(data: data, encoding: .utf8) else {
                throw DebugCommandError.invalidParam("js", reason: "not valid base64-encoded UTF-8")
            }
            return .eval(bridge: bridge, js: js)

        case "tts":
            let action = try requireParam("action", in: params)
            // Restrict to the documented action set so typos surface as
            // invalidParam (not as silent no-ops in the dispatcher).
            guard action == "start" || action == "stop" else {
                throw DebugCommandError.invalidParam(
                    "action",
                    reason: "expected start|stop, got \(action)"
                )
            }
            return .tts(action: action)

        case "search":
            // Bug #238: verification harness search-driver. `query` opens
            // the search sheet + runs the query; optional `index` (0-indexed,
            // ≥0) taps result N. `index` without `query` is rejected — they
            // go together (the harness cannot meaningfully tap a result
            // before running a query). The empty-value rejection on `index`
            // matches `requireParam`'s posture on the other commands.
            let query = try requireParam("query", in: params)
            let index: Int?
            if let rawIndex = params["index"] {
                guard !rawIndex.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "index",
                        reason: "expected non-negative integer, got empty value"
                    )
                }
                guard let parsed = Int(rawIndex) else {
                    throw DebugCommandError.invalidParam(
                        "index",
                        reason: "expected non-negative integer, got \(rawIndex)"
                    )
                }
                guard parsed >= 0 else {
                    throw DebugCommandError.invalidParam(
                        "index",
                        reason: "must be ≥ 0, got \(parsed)"
                    )
                }
                index = parsed
            } else {
                index = nil
            }
            return .search(query: query, index: index)

        case "highlight":
            // Bug #237: verification harness highlight-creator. Builds a
            // highlight over a UTF-16 range in the active TXT/MD reader,
            // bypassing the long-press + SelectionPopoverView gesture
            // (which XCUITest cannot synthesize on iOS 26). Range is
            // inclusive-exclusive (`[start, end)`), both non-negative,
            // start < end (a zero-length range is rejected — the user
            // gesture path requires `selectedRange.length > 0` too).
            // Color is optional; defaults to "yellow" downstream. When
            // present, must be one of NamedHighlightColor's four rawValues.
            let startRaw = try requireParam("start", in: params)
            guard let parsedStart = Int(startRaw) else {
                throw DebugCommandError.invalidParam(
                    "start",
                    reason: "expected non-negative integer, got \(startRaw)"
                )
            }
            guard parsedStart >= 0 else {
                throw DebugCommandError.invalidParam(
                    "start",
                    reason: "must be ≥ 0, got \(parsedStart)"
                )
            }
            let endRaw = try requireParam("end", in: params)
            guard let parsedEnd = Int(endRaw) else {
                throw DebugCommandError.invalidParam(
                    "end",
                    reason: "expected non-negative integer, got \(endRaw)"
                )
            }
            guard parsedEnd >= 0 else {
                throw DebugCommandError.invalidParam(
                    "end",
                    reason: "must be ≥ 0, got \(parsedEnd)"
                )
            }
            guard parsedEnd > parsedStart else {
                throw DebugCommandError.invalidParam(
                    "end",
                    reason: "must be > start (got start=\(parsedStart) end=\(parsedEnd))"
                )
            }
            let color: String?
            if let rawColor = params["color"] {
                guard !rawColor.isEmpty else {
                    throw DebugCommandError.invalidParam(
                        "color",
                        reason: "expected one of yellow|pink|green|blue, got empty value"
                    )
                }
                // Allowlist — NamedHighlightColor.rawValue cases (feature #60
                // WI-7c). Keeping the allowlist literal here rather than
                // referencing the type avoids a release/debug coupling
                // (parser is pure-value; presenter type lives elsewhere).
                let validColors: Set<String> = ["yellow", "pink", "green", "blue"]
                guard validColors.contains(rawColor) else {
                    throw DebugCommandError.invalidParam(
                        "color",
                        reason: "expected one of yellow|pink|green|blue, got \(rawColor)"
                    )
                }
                color = rawColor
            } else {
                color = nil
            }
            return .highlight(startUTF16: parsedStart, endUTF16: parsedEnd, color: color)

        default:
            throw DebugCommandError.unknownCommand(host)
        }
    }

    // MARK: - Helpers

    private static func queryParams(_ url: URL) throws -> [String: String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else {
            return [:]
        }
        var seen: Set<String> = []
        var out: [String: String] = [:]
        for item in items {
            // Reject duplicate keys explicitly. `?fixture=a&fixture=b` is almost always
            // a caller bug; silently using the last value masks it.
            if !seen.insert(item.name).inserted {
                throw DebugCommandError.invalidParam(item.name, reason: "duplicate parameter")
            }
            out[item.name] = item.value ?? ""
        }
        return out
    }

    private static func requireParam(_ name: String, in params: [String: String]) throws -> String {
        guard let raw = params[name], !raw.isEmpty else {
            throw DebugCommandError.missingParam(name)
        }
        return raw
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// Maximum length for filename-like parameters (`token`, `dest`).
    static let basenameMaxLength = 64

    /// Validate a parameter as a safe filename basename. The bridge writes
    /// real files with these values, so this is the right place to stop
    /// path traversal (`..`), separators (`/`), control characters, and
    /// dot-only sequences (`.`, `..`, `...`) before they reach the
    /// filesystem.
    ///
    /// Allowed: `[A-Za-z0-9._-]`, length 1..=64, with at least one char
    /// outside the dot-only set.
    private static func validateBasename(_ value: String, paramName: String) throws {
        guard value.count <= basenameMaxLength else {
            throw DebugCommandError.invalidParam(
                paramName,
                reason: "exceeds \(basenameMaxLength) characters"
            )
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw DebugCommandError.invalidParam(
                paramName,
                reason: "must match [A-Za-z0-9._-]"
            )
        }
        // Reject pure-dot sequences (".", "..", "...", etc.). They pass the
        // character-class check but trip path-traversal in any handler that
        // does `base.appendingPathComponent(value)`.
        if value.allSatisfy({ $0 == "." }) {
            throw DebugCommandError.invalidParam(
                paramName,
                reason: "dot-only basenames are not allowed"
            )
        }
    }
}

#endif
