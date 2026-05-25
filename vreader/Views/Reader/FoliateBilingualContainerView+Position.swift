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

    /// On the FIRST relocate (post-init; fires for every book), load the saved
    /// position, seek to it, then open the save gate. Gate-open follows the
    /// seek-post with no `await` between them, so the open→start relocate that
    /// preceded this is dropped (gate still closed) and the post-restore
    /// relocate persists. When nothing is saved, the gate still opens so
    /// reading from the start persists going forward.
    func triggerPositionRestoreIfNeeded() {
        guard !didStartPositionRestore else { return }
        didStartPositionRestore = true
        ensurePositionController()
        let controller = positionController
        let key = fingerprintKey
        positionRestoreTask = Task {
            let target = await controller?.loadRestoreTarget()
            // Bug #265 (Codex Gate-4): if the view was dismissed mid-load,
            // bail before posting so a stale task can't seek a new reader
            // instance of the same book.
            guard !Task.isCancelled else { return }
            if let target {
                NotificationCenter.default.post(
                    name: .foliateRequestSeekTarget,
                    object: nil,
                    userInfo: ["target": target, "fingerprintKey": key]
                )
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
