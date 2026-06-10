// Purpose: Bug #265 / GH #1148 — cross-session reading-position save/restore
// wiring for the live AZW3/MOBI path. Keeps the notification-handler logic out
// of the already-large `FoliateBilingualContainerView` body file.
//
// Flow:
//   - `.task` / lazy: build a `FoliatePositionRestoreController` from the
//     SwiftData container (`ensurePositionController`).
//   - first `.foliateRelocated` (post-init; fires for every book, TOC or not):
//     `triggerPositionRestoreIfNeeded` loads the saved position and seeks to it
//     via the `.foliateRequestSeekTarget` channel (the same channel #1136's TOC
//     nav uses), then opens the save gate.
//   - each `.readerPositionDidChange`: `handlePositionDidChange` forwards the
//     locator to the controller, which gates out the pre-restore open→start
//     relocate and debounce-saves the rest (filtered to this book).
//   - teardown: `.onDisappear` flushes the last position immediately.
//
// @coordinates-with: FoliateBilingualContainerView.swift,
//   FoliatePositionRestoreController.swift, FoliateNavSeek.swift,
//   ReaderContainerView.swift (deviceId), PersistenceActor+ReadingPosition.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData

extension FoliateBilingualContainerView {

    /// Lazily builds the position controller from the SwiftData container.
    /// Idempotent — safe to call from `.task` and from notification handlers.
    func ensurePositionController() {
        guard positionController == nil else { return }
        positionController = FoliatePositionRestoreController(
            fingerprintKey: fingerprintKey,
            deviceId: ReaderContainerView.deviceId,
            persistence: PersistenceActor(modelContainer: modelContext.container)
        )
    }

