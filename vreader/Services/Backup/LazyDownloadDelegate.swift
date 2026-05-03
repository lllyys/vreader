// Purpose: URLSessionDownloadDelegate that receives lazy-blob-download
// callbacks from a background URLSession and forwards events to a
// MainActor-isolated LazyDownloadCoordinator. Nonisolated by design —
// URLSession's delegate callbacks fire on a background queue and Swift 6
// strict concurrency forbids @MainActor delegate conformance.
//
// Pattern: this object is a lightweight adapter. It holds a weak reference
// to the coordinator (so the delegate doesn't outlive the coordinator) and
// hops to MainActor via `Task { @MainActor in ... }` to deliver each event.
//
// Feature #47 WI-3a.
//
// @coordinates-with: LazyDownloadCoordinator.swift, LazyDownloadTaskMeta.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "LazyDownloadDelegate")

final class LazyDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// Weak so the delegate doesn't outlive the MainActor coordinator that
    /// owns it. URLSession retains the delegate until the session is
    /// invalidated; clearing this back-pointer means lifecycle events that
    /// arrive after coordinator teardown are dropped silently. Mutated only
    /// during one-time setup before the URLSession starts dispatching
    /// callbacks (the @unchecked Sendable conformance documents that
    /// invariant — WI-3b will narrow to a locked weak box if needed).
    weak var coordinator: LazyDownloadCoordinator?

    // MARK: - URLSessionDownloadDelegate

    /// Per-byte progress. Forwarded to coordinator's MainActor surface.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let meta = LazyDownloadTaskMeta.decode(fromTaskDescription: downloadTask.taskDescription) else {
            handleOrphan(task: downloadTask, stage: "didWriteData")
            return
        }
        Task { @MainActor [weak coordinator] in
            coordinator?.didProgress(
                fingerprintKey: meta.fingerprintKey,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
            )
        }
    }

    /// Download finished — temp file is at `location`. Coordinator must
    /// move it to a stable spot synchronously (URLSession deletes the temp
    /// file after this call returns), so we hop to MainActor and forward
    /// the staged URL the coordinator already moved the bytes to.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let meta = LazyDownloadTaskMeta.decode(fromTaskDescription: downloadTask.taskDescription) else {
            handleOrphan(task: downloadTask, stage: "didFinishDownloadingTo")
            // URLSession deletes `location` after we return — nothing to
            // recover from here without metadata.
            return
        }
        // URLSession deletes `location` after this method returns. We must
        // move it synchronously OFF this delegate queue. Use a per-task
        // unique destination so concurrent downloads or retries don't
        // collide on the same staged file.
        let staged = LazyDownloadDelegate.stagedTempURL(for: meta, taskIdentifier: downloadTask.taskIdentifier)
        do {
            try FileManager.default.createDirectory(
                at: staged.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Replace any leftover from a prior partial run with the same
            // taskIdentifier (rare — URLSession reuses identifiers within a
            // session lifetime).
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            // Move failed — flip the row to .failed via the coordinator.
            Task { @MainActor [weak coordinator] in
                coordinator?.didFinishDownloadFailed(
                    fingerprintKey: meta.fingerprintKey,
                    reason: "move-from-tmp: \(error.localizedDescription)"
                )
            }
            return
        }
        Task { @MainActor [weak coordinator] in
            coordinator?.didFinishDownload(
                fingerprintKey: meta.fingerprintKey,
                meta: meta,
                stagedURL: staged
            )
        }
    }

    /// Called by URLSession when all background events for the session
    /// have been delivered. Forwards to the coordinator if alive, but
    /// ALWAYS invokes the stored UIApplicationDelegate completion
    /// handler — iOS will not release the app's background-launch grace
    /// period until that handler runs, even if the coordinator was
    /// torn down (test harness, app shutting down, etc.).
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier ?? ""
        Task { @MainActor [weak coordinator] in
            if let coordinator {
                coordinator.didFinishBackgroundEvents(sessionIdentifier: identifier)
            } else {
                // Coordinator is gone — invoke the AppDelegate handler
                // directly so iOS doesn't leak the grace period.
                VReaderAppDelegate.takeBackgroundHandler(for: identifier)?()
            }
        }
    }

    /// Task completed (success or error). Errors here mean the task itself
    /// failed (network, server 4xx/5xx, cancelled).
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask else { return }
        guard let meta = LazyDownloadTaskMeta.decode(fromTaskDescription: downloadTask.taskDescription) else {
            if error != nil {
                handleOrphan(task: downloadTask, stage: "didCompleteWithError")
            }
            return
        }
        if let error {
            Task { @MainActor [weak coordinator] in
                coordinator?.didFinishDownloadFailed(
                    fingerprintKey: meta.fingerprintKey,
                    reason: error.localizedDescription
                )
            }
        }
        // Success path is handled by didFinishDownloadingTo above; nothing
        // to do here when error is nil.
    }

    // MARK: - Helpers

    /// Deterministic-per-task staging URL. Lives under
    /// Caches/LazyDownloads/. Includes the URLSession `taskIdentifier` so
    /// concurrent downloads of the same blob (or a retry while a previous
    /// staged file is awaiting finalization) don't collide on disk. The
    /// SHA-256 + byte-count are still in the name so import-time verification
    /// can recover the expected identity from the staged path alone.
    static func stagedTempURL(for meta: LazyDownloadTaskMeta, taskIdentifier: Int) -> URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LazyDownloads", isDirectory: true)
        // Metadata fields were validated at decode time
        // (LazyDownloadTaskMeta.decode), so `expectedSHA256` is 64 hex chars
        // and `originalExtension` is alnum-only — safe to interpolate.
        return dir
            .appendingPathComponent("\(meta.expectedSHA256)_\(meta.expectedByteCount)_\(taskIdentifier)")
            .appendingPathExtension(meta.originalExtension)
    }

    /// Cancels and logs an orphaned task (one whose `taskDescription` is
    /// missing or fails the schema/format gate). The delegate cannot
    /// surface a coordinator failure event without a fingerprintKey — WI-3b
    /// will reattach orphans via `getAllTasks()` at relaunch and flip the
    /// matching row to .failed there.
    private func handleOrphan(task: URLSessionDownloadTask, stage: String) {
        log.error(
            "orphaned task at \(stage, privacy: .public) — id=\(task.taskIdentifier, privacy: .public), cancelling"
        )
        task.cancel()
    }
}
