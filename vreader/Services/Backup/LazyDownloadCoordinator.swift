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
    let totalBytes: Int64
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

    init() {}

    // MARK: - Delegate event handlers

    /// Called from `LazyDownloadDelegate` after hopping to MainActor.
    func didProgress(fingerprintKey: String, bytesWritten: Int64, totalBytes: Int64) {
        progressByKey[fingerprintKey] = LazyDownloadProgress(
            fingerprintKey: fingerprintKey,
            bytesWritten: bytesWritten,
            totalBytes: totalBytes
        )
    }

    /// Called when the download body finished and was moved to `stagedURL`.
    /// The coordinator records the outcome; downstream WIs (4a) call into
    /// `BookFileImportFinalizer` to verify SHA-256 + import via BookImporter.
    func didFinishDownload(fingerprintKey: String, meta: LazyDownloadTaskMeta, stagedURL: URL) {
        progressByKey.removeValue(forKey: fingerprintKey)
        outcomes[fingerprintKey] = .completed(
            fingerprintKey: fingerprintKey,
            stagedURL: stagedURL
        )
        log.info(
            "didFinishDownload: \(fingerprintKey, privacy: .public) → \(stagedURL.lastPathComponent, privacy: .public)"
        )
    }

    /// Called when the download failed (network, server, move-to-staging,
    /// etc.). Records the outcome so the row's UI can surface a retry CTA.
    func didFinishDownloadFailed(fingerprintKey: String, reason: String) {
        progressByKey.removeValue(forKey: fingerprintKey)
        outcomes[fingerprintKey] = .failed(
            fingerprintKey: fingerprintKey,
            reason: reason
        )
        log.error(
            "didFinishDownloadFailed: \(fingerprintKey, privacy: .public) — \(reason, privacy: .public)"
        )
    }

    // MARK: - Test/UI helpers

    /// Clears the outcome for a fingerprintKey (typically after the UI
    /// renders the new state once).
    func clearOutcome(for fingerprintKey: String) {
        outcomes.removeValue(forKey: fingerprintKey)
    }

    /// Test seam — wipes all coordinator state. Production never calls this.
    func reset() {
        progressByKey = [:]
        outcomes = [:]
    }
}
