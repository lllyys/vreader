// Bug #305: Foliate/AZW3 bilingual state not synced to the parent on reopen.
// The fix mirrors the TXT #245 fix — Foliate's `ensureBilingualViewModel` now
// runs on OPEN (section-load) and calls `postDidChange()`. These CI-safe tests
// pin the two invariants that make the on-open call correct:
//   1. a fresh (unconfigured) VM does NOT need the setup sheet → calling
//      ensureBilingualViewModel on open won't spuriously raise it;
//   2. postDidChange posts `.readerBilingualDidChange` carrying the enabled
//      state → the parent learns a previously-enabled book's state on reopen.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Foliate bilingual state-sync on open (Bug #305)")
struct FoliateBilingualStateSyncTests {

    private func tempBase() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("b305-\(UUID().uuidString)")
    }

    @Test("a fresh (unconfigured) VM has needsSetupSheet == false — on-open build is safe")
    func freshVMDoesNotNeedSetupSheet() {
        let vm = BilingualReadingViewModel(bookFingerprintKey: "azw3:x:1", perBookBaseURL: tempBase())
        #expect(vm.needsSetupSheet == false)
        #expect(vm.isEnabled == false)
    }

    @Test("postDidChange posts .readerBilingualDidChange carrying the enabled state")
    func postDidChangeNotifiesParent() {
        let vm = BilingualReadingViewModel(bookFingerprintKey: "azw3:k:9", perBookBaseURL: tempBase())
        nonisolated(unsafe) var receivedKey: String?
        nonisolated(unsafe) var receivedEnabled: Bool?
        // queue: nil → synchronous delivery on the posting (main) thread.
        let token = NotificationCenter.default.addObserver(
            forName: .readerBilingualDidChange, object: nil, queue: nil
        ) { note in
            receivedKey = note.userInfo?["fingerprintKey"] as? String
            receivedEnabled = note.userInfo?["isEnabled"] as? Bool
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.postDidChange()

        #expect(receivedKey == "azw3:k:9")
        #expect(receivedEnabled == false)  // fresh VM is not enabled
    }
}
