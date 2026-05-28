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
import OSLog

@MainActor
final class FoliatePositionRestoreController {

    private static let log = Logger(subsystem: "com.vreader.app", category: "FoliatePosition")

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

    /// The resolved restore instructions for a reopened book.
    struct RestorePlan: Equatable, Sendable {
        /// Whole-book progress (0...1) — the RELIABLE restore channel for
        /// AZW3/MOBI (filepos-anchored CFIs that foliate-js `goTo` can't resolve).
        let fraction: Double?
        /// CFI/href goTo target — kept as a fallback only.
        let cfiTarget: String?
    }

    /// Loads the saved position and returns both the whole-book `fraction` and
    /// the CFI/href goTo `cfiTarget`. Bug #265 rework: the live Foliate reader
    /// honors `goToFraction` but NOT a `goTo(filepos-CFI)` (device-confirmed:
    /// save + target-load worked, but the CFI seek never relocated the reader),
    /// so the caller restores via `fraction` and uses `cfiTarget` only as a
    /// fallback. `nil` when nothing is saved.
    ///
    /// Does NOT open the save gate — the caller opens it via `openSaveGate()`
    /// after posting the restore seek (gate-open/seek-post adjacency, Gate-4).
    func loadRestorePlan() async -> RestorePlan? {
        guard let saved = try? await persistence.loadPosition(bookFingerprintKey: fingerprintKey) else {
            Self.log.info("loadRestorePlan: no saved position for \(self.fingerprintKey, privacy: .public)")
            return nil
        }
        let cfi = FoliateNavSeek.navigationTarget(for: saved)
        Self.log.info("loadRestorePlan: fraction=\(saved.progression ?? -1) cfi=\(saved.cfi ?? "nil", privacy: .public) → restore via \(saved.progression != nil ? "fraction" : "cfi", privacy: .public)")
        return RestorePlan(fraction: saved.progression, cfiTarget: cfi)
    }

    /// Legacy CFI-only accessor (retained for unit tests + as the `cfiTarget`
    /// source). Prefer `loadRestorePlan()` on the live path.
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
            Self.log.info("loadRestoreTarget: no saved position for \(self.fingerprintKey, privacy: .public)")
            return nil
        }
        let target = FoliateNavSeek.navigationTarget(for: saved)
        Self.log.info("loadRestoreTarget: saved cfi=\(saved.cfi ?? "nil", privacy: .public) href=\(saved.href ?? "nil", privacy: .public) progression=\(saved.progression ?? -1) → target=\(target ?? "nil", privacy: .public)")
        return target
    }

    /// Opens the save gate. Call once, synchronously right after posting the
    /// restore seek (or after determining there's nothing to restore) so live
    /// position changes from then on persist. Idempotent.
    func openSaveGate() {
        restoreDispatched = true
        Self.log.info("openSaveGate: save gate OPEN for \(self.fingerprintKey, privacy: .public)")
    }

    /// Persists a live position change — debounced — but only after restore has
    /// been dispatched and only for this book.
    func handlePositionChange(_ locator: Locator) {
        guard restoreDispatched else {
            Self.log.info("handlePositionChange: DROPPED (gate closed) cfi=\(locator.cfi ?? "nil", privacy: .public)")
            return
        }
        guard locator.bookFingerprint.canonicalKey == fingerprintKey else {
            Self.log.info("handlePositionChange: DROPPED (key mismatch) \(locator.bookFingerprint.canonicalKey, privacy: .public)")
            return
        }
        lastLocator = locator
        positionService.scheduleSave(locator: locator)
        Self.log.info("handlePositionChange: scheduled save cfi=\(locator.cfi ?? "nil", privacy: .public) progression=\(locator.progression ?? -1)")
    }

    /// Immediately persists the last gated position (reader teardown), cancelling
    /// any pending debounce. No-op when nothing has been persisted yet.
    func flush() async {
        guard let lastLocator else {
            Self.log.info("flush: nothing to flush (no gated position) for \(self.fingerprintKey, privacy: .public)")
            return
        }
        Self.log.info("flush: saving cfi=\(lastLocator.cfi ?? "nil", privacy: .public) progression=\(lastLocator.progression ?? -1)")
        await positionService.saveNow(locator: lastLocator)
    }
}
