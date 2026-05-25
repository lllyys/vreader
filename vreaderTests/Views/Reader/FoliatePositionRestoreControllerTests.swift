// Purpose: Tests for FoliatePositionRestoreController — the save/restore
// gate that gives the LIVE AZW3/MOBI Foliate path cross-session reading
// position persistence (Bug #265 / GH #1148).
//
// The live FoliateBilingualContainerView never persisted or restored
// position (the wiring lived only in dead FoliateReaderHost/ViewModel).
// This controller encapsulates the two non-trivial decisions:
//   1. restore-target resolution — load the saved Locator, resolve a
//      Foliate-js goTo target (CFI preferred, href fallback).
//   2. the save gate — DROP the open→start relocate that fires before
//      restore is dispatched (it would clobber the saved position), and
//      only persist changes for THIS book.
//
// @coordinates-with: FoliatePositionRestoreController.swift,
//   FoliateBilingualContainerView+Position.swift, MockPositionStore.swift

import Testing
@testable import vreader

@MainActor
@Suite("FoliatePositionRestoreController")
struct FoliatePositionRestoreControllerTests {

    private let key = "azw3:\(String(repeating: "a", count: 64)):1000"
    private let otherKey = "azw3:\(String(repeating: "b", count: 64)):2000"

    private func fingerprint(_ k: String) -> DocumentFingerprint {
        DocumentFingerprint(canonicalKey: k)!
    }

    private func locator(_ k: String, cfi: String?, href: String? = nil, progression: Double? = nil) -> Locator {
        Locator.validated(bookFingerprint: fingerprint(k), href: href,
                          progression: progression, cfi: cfi)!
    }

    private func makeController(_ store: MockPositionStore) -> FoliatePositionRestoreController {
        FoliatePositionRestoreController(fingerprintKey: key, deviceId: "test-device", persistence: store)
    }

    // MARK: - restore-target resolution

    @Test("loadRestoreTarget returns the saved CFI")
    func loadRestoreTargetReturnsSavedCFI() async {
        let store = MockPositionStore()
        await store.seed(bookFingerprintKey: key, locator: locator(key, cfi: "epubcfi(/6/4!/2/10)"))
        let controller = makeController(store)
        #expect(await controller.loadRestoreTarget() == "epubcfi(/6/4!/2/10)")
    }

    @Test("loadRestoreTarget falls back to href when the saved position has no CFI")
    func loadRestoreTargetFallsBackToHref() async {
        let store = MockPositionStore()
        await store.seed(bookFingerprintKey: key, locator: locator(key, cfi: nil, href: "OEBPS/ch3.xhtml"))
        let controller = makeController(store)
        #expect(await controller.loadRestoreTarget() == "OEBPS/ch3.xhtml")
    }

    @Test("loadRestoreTarget returns nil when no position is saved")
    func loadRestoreTargetNilWhenNothingSaved() async {
        let store = MockPositionStore()
        let controller = makeController(store)
        #expect(await controller.loadRestoreTarget() == nil)
    }

    // MARK: - the save gate

    @Test("position change BEFORE the gate opens is dropped (would clobber the saved position)")
    func positionChangeBeforeRestoreNotPersisted() async {
        let store = MockPositionStore()
        let controller = makeController(store)
        // simulate the open→start relocate arriving before the gate opens
        controller.handlePositionChange(locator(key, cfi: "epubcfi(/6/2!/0)"))
        await controller.flush()
        #expect(await store.saveCallCount == 0)
    }

    @Test("loadRestoreTarget alone does NOT open the gate (closes the gate-open-before-seek window)")
    func loadRestoreTargetDoesNotOpenGate() async {
        let store = MockPositionStore()
        let controller = makeController(store)
        _ = await controller.loadRestoreTarget()
        // gate still closed — a relocate between load and openSaveGate is dropped
        controller.handlePositionChange(locator(key, cfi: "epubcfi(/6/2!/0)"))
        await controller.flush()
        #expect(await store.saveCallCount == 0)
    }

    @Test("position change AFTER openSaveGate is persisted")
    func positionChangeAfterGateOpenPersisted() async {
        let store = MockPositionStore()
        let controller = makeController(store)
        _ = await controller.loadRestoreTarget()
        controller.openSaveGate()
        controller.handlePositionChange(locator(key, cfi: "epubcfi(/6/8!/4)"))
        await controller.flush()
        #expect(await store.saveCallCount == 1)
        #expect(await store.position(forKey: key)?.cfi == "epubcfi(/6/8!/4)")
    }

    @Test("openSaveGate opens the gate even with no saved position (read-from-start persists)")
    func openSaveGateEnablesSaveWithoutSavedPosition() async {
        let store = MockPositionStore()
        let controller = makeController(store)
        _ = await controller.loadRestoreTarget() // nil — nothing saved
        controller.openSaveGate()
        controller.handlePositionChange(locator(key, cfi: "epubcfi(/6/12!/2)"))
        await controller.flush()
        #expect(await store.saveCallCount == 1)
    }

    @Test("position change for a DIFFERENT book is ignored")
    func positionChangeMismatchedFingerprintIgnored() async {
        let store = MockPositionStore()
        let controller = makeController(store)
        controller.openSaveGate()
        controller.handlePositionChange(locator(otherKey, cfi: "epubcfi(/6/2!/0)"))
        await controller.flush()
        #expect(await store.saveCallCount == 0)
    }

    @Test("flush with no persisted change does nothing")
    func flushWithoutChangeIsNoop() async {
        let store = MockPositionStore()
        let controller = makeController(store)
        controller.openSaveGate()
        await controller.flush()
        #expect(await store.saveCallCount == 0)
    }
}
