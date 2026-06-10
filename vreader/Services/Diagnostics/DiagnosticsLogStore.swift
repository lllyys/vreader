// Purpose: Feature #96 WI-1 — the UI-facing diagnostics store. Loads recent
// current-session entries via an injected `DiagnosticsLogSource` (off-main),
// holds them for a viewer to bind to (WI-2, design-blocked), supports pure
// level/category filtering, and produces a REDACTED export string.
//
// Key decisions:
// - `@MainActor @Observable` (Gate-2 Medium): the store owns UI state on the main
//   actor; the blocking OSLog enumeration lives in the nonisolated source, so
//   `load` just `await`s it and publishes the result.
// - Bounded: `load(limit:)` caps the fetch; a `maxEntries` window trims what's held.
// - `exportText()` runs EVERY message through `DiagnosticsRedactor` — the
//   export-leak guard.
//
// @coordinates-with: DiagnosticsLogSource.swift, DiagnosticsRedactor.swift,
//   DiagnosticsLogEntry.swift

import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsLogStore {
    /// The single source of truth for the human capture-window label, used by
    /// BOTH the export header and the viewer footer so they never diverge.
    /// WI-1 reads `OSLogStore(scope: .currentProcessIdentifier)` — the current
    /// process's entries, NOT a rolling time window — so "this session" is the
    /// ACCURATE descriptor. It deliberately supersedes the #1597 design mock's
    /// illustrative "last 24 h", which assumed the time-bounded store WI-1's
    /// Gate-2 scope correction removed (see the plan's revision history).
    static let captureScopeLabel = "this session"

    /// Entries currently held (oldest→newest), already bounded.
    private(set) var entries: [DiagnosticsLogEntry] = []
    /// True once a load has completed at least once (drives an empty-vs-unloaded
    /// distinction for the viewer).
    private(set) var hasLoaded = false

    private let source: DiagnosticsLogSource
    private let maxEntries: Int

    init(source: DiagnosticsLogSource = OSLogDiagnosticsSource(), maxEntries: Int = 2000) {
        self.source = source
        self.maxEntries = max(1, maxEntries)
    }

    /// Loads recent entries. A throwing/empty source yields an empty list (a
    /// normal runtime outcome — never a crash). `since` bounds the time window.
    func load(since: Date? = nil, limit: Int? = nil) async {
        // Gate-4 Medium: clamp to a non-negative cap — a negative `limit` would
        // reach `Array.suffix(_:)` in the source and trap.
        let cap = max(0, min(limit ?? maxEntries, maxEntries))
        let fetched = (try? await source.recentEntries(since: since, limit: cap)) ?? []
        entries = fetched.count > maxEntries ? Array(fetched.suffix(maxEntries)) : fetched
        hasLoaded = true
    }

    /// Pure filter — entries matching the given level (nil = any) and category
    /// (nil/empty = any). Does not mutate `entries`.
    func filtered(level: DiagnosticsLevel? = nil, category: String? = nil) -> [DiagnosticsLogEntry] {
        entries.filter { e in
            (level == nil || e.level == level)
                && (category == nil || category!.isEmpty || e.category == category)
        }
    }

    /// The distinct categories present, sorted — drives the viewer's category filter.
    var categories: [String] {
        Array(Set(entries.map(\.category))).filter { !$0.isEmpty }.sorted()
    }

    /// A redacted, shareable plain-text dump. Every message is scrubbed by
    /// `DiagnosticsRedactor` (defense-in-depth over the OSLog `.private` barrier).
    /// `filter` (level/category) narrows the export to match the viewer.
    func exportText(level: DiagnosticsLevel? = nil, category: String? = nil) -> String {
        exportText(entries: filtered(level: level, category: category))
    }

    /// Formats + redacts an explicit entry list. The viewer passes its own
    /// already-filtered list here so a multi-level filter (the "Errors" chip =
    /// `{.error, .fault}`) exports exactly what's on screen — the single
    /// `level:` predicate above can't express that set.
    func exportText(entries rows: [DiagnosticsLogEntry]) -> String {
        var lines = ["vreader diagnostics — \(rows.count) entr\(rows.count == 1 ? "y" : "ies") (\(Self.captureScopeLabel))"]
        let fmt = ISO8601DateFormatter()
        for e in rows {
            let cat = e.category.isEmpty ? "" : " (\(e.category))"
            lines.append("\(fmt.string(from: e.date)) [\(e.level.exportTag)]\(cat) \(DiagnosticsRedactor.redact(e.message))")
        }
        return lines.joined(separator: "\n")
    }
}