    /// Bug #345: lazily builds + starts the session lifecycle (mirrors
    /// `ensurePositionController`). Begins the session immediately — the
    /// reader is on screen by the time `.task` runs.
    func ensureSessionLifecycle() {
        guard sessionLifecycle == nil,
              let fingerprint = DocumentFingerprint(canonicalKey: fingerprintKey) else { return }
        let persistence = PersistenceActor(modelContainer: modelContext.container)
        let lifecycle = ReaderLifecycleHelper(
            bookFingerprint: fingerprint,
            positionService: ReaderPositionService(
                bookFingerprintKey: fingerprintKey,
                deviceId: ReaderContainerView.deviceId,
                persistence: persistence
            ),
            sessionTracker: ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContext.container),
                deviceId: ReaderContainerView.deviceId
            ),
            positionStore: persistence
        )
        try? lifecycle.beginSession()
        Task { await lifecycle.updateLastOpened() }
        sessionLifecycle = lifecycle
    }

    /// Bug #265 + #345 teardown: flush the last position, then end the
    /// reading session (the helper ends the session row, recomputes stats,
    /// and posts `.readerDidClose` — library-refresh parity with the other
    /// formats). Codex round-1 Medium: guarded by a background task so a
    /// fast dismiss / app-leave can't suspend before the writes land (the
    /// legacy Foliate host's precedent).
    func handleHostTeardown() {
        positionRestoreTask?.cancel()
        let controller = positionController
        let lifecycle = sessionLifecycle
        let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        Task {
            await controller?.flush()
            await lifecycle?.close(locator: nil)
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }
    }

    /// Bug #345 (Codex round-1 High): scene-phase session pause/resume. The
    /// position flush rides the same background-task guard as the legacy
    /// hosts so iOS can't suspend mid-write.
    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            let controller = positionController
            let lifecycle = sessionLifecycle
            let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            Task {
                await controller?.flush()
                await lifecycle?.onBackground(locator: nil)
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        case .active:
            sessionLifecycle?.onForeground()
        @unknown default:
            break
        }
    }

    /// On the FIRST relocate (post-init; fires for every book), load the saved
    /// position, seek to it, then open the save gate. Gate-open follows the
    /// seek-post with no `await` between them, so the open→start relocate that
    /// preceded this is dropped (gate still closed) and the post-restore
    /// relocate persists. When nothing is saved, the gate still opens so
    /// reading from the start persists going forward.
    /// Number of times the restore seek is re-asserted (Bug #265 rework). The
    /// first relocate is render-complete of the OPENING section only, so a
    /// cross-section `goToFraction` that early is a no-op; re-asserting over a
    /// short window lands the seek once foliate-js finishes paginating — more
    /// robust than one fixed delay across device speeds / book sizes.
    private var restoreSeekAttempts: Int { 4 }
    /// Gap between restore-seek re-assertions.
    private var restoreSeekRetryNanoseconds: UInt64 { 700_000_000 }

    func triggerPositionRestoreIfNeeded() {
        guard !didStartPositionRestore else { return }
        didStartPositionRestore = true
        ensurePositionController()
        let controller = positionController
        let key = fingerprintKey
        positionRestoreTask = Task {
            let plan = await controller?.loadRestorePlan()
            // Bug #265 (Codex Gate-4): if the view was dismissed mid-load,
            // bail before posting so a stale task can't seek a new reader
            // instance of the same book.
            guard !Task.isCancelled else { return }

            // Nothing meaningful to restore → open the save gate IMMEDIATELY so
            // reading-from-start persists with no needless delay (Codex round-1):
            // a fresh book, or a saved position already at the start.
            let hasRestore = (plan?.fraction ?? 0) > 0 || plan?.cfiTarget != nil
            guard let plan, hasRestore else {
                controller?.openSaveGate()
                return
            }

            // Re-assert the restore seek across a short window. The save gate
            // stays CLOSED until the restore completes, so the open→start
            // relocates (and the seek's own relocates) are dropped, not
            // persisted; only the post-restore position persists.
            for attempt in 0..<restoreSeekAttempts {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: restoreSeekRetryNanoseconds)
                    guard !Task.isCancelled else { return }
                }
                if let fraction = plan.fraction, fraction > 0 {
                    // Restore via whole-book fraction. The live Foliate reader
                    // honors `goToFraction` (the bottom scrubber + `seek?fraction`
                    // channel) but NOT `goTo(filepos-CFI)` for AZW3/MOBI —
                    // device-confirmed: save + target-load worked, yet the CFI
                    // seek never relocated the reader. Fraction resumes near
                    // where the reader left off.
                    NotificationCenter.default.post(
                        name: .foliateRequestSeekFraction,
                        object: nil,
                        userInfo: ["fraction": fraction, "fingerprintKey": key]
                    )
                } else if let target = plan.cfiTarget {
                    // Fallback only (no saved fraction): try the CFI/href target.
                    NotificationCenter.default.post(
                        name: .foliateRequestSeekTarget,
                        object: nil,
                        userInfo: ["target": target, "fingerprintKey": key]
                    )
                }
            }
            controller?.openSaveGate()
        }
    }

    /// Forward a live position change to the controller (which filters by
    /// fingerprint + gates the pre-restore relocate).
    func handlePositionDidChange(_ notification: Notification) {
        guard let locator = notification.object as? Locator else { return }
        ensurePositionController()
        positionController?.handlePositionChange(locator)
    }
}
#endif

/// Bug #265 + #345: the Foliate host's lifecycle bundle — setup on mount,
/// teardown on unmount, session pause/resume on scene-phase change. A single
/// `ViewModifier` so the host body's modifier chain stays inside SwiftUI's
/// type-inference budget (the `ReaderReTranslateObserver` precedent).
struct FoliateSessionLifecycleModifier: ViewModifier {
    let scenePhase: ScenePhase
    let onSetup: () -> Void
    let onTeardown: () -> Void
    let onPhaseChange: (ScenePhase) -> Void

    func body(content: Content) -> some View {
        content
            .task { onSetup() }
            .onDisappear { onTeardown() }
            .onChange(of: scenePhase) { _, newPhase in
                onPhaseChange(newPhase)
            }
    }
}
