// Purpose: Feature #96 WI-1 — the production `DiagnosticsLogSource` that reads
// the app's OWN current-process `Logger` entries back via `OSLogStore`.
//
// Key decisions:
// - Scope `.currentProcessIdentifier` → CURRENT SESSION only (Gate-2 Critical:
//   it does NOT read prior launches / a pre-crash trail). That serves the
//   "view this run's runtime context" need; cross-launch forensics is out of scope.
// - `nonisolated` / off-main (Gate-2 Medium): `OSLogStore.getEntries` enumeration
//   is synchronous + blocking, so it runs on a background executor (the `async`
//   protocol method hops off the caller's actor). No entitlement is required for
//   `.currentProcessIdentifier` on iOS (target 17.0).
// - Retrieval contract: `OSLogStore(scope:)` → `position(date:)` → `getEntries(
//   with:at:matching:)` with a `subsystem == "com.vreader.app"` predicate →
//   `compactMap { $0 as? OSLogEntryLog }` (the only entry type carrying level +
//   category + composedMessage).
//
// @coordinates-with: DiagnosticsLogSource.swift, DiagnosticsLogStore.swift

import Foundation
import OSLog

/// Reads the app's own current-process log via `OSLogStore`. The OS boundary —
/// mocked behind `DiagnosticsLogSource` in tests; not unit-tested here.
struct OSLogDiagnosticsSource: DiagnosticsLogSource {
    /// The subsystem every vreader `Logger` uses (rule 50 §7).
    static let subsystem = "com.vreader.app"

    func recentEntries(since: Date?, limit: Int) async throws -> [DiagnosticsLogEntry] {
        guard limit > 0 else { return [] }   // defensive — never `suffix(<0)` downstream
        // Hop off any caller actor — the enumeration below is blocking.
        return try await Task.detached(priority: .utility) {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = since.map { store.position(date: $0) }
            let predicate = NSPredicate(format: "subsystem == %@", Self.subsystem)
            let entries = try store.getEntries(
                with: [], at: position, matching: predicate)
            // `getEntries` yields oldest→newest; keep a rolling window of the most
            // recent `limit` so we don't accumulate the entire stream (Gate-4 Low).
            var window: [DiagnosticsLogEntry] = []
            window.reserveCapacity(limit)
            for case let log as OSLogEntryLog in entries {
                window.append(DiagnosticsLogEntry(
                    date: log.date,
                    level: DiagnosticsLevel(log.level),
                    category: log.category,
                    message: log.composedMessage))
                if window.count > limit { window.removeFirst(window.count - limit) }
            }
            return window
        }.value
    }
}
