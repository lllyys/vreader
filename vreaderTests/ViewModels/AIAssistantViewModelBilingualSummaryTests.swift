// Purpose: Feature #90 WI-1 — tests for the bilingual-summary VM logic on
// `AIAssistantViewModel` (the `+BilingualSummary.swift` extension):
// SummaryDisplayMode, the synchronous setters, the PRIVATE two-step translate
// helper (never clobbers `responseText`/`state`), the op-token race guard,
// retry, and the `cancelSummaryTranslation()` teardown wired into `reset()`.
//
// A GATEABLE provider double (`GatedAIProvider`) lets each test hold a
// translation in `.translating` to exercise the in-flight + race states the
// canned `StubAIProvider` cannot.

import Testing
import Foundation
@testable import vreader

@Suite("AIAssistantViewModel+BilingualSummary")
struct AIAssistantViewModelBilingualSummaryTests {

    // MARK: - Gateable provider double

    /// An `AIProvider` whose `sendRequest` blocks until the test releases a
    /// per-call gate, so tests can observe `.translating` and drive races.
    final class GatedAIProvider: AIProvider, @unchecked Sendable {
        let providerName = "Gated"

        /// Canned content returned to whichever translate call is released.
        /// Keyed in order; each release pops the next response.
        private let lock = NSLock()
        private var continuations: [CheckedContinuation<String, Error>] = []
        private(set) var sendRequestCallCount = 0
        private(set) var lastTargetLanguage: String?
        private(set) var lastContextText: String?
        private(set) var lastActionType: AIActionType?

        func sendRequest(_ request: AIRequest) async throws -> AIResponse {
            lock.withLock {
                sendRequestCallCount += 1
                lastTargetLanguage = request.targetLanguage
                lastContextText = request.contextText
                lastActionType = request.actionType
            }

            let content: String = try await withCheckedThrowingContinuation { cont in
                lock.withLock { continuations.append(cont) }
            }
            return AIResponse(
                content: content,
                actionType: request.actionType,
                promptVersion: request.promptVersion,
                createdAt: Date()
            )
        }

        /// Releases the oldest pending request with `content`.
        func release(_ content: String) {
            let cont = lock.withLock {
                continuations.isEmpty ? nil : continuations.removeFirst()
            }
            cont?.resume(returning: content)
        }

        /// Fails the oldest pending request.
        func fail(_ error: Error = AIError.providerError("translate down")) {
            let cont = lock.withLock {
                continuations.isEmpty ? nil : continuations.removeFirst()
            }
            cont?.resume(throwing: error)
        }

        var pendingCount: Int {
            lock.withLock { continuations.count }
        }

