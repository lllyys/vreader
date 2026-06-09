// Purpose: Feature #96 WI-1 — value type for one captured diagnostics log entry,
// read back from the app's own OSLog `Logger` output (subsystem com.vreader.app).
//
// Key decisions:
// - `DiagnosticsLevel` MIRRORS `OSLogEntryLog.Level` exactly (undefined/debug/info/
//   notice/error/fault). Gate-2 High: Swift `Logger.warning()` compiles down to
//   `.error` in the SDK, so a distinct "warning" level is NOT recoverable from
//   historical entries — we don't invent one.
// - Pure value type (`Sendable`, `Equatable`), decoupled from `OSLogEntry` so the
//   store + tests never touch the OS type directly.
//
// @coordinates-with: DiagnosticsLogSource.swift, OSLogDiagnosticsSource.swift,
//   DiagnosticsLogStore.swift

import Foundation
import OSLog

/// Severity of a captured entry — mirrors `OSLogEntryLog.Level` 1:1.
enum DiagnosticsLevel: String, Sendable, Equatable, CaseIterable {
    case undefined
    case debug
    case info
    case notice
    case error
    case fault

    /// Maps an OS level into our mirror. `Logger.warning()` reads back as `.error`
    /// (SDK behavior) — there is no `warning` case to map to.
    init(_ osLevel: OSLogEntryLog.Level) {
        switch osLevel {
        case .undefined: self = .undefined
        case .debug:     self = .debug
        case .info:      self = .info
        case .notice:    self = .notice
        case .error:     self = .error
        case .fault:     self = .fault
        @unknown default: self = .undefined
        }
    }

    /// Short uppercase tag for the export line (`[ERROR]`, `[INFO]`, …).
    var exportTag: String { rawValue.uppercased() }
}

/// One captured diagnostics entry.
struct DiagnosticsLogEntry: Sendable, Equatable {
    let date: Date
    let level: DiagnosticsLevel
    /// The `Logger` category (e.g. "Library", "Persistence"). Empty when absent.
    let category: String
    /// The composed message. `.private` interpolations arrive already redacted to
    /// `<private>` by the OS; `.public`/untagged content is scrubbed by
    /// `DiagnosticsRedactor` on export.
    let message: String
}
