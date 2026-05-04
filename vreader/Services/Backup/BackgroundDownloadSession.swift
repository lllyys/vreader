// Purpose: Test seam for the lazy-download coordinator's interaction
// with `URLSession.background(...)`. The standard URLProtocol mock can't
// model a background URLSession's persistence-across-launches semantics,
// so we abstract just the surface the coordinator needs: enumeration of
// in-flight tasks at launch (for reattach) and a value-type descriptor so
// tests can construct fakes without instantiating real URLSessionDownloadTasks.
//
// Feature #47 WI-3b. Production wrapper holds the live URLSession and
// connects the delegate at construction. Mock in tests synthesizes
// descriptors directly.
//
// @coordinates-with: LazyDownloadCoordinator.swift, LazyDownloadDelegate.swift,
//   LazyDownloadTaskMeta.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation

/// Snapshot of an in-flight download task as observed at coordinator init.
/// Carries only what reattach actually needs — taskIdentifier (for collision
/// resolution and logs) and the persisted `taskDescription` (decoded into
/// `LazyDownloadTaskMeta` to recover identity). The real
/// `URLSessionDownloadTask` continues to live inside the production
/// session's runloop; subsequent delegate callbacks arrive via the normal
/// path.
struct LazyDownloadTaskDescriptor: Sendable, Equatable {
    let taskIdentifier: Int
    let taskDescription: String?
}

/// Test seam for the background URLSession. Production wraps a real
/// `URLSession.background(...)`; tests inject a deterministic mock.
protocol BackgroundDownloadSessioning: Sendable {
    /// All download tasks currently tracked by the underlying session.
    /// Called once at coordinator init to recover state from a session
    /// that survived app termination.
    func allInFlightDownloads() async -> [LazyDownloadTaskDescriptor]

    /// Starts a download task for `request` with the given persisted
    /// `taskDescription` so the delegate can recover identity across
    /// app termination. Returns the assigned task identifier so the
    /// coordinator can track it. Production calls
    /// `URLSessionDownloadTask.resume()`. Feature #47 WI-6.
    func enqueueDownload(request: URLRequest, taskDescription: String) -> Int
}

/// Production wrapper around `URLSession.background(...)`. Owns the
/// live session for the app's lifetime; the coordinator holds an instance
/// via the protocol and never touches the underlying URLSession directly.
final class URLSessionBackgroundSession: BackgroundDownloadSessioning, @unchecked Sendable {

    private let session: URLSession

    /// Creates a background URLSession with the specified identifier and
    /// connects the delegate at construction (URLSession requires this —
    /// the delegate cannot be replaced after).
    /// `allowsCellularAccess = true` here because Wi-Fi-only gating lives
    /// in `WebDAVNetworkPolicy` (WI-3c) — flipping this property mid-flight
    /// causes URLSession to cancel rather than pause, which doesn't match
    /// the UX we want.
    init(identifier: String, delegate: URLSessionDownloadDelegate) {
        let cfg = URLSessionConfiguration.background(withIdentifier: identifier)
        cfg.isDiscretionary = true
        cfg.sessionSendsLaunchEvents = true
        cfg.allowsCellularAccess = true
        self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    }

    func allInFlightDownloads() async -> [LazyDownloadTaskDescriptor] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                let descriptors = tasks.compactMap { task -> LazyDownloadTaskDescriptor? in
                    guard task is URLSessionDownloadTask else { return nil }
                    return LazyDownloadTaskDescriptor(
                        taskIdentifier: task.taskIdentifier,
                        taskDescription: task.taskDescription
                    )
                }
                continuation.resume(returning: descriptors)
            }
        }
    }

    func enqueueDownload(request: URLRequest, taskDescription: String) -> Int {
        let task = session.downloadTask(with: request)
        task.taskDescription = taskDescription
        task.resume()
        return task.taskIdentifier
    }
}
