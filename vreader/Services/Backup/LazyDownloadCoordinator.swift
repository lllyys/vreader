// Purpose: MainActor-isolated coordinator for lazy book-blob downloads
// triggered by user tap on a `.remoteOnly` library row. Receives progress
// + completion events from a non-isolated `LazyDownloadDelegate` and
// updates @Observable state that SwiftUI views can render.
//
// Feature #47 WI-3a — skeleton. WI-3b adds lifecycle persistence
// (taskDescription mapping, getAllTasks reattach, crash recovery).
// WI-3c adds WebDAVNetworkPolicy for Wi-Fi-only gating.
//
// @coordinates-with: LazyDownloadDelegate.swift, LazyDownloadTaskMeta.swift,
//   BookFileImportFinalizer.swift (future, WI-4a),
//   WebDAVDownloadRequestBuilder.swift (future, request construction),
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation
import OSLog
import Observation

private let log = Logger(subsystem: "com.vreader.app", category: "LazyDownloadCoordinator")

/// Per-fingerprintKey progress + outcome state observed by SwiftUI rows.
struct LazyDownloadProgress: Sendable, Equatable {
    let fingerprintKey: String
    let bytesWritten: Int64
    /// nil when URLSession reports `NSURLSessionTransferSizeUnknown` (-1).
    /// UI surfaces an indeterminate spinner in that case.
    let totalBytes: Int64?
}

/// Completion outcome surfaced to UI consumers.
enum LazyDownloadOutcome: Sendable, Equatable {
    case completed(fingerprintKey: String, stagedURL: URL)
    case failed(fingerprintKey: String, reason: String)
}

/// Receives forwarded events from `LazyDownloadDelegate` (which fires on a
/// background queue) and exposes @Observable state to SwiftUI rows. WI-3a
/// scope: skeleton — captures progress + outcome but doesn't yet integrate
/// with `BookFileState` persistence (WI-3b) or trigger import/finalization
/// (WI-4a's `BookFileImportFinalizer`).
@MainActor
@Observable
final class LazyDownloadCoordinator {

    /// Active progress per fingerprintKey. SwiftUI rows read this to draw
    /// the inline progress bar / spinner.
    private(set) var progressByKey: [String: LazyDownloadProgress] = [:]

    /// Most recent outcome per fingerprintKey. Cleared by callers when the
    /// row's UI acknowledges the result (e.g., showing the new state for a
    /// frame and then forgetting the outcome).
    private(set) var outcomes: [String: LazyDownloadOutcome] = [:]

    /// Sticky terminal-state guard. Survives `clearOutcome(for:)` so a
    /// stale `didWriteData` callback that lands after the UI has already
    /// dismissed the outcome can't resurrect `progressByKey`. Cleared only
    /// by `prepareToDownload(fingerprintKey:)` — called by the enqueue
    /// path before a fresh download starts — or by `reset()`. Concurrency
    /// scoping note: the coordinator assumes a single in-flight download
    /// per fingerprintKey at a time. Serialising enqueue is WI-4a's job
    /// (`BookFileImportFinalizer` / `SelectiveRestoreCoordinator`).
    private(set) var terminalKeys: Set<String> = []

    init() {}

    // MARK: - Delegate event handlers

    /// Called from `LazyDownloadDelegate` after hopping to MainActor.
    /// Ignores progress events that arrive after a terminal event for the
    /// same key — the delegate hops to MainActor via independent Tasks so
    /// a stale didWriteData callback can land after didFinish, and the
    /// `terminalKeys` guard outlives `clearOutcome(for:)` so a UI dismissal
    /// of the outcome doesn't reopen the door for the stale event.
    func didProgress(fingerprintKey: String, bytesWritten: Int64, totalBytes: Int64) {
        if terminalKeys.contains(fingerprintKey) { return }
        let total: Int64? = (totalBytes >= 0) ? totalBytes : nil
        progressByKey[fingerprintKey] = LazyDownloadProgress(
            fingerprintKey: fingerprintKey,
            bytesWritten: bytesWritten,
            totalBytes: total
        )
    }

    /// Called when the download body finished and was moved to `stagedURL`.
    /// The coordinator records the outcome; downstream WIs (4a) call into
    /// `BookFileImportFinalizer` to verify SHA-256 + import via BookImporter.
    /// Ignored if the key already has a terminal outcome.
    func didFinishDownload(fingerprintKey: String, meta: LazyDownloadTaskMeta, stagedURL: URL) {
        if terminalKeys.contains(fingerprintKey) { return }
        progressByKey.removeValue(forKey: fingerprintKey)
        terminalKeys.insert(fingerprintKey)
        outcomes[fingerprintKey] = .completed(
            fingerprintKey: fingerprintKey,
            stagedURL: stagedURL
        )
        log.info(
            "didFinishDownload: \(fingerprintKey, privacy: .private) → \(stagedURL.lastPathComponent, privacy: .private)"
        )
    }

    /// Called when the download failed (network, server, move-to-staging,
    /// etc.). Records the outcome so the row's UI can surface a retry CTA.
    /// Ignored if the key already has a terminal outcome.
    func didFinishDownloadFailed(fingerprintKey: String, reason: String) {
        if terminalKeys.contains(fingerprintKey) { return }
        progressByKey.removeValue(forKey: fingerprintKey)
        terminalKeys.insert(fingerprintKey)
        outcomes[fingerprintKey] = .failed(
            fingerprintKey: fingerprintKey,
            reason: reason
        )
        log.error(
            "didFinishDownloadFailed: \(fingerprintKey, privacy: .private) — \(reason, privacy: .private)"
        )
    }

    // MARK: - Test/UI helpers

    /// Clears the outcome for a fingerprintKey (typically after the UI
    /// renders the new state once). Does NOT clear the terminal-state
    /// guard — a stale `didWriteData` callback that lands after the UI
    /// has already dismissed the outcome must still be ignored.
    func clearOutcome(for fingerprintKey: String) {
        outcomes.removeValue(forKey: fingerprintKey)
    }

    /// Called by the enqueue path before a fresh download for `key` starts
    /// (e.g., after the user taps Retry on a failed row). Clears any
    /// outcome and the terminal-state guard so subsequent progress events
    /// are accepted again. WI-3a doesn't ship the enqueue path yet — this
    /// hook is the seam WI-4a will call from the request builder.
    func prepareToDownload(fingerprintKey: String) {
        outcomes.removeValue(forKey: fingerprintKey)
        terminalKeys.remove(fingerprintKey)
        progressByKey.removeValue(forKey: fingerprintKey)
    }

    /// Test seam — wipes all coordinator state. Production never calls this.
    func reset() {
        progressByKey = [:]
        outcomes = [:]
        terminalKeys = []
    }
}
