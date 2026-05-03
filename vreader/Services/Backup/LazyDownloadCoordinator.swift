// Purpose: MainActor-isolated coordinator for lazy book-blob downloads
// triggered by user tap on a `.remoteOnly` library row. Receives progress
// + completion events from a non-isolated `LazyDownloadDelegate` and
// updates @Observable state that SwiftUI views can render.
//
// Feature #47 WI-3a + WI-3b. WI-3a shipped the skeleton + delegate hop.
// WI-3b adds lifecycle persistence: at init, the coordinator reattaches
// to any in-flight tasks the OS preserved across app termination and
// reconciles persisted `.downloading` rows that have no live task by
// flipping them to `.failed` (crash recovery).
// WI-3c adds WebDAVNetworkPolicy for Wi-Fi-only gating.
//
// @coordinates-with: LazyDownloadDelegate.swift, LazyDownloadTaskMeta.swift,
//   BackgroundDownloadSession.swift, PersistenceActor+RemoteOnly.swift,
//   BookFileImportFinalizer.swift (future, WI-4a),
//   WebDAVDownloadRequestBuilder.swift (future, request construction),
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation
import OSLog
import Observation

extension Notification.Name {
    /// Posted when a book's `BookFileState` changes due to lazy-download
    /// reconciliation, finalization, or failure. `userInfo` carries
    /// `["fingerprintKey": String, "state": String]` (state is the
    /// `BookFileState.rawValue`). Library rows observe this to refresh
    /// without a full fetch.
    static let bookFileStateDidChange = Notification.Name("vreader.backup.bookFileStateDidChange")
}

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

    /// True once `reattachAndReconcile()` has finished. Tests can `await`
    /// this — production code never reads it.
    private(set) var didCompleteReattach: Bool = false

    private let session: (any BackgroundDownloadSessioning)?
    private let persistence: PersistenceActor?

    /// Skeleton init for tests that don't need lifecycle persistence
    /// (WI-3a tests pass through this path).
    init() {
        self.session = nil
        self.persistence = nil
        self.didCompleteReattach = true
    }

    /// Production / WI-3b init. Triggers reattach + reconcile in a child
    /// Task — callers can `await coordinator.waitForReattach()` to barrier
    /// on completion in tests.
    init(session: any BackgroundDownloadSessioning, persistence: PersistenceActor) {
        self.session = session
        self.persistence = persistence
        Task { [weak self] in
            await self?.reattachAndReconcile()
        }
    }

    /// Test barrier — resumes once `reattachAndReconcile()` has finished.
    /// Production callers don't need this; observers see `progressByKey`
    /// update via @Observable as the OS delivers callbacks.
    func waitForReattach() async {
        while !didCompleteReattach {
            await Task.yield()
        }
    }

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

    // MARK: - Background-event handler invocation

    /// Called by `LazyDownloadDelegate.urlSessionDidFinishEvents` after
    /// iOS has finished delivering all queued background events for the
    /// session. Retrieves the stored UIApplicationDelegate completion
    /// handler (registered when iOS relaunched the app via
    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`)
    /// and invokes it. iOS will not release the app's background-launch
    /// grace period until the handler runs.
    ///
    /// `handlerProvider` is injected only in tests — production reads
    /// `VReaderAppDelegate.takeBackgroundHandler(for:)`.
    func didFinishBackgroundEvents(
        sessionIdentifier: String,
        handlerProvider: ((String) -> (() -> Void)?)? = nil
    ) {
        let take = handlerProvider ?? { id in
            VReaderAppDelegate.takeBackgroundHandler(for: id)
        }
        guard let handler = take(sessionIdentifier) else {
            log.info(
                "didFinishBackgroundEvents: no handler for session \(sessionIdentifier, privacy: .public) (foreground events?)"
            )
            return
        }
        handler()
        log.info(
            "didFinishBackgroundEvents: invoked handler for session \(sessionIdentifier, privacy: .public)"
        )
    }

    /// Test seam — wipes all coordinator state. Production never calls this.
    func reset() {
        progressByKey = [:]
        outcomes = [:]
        terminalKeys = []
    }

    // MARK: - Reattach + reconcile (WI-3b)

    /// Bootstraps coordinator state from the underlying background session
    /// and persistence layer. Runs in the init Task; tests can barrier on
    /// `waitForReattach()`. Logic:
    ///
    /// 1. Read every in-flight task descriptor from the session
    ///    (suspension point — gated tests inject delegate events here
    ///    to drive race scenarios).
    /// 2. Read persisted `.downloading` fingerprintKeys. If the fetch
    ///    fails, log and exit — production keeps running with stale
    ///    state rather than stranding the coordinator.
    /// 3. For each descriptor with a valid `LazyDownloadTaskMeta` whose
    ///    persisted row is `.downloading` AND the key is not already in
    ///    `terminalKeys`, seed `progressByKey` with an indeterminate
    ///    spinner so the UI shows progress before the first real
    ///    `didWriteData`. Tasks for non-`.downloading` rows are stale
    ///    (OS-preserved past finalization) and ignored.
    /// 4. Reconcile orphans: each persisted `.downloading` key not in
    ///    the live set is flipped to `.failed` UNLESS the coordinator
    ///    already has a `.completed` outcome for that key (a finish
    ///    callback raced reattach and the WI-4a finalizer hasn't yet
    ///    advanced persistence to `.local`). The `.completed` outcome
    ///    stays — the finalizer will reconcile persistence next.
    private func reattachAndReconcile() async {
        guard let session, let persistence else {
            didCompleteReattach = true
            return
        }
        let descriptors = await session.allInFlightDownloads()
        let persistedDownloading: [String]
        do {
            persistedDownloading = try await persistence.fingerprintKeys(withFileState: .downloading)
        } catch {
            log.error(
                "reattach: fingerprintKeys(.downloading) fetch failed: \(String(describing: error), privacy: .private). Skipping reconcile this launch."
            )
            didCompleteReattach = true
            return
        }
        let persistedDownloadingSet = Set(persistedDownloading)

        // Seed progress only for live tasks whose persisted row is
        // `.downloading`. Tasks that the OS preserved for already-final
        // rows (`.local`, `.failed`, `.remoteOnly`, or deleted) are
        // ignored here — they're stale and will be cancelled by the
        // enqueue path (WI-4a) when it next runs, or simply complete
        // into a coordinator that has no consumer for them. Tasks
        // already in `terminalKeys` (a delegate event raced reattach
        // and finished first) are also excluded so the row is treated
        // as orphaned and reconciled to `.failed`.
        var liveDownloadingKeys: Set<String> = []
        for desc in descriptors {
            guard let meta = LazyDownloadTaskMeta.decode(fromTaskDescription: desc.taskDescription) else {
                continue
            }
            guard persistedDownloadingSet.contains(meta.fingerprintKey) else { continue }
            guard !terminalKeys.contains(meta.fingerprintKey) else { continue }
            liveDownloadingKeys.insert(meta.fingerprintKey)
            progressByKey[meta.fingerprintKey] = LazyDownloadProgress(
                fingerprintKey: meta.fingerprintKey,
                bytesWritten: 0,
                totalBytes: nil
            )
        }

        for key in persistedDownloading where !liveDownloadingKeys.contains(key) {
            // Don't overwrite a `.completed` outcome with `.failed`. The
            // delegate's finish callback raced reattach and won — let
            // WI-4a's finalizer advance persistence to `.local` next.
            if case .completed = outcomes[key] { continue }
            do {
                try await persistence.setBookFileState(fingerprintKey: key, newState: .failed)
            } catch {
                // Row stays `.downloading` for this launch. We surface
                // a `.failed` outcome anyway so the row's UI can offer
                // a retry CTA — the next enqueue+finalize cycle will
                // re-attempt the persistence write. Never strand a
                // user-visible row silently.
                log.error(
                    "reconcile setBookFileState failed: \(key, privacy: .private) — \(String(describing: error), privacy: .private)"
                )
                terminalKeys.insert(key)
                if outcomes[key] == nil {
                    outcomes[key] = .failed(
                        fingerprintKey: key,
                        reason: "reconcile-persist-failed"
                    )
                }
                continue
            }
            terminalKeys.insert(key)
            // Don't overwrite an existing `.failed` outcome that carried
            // a more specific reason (e.g. a real network error from a
            // delegate event that raced reattach). Only fill in the
            // termination-reason if no outcome exists yet.
            if outcomes[key] == nil {
                outcomes[key] = .failed(
                    fingerprintKey: key,
                    reason: "interrupted-by-app-termination"
                )
            }
            NotificationCenter.default.post(
                name: .bookFileStateDidChange,
                object: nil,
                userInfo: [
                    "fingerprintKey": key,
                    "state": BookFileState.failed.rawValue
                ]
            )
            log.info(
                "reconcile: \(key, privacy: .private) → .failed (no live task)"
            )
        }

        didCompleteReattach = true
    }
}
