// Purpose: Bug #265 / GH #1148 — high-fidelity integration verification that
// the live AZW3/MOBI Foliate reading-position save/restore actually round-trips
// through the REAL persistence subsystem. The original failure was that the
// live `FoliateBilingualContainerView` path never invoked persistence at all
// (the save/restore code lived only in dead `FoliateReaderHost`), so every
// reopen resumed at the start. The fix wired `FoliatePositionRestoreController`
// (→ `ReaderPositionService` → `PersistenceActor`) into the live path.
//
// Scope (deliberately narrow): this verifies the controller →
// `ReaderPositionService` → REAL in-memory `PersistenceActor` (SwiftData)
// round-trip with NO stubbed persistence — unlike `FoliatePositionRestoreControllerTests`,
// which use a `MockPositionStore`. It proves a read position persists to the
// real store, a reopen restores it, the gate prevents the open→start relocate
// from clobbering the saved position, and a mismatched-book change is ignored.
//
// What it does NOT cover: the live SwiftUI/WKWebView wiring in
// `FoliateBilingualContainerView+Position.swift` (the `.onReceive(.foliateRelocated)`
// / `.task` / `.onDisappear` observers that actually INVOKE this controller) —
// the exact missing-call seam Bug #265 lived in. That seam can only be exercised
// end-to-end by opening a real AZW3/MOBI book, and `DebugFixtureCatalog` ships
// no AZW3/MOBI fixture (none can be generated here — no Calibre/kindlegen). So
// the view-wiring remains device-verification-blocked on an AZW3 fixture
// harness; this suite hardens the persistence subsystem boundary it depends on.
//
// @coordinates-with: FoliatePositionRestoreController.swift,
//   ReaderPositionService.swift, PersistenceActor+ReadingPosition.swift,
//   FoliateNavSeek.swift, dev-docs/verification/bug-265-20260526.md, GH #1148

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Bug #265 — Foliate position persistence (high-fidelity integration)")
struct FoliatePositionPersistenceIntegrationTests {

    private func azw3Fingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "c", count: 64),
            fileByteCount: 4096, format: .azw3
        )
    }

    private func insertAZW3Book(_ persistence: PersistenceActor, fp: DocumentFingerprint) async throws {
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey, title: "AZW3 Book", author: nil,
            coverImagePath: nil, fingerprint: fp,
            provenance: CollectionTestHelper.makeProvenance(),
            detectedEncoding: nil, addedAt: Date()
        )
        _ = try await persistence.insertBook(record)
    }

    /// The core round-trip: read to a CFI in one session, reopen in a fresh
    /// controller, and confirm the saved CFI nav target is restored — through the
    /// real `PersistenceActor`. Production previously resumed at the start because
    /// the live path never persisted.
    @Test("save→reopen restores the saved CFI through the real PersistenceActor")
    func saveThenReopenRestoresCFIThroughRealStore() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let fp = azw3Fingerprint()
        let key = fp.canonicalKey
        try await insertAZW3Book(persistence, fp: fp)

        // SESSION 1 — open at start (nothing saved), read to a CFI, close.
        let session1 = FoliatePositionRestoreController(
            fingerprintKey: key, deviceId: "dev-1", persistence: persistence, debounceNanoseconds: 0
        )
        #expect(await session1.loadRestoreTarget() == nil, "first open has nothing to restore")
        session1.openSaveGate()

        let cfi = "epubcfi(/6/14!/4/2/1:42)"
        let readLocator = Locator.validated(
            bookFingerprint: fp, href: "chapter3.xhtml", progression: 0.5, cfi: cfi
        )!
        session1.handlePositionChange(readLocator)
        await session1.flush() // immediate save via the REAL PersistenceActor

        // The position actually reached the real SwiftData store.
        let persisted = try await persistence.loadPosition(bookFingerprintKey: key)
        #expect(persisted?.cfi == cfi, "the read position persisted to the real store")

        // SESSION 2 (reopen) — a fresh controller restores the saved CFI.
        let session2 = FoliatePositionRestoreController(
            fingerprintKey: key, deviceId: "dev-1", persistence: persistence, debounceNanoseconds: 0
        )
        let restoreTarget = await session2.loadRestoreTarget()
        #expect(restoreTarget != nil, "reopen has a restore target (production resumed at the start)")
        #expect(restoreTarget == FoliateNavSeek.navigationTarget(for: readLocator),
                "reopen restores the exact saved CFI nav target")
    }

    /// The restore gate must drop the open→start relocate so it cannot clobber a
    /// previously-saved position before the restore seek runs — verified against
    /// the real store (the saved position survives intact).
    @Test("open→start relocate before the gate opens does NOT clobber the saved position (real store)")
    func preGateRelocateDoesNotClobberSavedPosition() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let fp = azw3Fingerprint()
        let key = fp.canonicalKey
        try await insertAZW3Book(persistence, fp: fp)

        // Pre-seed a saved position from a prior session.
        let savedCFI = "epubcfi(/6/4!/4/10:0)"
        try await persistence.savePosition(
            bookFingerprintKey: key,
            locator: Locator.validated(bookFingerprint: fp, href: "c1.xhtml", progression: 0.2, cfi: savedCFI)!,
            deviceId: "dev-1"
        )

        let controller = FoliatePositionRestoreController(
            fingerprintKey: key, deviceId: "dev-1", persistence: persistence, debounceNanoseconds: 0
        )
        // The open→start relocate arrives BEFORE loadRestoreTarget/openSaveGate.
        let startLocator = Locator.validated(
            bookFingerprint: fp, href: "c1.xhtml", progression: 0.0, cfi: "epubcfi(/6/2!/4/2:0)"
        )!
        controller.handlePositionChange(startLocator) // gate closed → dropped
        await controller.flush()                       // nothing gated to flush

        let after = try await persistence.loadPosition(bookFingerprintKey: key)
        #expect(after?.cfi == savedCFI, "the pre-gate start relocate did not overwrite the saved position")
    }

    /// A position change for a DIFFERENT book must never be written under this
    /// controller's key — verified end-to-end against the real store.
    @Test("a mismatched-book position change is not persisted under this book (real store)")
    func mismatchedBookChangeNotPersisted() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let fp = azw3Fingerprint()
        let key = fp.canonicalKey
        try await insertAZW3Book(persistence, fp: fp)

        let controller = FoliatePositionRestoreController(
            fingerprintKey: key, deviceId: "dev-1", persistence: persistence, debounceNanoseconds: 0
        )
        _ = await controller.loadRestoreTarget()
        controller.openSaveGate()

        // A locator for a different book.
        let otherFp = DocumentFingerprint(
            contentSHA256: String(repeating: "d", count: 64), fileByteCount: 2048, format: .azw3
        )
        let otherLocator = Locator.validated(
            bookFingerprint: otherFp, href: "x.xhtml", progression: 0.9, cfi: "epubcfi(/6/99!/4/2:0)"
        )!
        controller.handlePositionChange(otherLocator) // mismatched key → ignored
        await controller.flush()

        #expect(try await persistence.loadPosition(bookFingerprintKey: key) == nil,
                "no position was written under this book for a different book's locator")
    }
}
