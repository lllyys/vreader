// Purpose: Feature #96 WI-1 — the testable seam for diagnostics capture. The
// store depends on this protocol; production wires `OSLogDiagnosticsSource`,
// tests inject a mock that returns canned entries (so the store/redact/export
// logic is verified without touching the real OS log).
//
// @coordinates-with: OSLogDiagnosticsSource.swift, DiagnosticsLogStore.swift

import Foundation

/// Supplies recent diagnostics entries. `Sendable` so the `@MainActor` store can
/// hold `any DiagnosticsLogSource` and `await` it off-main (the real OSLog
/// enumeration is synchronous + blocking — it must NOT run on the main actor).
protocol DiagnosticsLogSource: Sendable {
    /// Returns up to `limit` recent entries, optionally bounded to `since`.
    /// Ordered oldest→newest. Throws on a source failure (the store treats a
    /// throw as "no entries available" — a normal runtime outcome, not a crash).
    func recentEntries(since: Date?, limit: Int) async throws -> [DiagnosticsLogEntry]
}
