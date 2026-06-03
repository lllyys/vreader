// Feature #86 WI-5b: AIChatViewModel's whole-book send-flow integration — the
// first question under the .wholeBook scope triggers the on-demand read, and the
// composer is disabled while reading.

import Testing
import Foundation
@testable import vreader

@Suite("AIChatViewModel whole-book send flow (Feature #86 WI-5b)")
@MainActor
struct AIChatViewModelWholeBookTests {

    private func makeVM() -> AIChatViewModel {
        AIChatViewModel(
            aiService: AIService(
                featureFlags: FeatureFlags.shared,
                consentManager: AIConsentManager(),
                keychainService: KeychainService(),
                profileStore: ProviderProfileStore.shared
            ),
            bookFingerprint: nil
        )
    }

    @Test func isComposerDisabled_falseWhenNoRetrievalOrIdle() {
        let vm = makeVM()
        #expect(!vm.isComposerDisabled)               // no retrieval
        vm.wholeBookRetrieval = WholeBookRetrievalViewModel()
        #expect(!vm.isComposerDisabled)               // idle
        vm.wholeBookRetrieval?.arm()
        #expect(!vm.isComposerDisabled)               // armed (not reading)
    }

    @Test func sendMessage_wholeBookArmed_triggersTheRead() async {
        let vm = makeVM()
        vm.setScope(.wholeBook)
        let retrieval = WholeBookRetrievalViewModel()
        retrieval.arm()
        vm.wholeBookRetrieval = retrieval
        nonisolated(unsafe) var readRequested = false
        vm.onWholeBookReadRequested = { readRequested = true }

        // The send will fail at the provider (no key) AFTER the read trigger; we
        // only assert the trigger fired.
        await vm.sendMessage("What happens at the end?")
        #expect(readRequested)
    }

    @Test func sendMessage_nonWholeBookScope_doesNotTriggerRead() async {
        let vm = makeVM()
        vm.setScope(.chapter)
        let retrieval = WholeBookRetrievalViewModel()
        vm.wholeBookRetrieval = retrieval
        nonisolated(unsafe) var readRequested = false
        vm.onWholeBookReadRequested = { readRequested = true }

        await vm.sendMessage("A chapter question")
        #expect(!readRequested)
    }
}
