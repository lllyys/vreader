// Purpose: Bug #323 repro — "AI chat hangs on the SECOND message". The default
// 2-message path is already covered by an INSTANT-stub test (which passes), so
// this drives the REAL streaming timing with MockAIProvider's DELAYED chunks +
// awaits each turn's completion (the existing test fires turn 2 before turn 1
// settles, so turn 2 supersedes turn 1 — it never exercises two SEQUENTIAL
// completed turns). If turn 2 hangs, `streamTask` never finishes → the timeout
// race fails the test deterministically (no wall-clock hang).
//
// @coordinates-with: AIChatViewModel+Streaming.swift, MockAIProvider.swift

import Testing
import Foundation
@testable import vreader

@Suite("AIChatViewModelTurn2Hang")
struct AIChatViewModelTurn2HangTests {

    @MainActor
    private func makeVM(store: MockChatSessionStore) -> AIChatViewModel {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: MockAIProvider(chunkDelayNanos: 5_000_000) // 5ms/chunk — real async timing
        )
        return AIChatViewModel(
            aiService: service,
            bookFingerprint: DocumentFingerprint(
                contentSHA256: String(repeating: "a", count: 64),
                fileByteCount: 1024, format: .epub),
            contextWindowSize: 10,
            chatSessionStore: store
        )
    }

    /// Wait for a turn's `runSend` task, but fail (return false) if it doesn't
    /// finish within `seconds` — so a HANG is a deterministic test failure.
    @MainActor
    private func finished(_ task: Task<Void, Never>?, within seconds: Double) async -> Bool {
        guard let task else { return true }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await task.value; return true }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test @MainActor func secondMessage_completes_doesNotHang() async {
        let store = MockChatSessionStore()
        let vm = makeVM(store: store)

        // Turn 1 — send AND wait for it to fully settle before turn 2.
        await vm.sendMessage("first question")
        let t1Done = await finished(vm.streamTask, within: 5)
        #expect(t1Done, "turn 1 must complete")
        #expect(vm.isLoading == false, "composer must re-enable after turn 1")
        let countAfterTurn1 = vm.messages.count
        #expect(countAfterTurn1 >= 2, "turn 1 should leave a user + assistant message")

        // Turn 2 — the reported hang. Must also complete + re-enable the composer.
        await vm.sendMessage("second question")
        let t2Done = await finished(vm.streamTask, within: 5)
        #expect(t2Done, "BUG #323: turn 2 must complete, not hang")
        #expect(vm.isLoading == false, "BUG #323: composer must re-enable after turn 2")
        #expect(vm.messages.count > countAfterTurn1, "turn 2 should append a reply")
        // The mock answer must be present (proves the streamed reply landed).
        #expect(vm.messages.contains { $0.role == .assistant && $0.content.contains("[MOCK]") })
    }

    /// Polls an async `condition` on the @MainActor, yielding (via a short sleep)
    /// between checks so an in-flight DETACHED send can make progress. Returns false
    /// on timeout — a deterministic failure, never a wall-clock hang.
    @MainActor
    private func waitUntil(timeout seconds: Double, _ condition: @MainActor () async -> Bool) async -> Bool {
        let iterations = max(1, Int(seconds * 1000 / 5))
        for _ in 0..<iterations {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)   // 5ms — yields the MainActor
        }
        return await condition()
    }

    /// Bug #323 — the PRIMARY (deterministic) cause: the user-visible turn
    /// completion must NOT be gated on the persistence save. Here turn 2's session
    /// save is STALLED on the serialized session lane (mirroring a slow cold-store
    /// `loadSessions()` still parked ahead of it). Once the save has actually PARKED
    /// (the reply already streamed and `runSend` reached `saveSettledTurn`), the
    /// composer MUST already be re-enabled (`isLoading == false`). Pre-fix, `runSend`
    /// awaits the stalled save BEFORE its `defer` resets `isLoading`, so `isLoading`
    /// stays true → the composer's `canSend` (`!isLoading`) is false → the Send
    /// button is disabled → the user can't send turn 2 ("second message hangs").
    @Test @MainActor func secondMessage_composerReEnables_whenSessionSaveStalls() async {
        let store = MockChatSessionStore()
        let vm = makeVM(store: store)

        // Turn 1 — completes normally; lazily creates the persisted session.
        await vm.sendMessage("first question")
        #expect(vm.isLoading == false, "composer re-enables after turn 1")
        #expect(vm.activeSessionId != nil, "turn 1 lazily created a session")
        let countAfterTurn1 = vm.messages.count

        // STALL the next session save (turn 2's update) on the serialized lane.
        await store.gateUpdate()

        // Turn 2 — launch DETACHED: pre-fix `sendMessage` never returns (it awaits
        // the stalled save), so awaiting it would hang. The bug is the FROZEN
        // COMPOSER, asserted via `isLoading` — independent of the send returning.
        let send2 = Task { @MainActor in await vm.sendMessage("second question") }

        // Wait until turn 2's save has actually PARKED on the gate — i.e. the reply
        // streamed and `runSend` reached the save. NOW the discriminator is live.
        let parked = await waitUntil(timeout: 5) { await store.parkedUpdateCount >= 1 }
        #expect(parked, "turn 2 reached the (stalled) session save")
        #expect(vm.messages.count > countAfterTurn1, "turn 2's reply landed before the save")
        #expect(
            vm.messages.contains { $0.role == .assistant && $0.content.contains("[MOCK]") },
            "the streamed reply is visible while the save is still parked")
        // THE BUG: with the save parked, the composer must already be usable.
        #expect(vm.isLoading == false,
            "BUG #323: composer must re-enable after the reply even while the session save is parked")

        // Release the parked save; bounded-drain the detached send (never hang the
        // suite — `finished` races the task against a timeout).
        await store.releaseUpdate()
        let drained = await finished(send2, within: 5)
        #expect(drained, "the detached send drained after the save was released")
        #expect(store.updateCallCount >= 1, "the settled turn eventually persisted")
    }
}