        func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        provider: any AIProvider
    ) -> AIAssistantViewModel {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: provider
        )
        return AIAssistantViewModel(aiService: service)
    }

    /// Drives the VM to a completed summary via the canned stub so tests can
    /// then run the translation half against a separate gated provider.
    @MainActor
    private func makeViewModelWithCompletedSummary(
        summary: String = "The chapter introduces the protagonist.",
        translationProvider: GatedAIProvider
    ) async -> AIAssistantViewModel {
        // First, complete a summary with a canned stub, then swap to the gated
        // provider by building a single service that the gated provider serves —
        // but `summarize` runs through the SAME service. To keep `responseText`
        // populated yet have the translate half gateable, we seed `responseText`
        // through a real summarize against a provider that returns immediately,
        // then point the VM's service at the gated provider for translation.
        let vm = makeViewModel(provider: translationProvider)
        // Seed a completed summary WITHOUT the provider (the gated provider would
        // block summarize too). Use the VM's own state seam via a direct summarize
        // path: release the summarize call immediately.
        async let summarizeTask: Void = vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some full book text for the summary.",
            format: .txt
        )
        // The summarize request is the first gated call — release it as the summary.
        await Task.yield()
        await waitUntil { translationProvider.pendingCount >= 1 }
        translationProvider.release(summary)
        await summarizeTask
        #expect(vm.state == .complete)
        #expect(vm.responseText == summary)
        return vm
    }

    /// Spins until `condition` is true or a generous deadline elapses. Runs on
    /// the MainActor (every test is `@MainActor`), so the predicate may read
    /// MainActor-isolated VM / provider state without crossing actor isolation.
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
    }

    // MARK: - originalOnly → no translation

    @Test @MainActor func originalOnlyDoesNotTranslate() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(translationProvider: provider)
        let summaryBefore = vm.responseText
        let countBefore = provider.sendRequestCallCount

        // Default mode is originalOnly.
        #expect(vm.summaryDisplayMode == .originalOnly)
        await vm.refreshSummaryTranslationIfNeeded()

        #expect(vm.summaryTranslation == .none)
        #expect(vm.responseText == summaryBefore)
        #expect(vm.state == .complete)
        #expect(provider.sendRequestCallCount == countBefore, "originalOnly must not call the provider")
    }

    // MARK: - Synchronous pure setters

    @Test @MainActor func settersAreSynchronousPureMutators() async {
        let provider = GatedAIProvider()
        let vm = makeViewModel(provider: provider)

        vm.setSummaryDisplayMode(.interlinear)
        #expect(vm.summaryDisplayMode == .interlinear)

        let italian = BilingualLanguage.find(key: "Italian")!
        vm.setSummaryTargetLanguage(italian)
        #expect(vm.summaryTargetLanguage == italian)

        // Setters do NOT kick translation (no provider call, no state change).
        #expect(provider.sendRequestCallCount == 0)
        #expect(vm.summaryTranslation == .none)
    }

    @Test @MainActor func defaultTargetLanguageIsFirstBilingualLanguage() {
        let vm = makeViewModel(provider: GatedAIProvider())
        #expect(vm.summaryTargetLanguage == BilingualLanguage.all.first)
    }

    // MARK: - translatedOnly / interlinear → kick translation via PRIVATE helper

    @Test @MainActor func translatedOnlyKicksTranslationWithoutClobberingSummary() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(
            summary: "Original summary text.", translationProvider: provider
        )
        let summary = vm.responseText
        vm.setSummaryDisplayMode(.translatedOnly)
        vm.setSummaryTargetLanguage(BilingualLanguage.find(key: "Chinese")!)

        async let refresh: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }

        // In-flight: summary + state untouched while translating.
        #expect(vm.summaryTranslation == .translating)
        #expect(vm.responseText == summary, "responseText must NOT be clobbered")
        #expect(vm.state == .complete, "state must NOT be clobbered")
        #expect(vm.currentAction == .summarize, "currentAction must NOT be clobbered")

        // The private helper sent a .translate request with the SUMMARY as input.
        #expect(provider.lastActionType == .translate)
        #expect(provider.lastContextText == summary)
        #expect(provider.lastTargetLanguage == "Chinese")

        provider.release("翻译后的摘要。")
        await refresh

        #expect(vm.summaryTranslation == .translated("翻译后的摘要。"))
        #expect(vm.responseText == summary, "summary still preserved after success")
        #expect(vm.state == .complete)
    }

    @Test @MainActor func interlinearKicksTranslation() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(translationProvider: provider)
        let summary = vm.responseText
        vm.setSummaryDisplayMode(.interlinear)

        async let refresh: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }
        provider.release("interlinear translation")
        await refresh

        #expect(vm.summaryTranslation == .translated("interlinear translation"))
        #expect(vm.responseText == summary)
    }

    @Test @MainActor func translationFailurePreservesSummary() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(
            summary: "Keep me.", translationProvider: provider
        )
        vm.setSummaryDisplayMode(.translatedOnly)

        async let refresh: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }
        provider.fail()
        await refresh

        #expect(vm.summaryTranslation == .failed)
        #expect(vm.responseText == "Keep me.", "summary preserved on failure")
        #expect(vm.state == .complete)
    }

    // MARK: - No summary yet → no-op

    @Test @MainActor func refreshIsNoOpWithoutCompletedSummary() async {
        let provider = GatedAIProvider()
        let vm = makeViewModel(provider: provider)
        vm.setSummaryDisplayMode(.translatedOnly)
        // No summary has run; responseText empty, state idle.
        await vm.refreshSummaryTranslationIfNeeded()

        #expect(vm.summaryTranslation == .none)
        #expect(provider.sendRequestCallCount == 0)
    }

    @Test @MainActor func reSummarizeSupersedesInFlightTranslation() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(
            summary: "Summary A.", translationProvider: provider
        )
        vm.setSummaryDisplayMode(.translatedOnly)
        vm.setSummaryTargetLanguage(BilingualLanguage.find(key: "Chinese")!)

        // Translation for summary A in flight (gated). Wait until its request has
        // actually REACHED the provider (pendingCount), not just `.translating`
        // (which is set before the child task hits sendRequest) — so the FIFO
        // release below deterministically targets translation A (Gate-4 r2).
        async let translateA: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }
        await waitUntil { provider.pendingCount >= 1 }

        // Re-summarize: a NEW summarize() runs through performAction, which must
        // cancel the in-flight summary translation (Gate-4 r1 High) — a
        // re-summarize does NOT go through reset(), so the teardown lives in
        // performAction.
        async let reSummarize: Void = vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Full text for summary B.",
            format: .txt
        )
        await waitUntil { vm.summaryTranslation == .none }
        #expect(vm.summaryTranslation == .none,
                "a re-summarize cancels the in-flight summary translation")

        // Release the STALE translation A; the cancelled task must NOT clobber.
        provider.release("STALE-translation-A")
        await translateA
        #expect(vm.summaryTranslation != .translated("STALE-translation-A"),
                "a translation of the OLD summary must not land after a re-summarize")

        // Drain: release the new summarize as summary B.
        await waitUntil { provider.pendingCount >= 1 }
        provider.release("Summary B.")
        await reSummarize
        #expect(vm.responseText == "Summary B.")
    }

    // MARK: - Retry

    @Test @MainActor func retrySummaryTranslationRerunsOnlyTranslation() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(
            summary: "Summary.", translationProvider: provider
        )
        vm.setSummaryDisplayMode(.translatedOnly)

        async let refresh: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }
        provider.fail()
        await refresh
        #expect(vm.summaryTranslation == .failed)
        let summaryBefore = vm.responseText

        async let retry: Void = vm.retrySummaryTranslation()
        await waitUntil { vm.summaryTranslation == .translating }
        provider.release("retried translation")
        await retry

        #expect(vm.summaryTranslation == .translated("retried translation"))
        #expect(vm.responseText == summaryBefore, "retry does not touch the summary")
        #expect(vm.state == .complete)
    }

    // MARK: - Cancel / supersede races (op-token guard)

    @Test @MainActor func languageChangeSupersedesInFlightTranslation() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(
            summary: "Race summary.", translationProvider: provider
        )
        vm.setSummaryDisplayMode(.translatedOnly)
        vm.setSummaryTargetLanguage(BilingualLanguage.find(key: "Chinese")!)

        // First translation in flight.
        async let first: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }

        // Language change → supersede: setter + a new refresh.
        vm.setSummaryTargetLanguage(BilingualLanguage.find(key: "French")!)
        async let second: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { provider.pendingCount >= 2 }

        // Release the STALE (first) translation first; it must NOT clobber.
        provider.release("STALE-chinese")
        await first
        #expect(vm.summaryTranslation != .translated("STALE-chinese"),
                "a superseded translation must not win")

        // Release the live (second) translation.
        provider.release("fresh-french")
        await second
        #expect(vm.summaryTranslation == .translated("fresh-french"))
    }

    @Test @MainActor func modeFlipCancelsInFlightTranslation() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(translationProvider: provider)
        vm.setSummaryDisplayMode(.translatedOnly)

        async let first: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }

        // Flip back to originalOnly → cancels + resets translation.
        vm.setSummaryDisplayMode(.originalOnly)
        await vm.refreshSummaryTranslationIfNeeded()
        #expect(vm.summaryTranslation == .none)

        // Even if the stale translate now returns, it must not write.
        provider.release("STALE")
        await first
        #expect(vm.summaryTranslation == .none, "originalOnly stays none after stale return")
    }

    // MARK: - Cancel + reset teardown

    @Test @MainActor func cancelSummaryTranslationResetsToNone() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(translationProvider: provider)
        vm.setSummaryDisplayMode(.translatedOnly)

        async let refresh: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }

        vm.cancelSummaryTranslation()
        #expect(vm.summaryTranslation == .none)

        provider.release("STALE")
        await refresh
        #expect(vm.summaryTranslation == .none, "no stale write after cancel")
    }

    @Test @MainActor func resetCancelsInFlightTranslation() async {
        let provider = GatedAIProvider()
        let vm = await makeViewModelWithCompletedSummary(translationProvider: provider)
        vm.setSummaryDisplayMode(.translatedOnly)

        async let refresh: Void = vm.refreshSummaryTranslationIfNeeded()
        await waitUntil { vm.summaryTranslation == .translating }

        vm.reset()
        #expect(vm.summaryTranslation == .none)
        #expect(vm.state == .idle)
        #expect(vm.responseText.isEmpty)

        provider.release("STALE")
        await refresh
        #expect(vm.summaryTranslation == .none, "reset-while-translating leaves no stale write")
    }
}
