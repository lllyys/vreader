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

final class LazyDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// Weak so the delegate doesn't outlive the MainActor coordinator that
    /// owns it. URLSession retains the delegate until the session is
    /// invalidated; clearing this back-pointer means lifecycle events that
    /// arrive after coordinator teardown are dropped silently.
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
        guard let meta = LazyDownloadTaskMeta.decode(fromTaskDescription: downloadTask.taskDescription) else { return }
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
        guard let meta = LazyDownloadTaskMeta.decode(fromTaskDescription: downloadTask.taskDescription) else { return }
        // URLSession deletes `location` after this method returns. We must
        // move it synchronously OFF this delegate queue. Use a per-task
        // deterministic destination based on the SHA-256 so concurrent
        // moves don't collide.
        let staged = LazyDownloadDelegate.stagedTempURL(for: meta)
        do {
            try FileManager.default.createDirectory(
                at: staged.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Replace any leftover from a prior partial run.
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

    /// Task completed (success or error). Errors here mean the task itself
    /// failed (network, server 4xx/5xx, cancelled).
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask else { return }
        guard let meta = LazyDownloadTaskMeta.decode(fromTaskDescription: downloadTask.taskDescription) else { return }
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

    /// Deterministic staging URL for a download. Lives under
    /// Caches/LazyDownloads/ so the OS may reclaim it under storage
    /// pressure, but we move into the sandbox before any persistent
    /// state references it.
    static func stagedTempURL(for meta: LazyDownloadTaskMeta) -> URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LazyDownloads", isDirectory: true)
        return dir
            .appendingPathComponent("\(meta.expectedSHA256)_\(meta.expectedByteCount)")
            .appendingPathExtension(meta.originalExtension)
    }
}
