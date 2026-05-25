// Purpose: Cross-session reading-position save/restore for the LIVE AZW3/MOBI
// Foliate path (Bug #265 / GH #1148). Owns the debounced save + the restore
// gate so `FoliateBilingualContainerView` can persist + restore position the
// same way every other format does.
//
// Why this exists: position persistence for Foliate used to live only in the
// DEAD `FoliateReaderHost`/`FoliateReaderViewModel` (which composed
// `ReaderPositionService` + `loadPosition`+seek-on-ready). The live wrapper
// `FoliateBilingualContainerView` → `FoliateSpikeView` (Feature #56 WI-11)
// never re-wired it, so AZW3/MOBI always reopened at the start. This is the
// third such regression from the wrapper swap, after Bug #260 (bottom chrome)
// and #262/#1136 (TOC + locator-nav + position reporting).
//
// Key decisions:
// - **The save gate (the load-bearing bit).** On open, foliate-js renders at
//   the start and fires a relocate → `.readerPositionDidChange` (start). If we
//   persisted that, it would clobber the saved position BEFORE we restore it.
//   So `handlePositionChange` is a no-op until `loadRestoreTarget()` has run
//   (which is what dispatches the restore seek). The post-restore relocate
//   then re-persists the correct position.
// - **Reuses `ReaderPositionService`** for the 2s debounce + stale-write
//   guard, identical to the EPUB/TXT/MD/PDF readers — no parallel save logic.
// - **Restore target via `FoliateNavSeek.navigationTarget`** (CFI preferred,
//   href fallback) — the same resolution the #1136 TOC-nav path uses.
// - Pure-ish + `@MainActor`; persistence injected as `ReadingPositionPersisting`
//   so the gate + restore logic is unit-testable with `MockPositionStore`.
//
// @coordinates-with: FoliateBilingualContainerView+Position.swift,
//   ReaderPositionService.swift, FoliateNavSeek.swift,
//   ReadingPositionPersisting.swift, PersistenceActor+ReadingPosition.swift

import Foundation

@MainActor
final class FoliatePositionRestoreController {

    private let fingerprintKey: String
    private let persistence: any ReadingPositionPersisting
    private let positionService: ReaderPositionService

    /// Opened by `loadRestoreTarget()`. Until then, position changes are
    /// dropped so the open→start relocate cannot overwrite the saved position.
    private var restoreDispatched = false
    /// The most recent gated position change — flushed (immediate save) on
    /// teardown so a close within the debounce window still persists.
    private var lastLocator: Locator?

    init(
        fingerprintKey: String,
        deviceId: String,
        persistence: any ReadingPositionPersisting,
        debounceNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.fingerprintKey = fingerprintKey
        self.persistence = persistence
        self.positionService = ReaderPositionService(
            bookFingerprintKey: fingerprintKey,
            deviceId: deviceId,
            persistence: persistence,
            debounceNanoseconds: debounceNanoseconds
        )
    }

    /// Loads the saved position and resolves the Foliate-js goTo target (CFI
    /// preferred, href fallback), or `nil` when nothing is saved / usable.
    ///
    /// Does NOT open the save gate — the caller opens it via `openSaveGate()`
    /// *after* posting the restore seek, so the gate-open and seek-post are
    /// adjacent (no `await` between them). This closes the window where the
    /// open→start relocate could be persisted between gate-open and seek-post
    /// (Codex Gate-4): until `openSaveGate()`, every position change is dropped.
    func loadRestoreTarget() async -> String? {
        // `loadPosition` returns `Locator?`; `try?` flattens the throw away,
        // so this binds the saved locator (nil when nothing is stored).
        guard let saved = try? await persistence.loadPosition(bookFingerprintKey: fingerprintKey) else {
            return nil
        }
        return FoliateNavSeek.navigationTarget(for: saved)
    }

    /// Opens the save gate. Call once, synchronously right after posting the
    /// restore seek (or after determining there's nothing to restore) so live
    /// position changes from then on persist. Idempotent.
    func openSaveGate() {
        restoreDispatched = true
    }

    /// Persists a live position change — debounced — but only after restore has
    /// been dispatched and only for this book.
    func handlePositionChange(_ locator: Locator) {
        guard restoreDispatched else { return }
        guard locator.bookFingerprint.canonicalKey == fingerprintKey else { return }
        lastLocator = locator
        positionService.scheduleSave(locator: locator)
    }

    /// Immediately persists the last gated position (reader teardown), cancelling
    /// any pending debounce. No-op when nothing has been persisted yet.
    func flush() async {
        guard let lastLocator else { return }
        await positionService.saveNow(locator: lastLocator)
    }
}
