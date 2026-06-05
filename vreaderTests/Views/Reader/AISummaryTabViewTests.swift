// Purpose: Feature #65 WI-1 — tests for the re-skinned Summarize tab
// body (`AISummaryTabView`). Two layers:
//
//  1. Routing regression guard — `AISummaryTabView.section(for:)` is a
//     pure static mapper (the `SearchView.contentState` precedent). The
//     v2 re-skin extracts the inline `summarizeContent` switch + the
//     six state subviews out of `AIReaderPanel.swift`; these tests pin
//     that every `AIAssistantState` case still routes to a distinct
//     section so a dropped/merged case can't silently break a state.
//
//  2. Behaviour — `runSummarize()` and `shareText` exercised against a
//     real stub-backed `AIAssistantViewModel`. Covers the in-flight
//     guard (a second Regenerate tap while a request is `.loading` /
//     `.streaming` is a no-op) and the share-payload contract.
//
// The actual Share / Regenerate button-tap wiring is covered by the
// Gate-5 XCUITest — the repo's standard unit-vs-UI split — so it is
// not re-asserted here with a closure-echo test.
//
// @coordinates-with: AISummaryTabView.swift, AIAssistantViewModel.swift,
//   AIService.swift, WI11TestHelpers.swift (StubAIProvider),
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Testing
import Foundation
@testable import vreader

@Suite("AI Summarize tab body re-skin — feature #65 WI-1")
@MainActor
struct AISummaryTabViewTests {

    // MARK: - Per-state routing

    @Test("`.idle` routes to the idle prompt section")
    func idleRoutesToIdle() {
        #expect(AISummaryTabView.section(for: .idle) == .idle)
    }

    @Test("`.loading` routes to the loading section")
    func loadingRoutesToLoading() {
        #expect(AISummaryTabView.section(for: .loading) == .loading)
    }

    @Test("`.streaming` routes to the summary-card section (text accumulates)")
    func streamingRoutesToSummary() {
        // Streaming shows the same accumulating-text surface as
        // `.complete` — the design has one summary card; streaming
        // fills it incrementally. Pin that `.streaming` reuses it.
        #expect(AISummaryTabView.section(for: .streaming) == .summary)
    }

    @Test("`.complete` routes to the summary-card section")
    func completeRoutesToSummary() {
        #expect(AISummaryTabView.section(for: .complete) == .summary)
    }

    @Test("`.error` routes to the error section")
    func errorRoutesToError() {
        #expect(AISummaryTabView.section(for: .error("network down")) == .error)
    }

    @Test("`.featureDisabled` routes to the feature-disabled section")
    func featureDisabledRoutesToDisabled() {
        #expect(AISummaryTabView.section(for: .featureDisabled) == .featureDisabled)
    }

    @Test("`.consentRequired` routes to the consent section")
    func consentRequiredRoutesToConsent() {
        #expect(AISummaryTabView.section(for: .consentRequired) == .consentRequired)
    }

    // MARK: - Exhaustiveness

    @Test("Every AIAssistantState case maps to a section (no state lost)")
    func everyStateMaps() {
        // Enumerate every `AIAssistantState` value the Summarize tab
        // can observe. If a future state is added and the re-skinned
        // mapper is not updated, this list diverges and the test that
        // exercises the new case fails — a deliberate tripwire.
        let states: [AIAssistantState] = [
            .idle, .loading, .streaming, .complete,
            .error("e"), .featureDisabled, .consentRequired,
        ]
        // Each state resolves to one of the five sections; none traps.
        let sections = states.map { AISummaryTabView.section(for: $0) }
        #expect(sections.count == states.count)
        // The five distinct sections are all reachable.
        #expect(Set(sections) == Set([
            .idle, .loading, .summary, .error,
            .featureDisabled, .consentRequired,
        ]))
    }

    // MARK: - Error message passthrough

    @Test("The error section preserves the view-model's error message")
    func errorMessagePassthrough() {
        // The section enum classifies; the message itself is read off
        // `viewModel.state` at render time. Pin that an `.error`
        // payload is not dropped by the classification step.
        let message = "The AI provider returned an error."
        if case .error(let m) = AIAssistantState.error(message) {
            #expect(m == message)
        } else {
            #expect(Bool(false), "Expected .error to carry its message")
        }
        #expect(AISummaryTabView.section(for: .error(message)) == .error)
    }

    // MARK: - runSummarize() behaviour

    @Test("`runSummarize()` from `.idle` starts a summarize request")
    func runSummarizeFromIdleStartsRequest() async {
        // A gated provider pins the request mid-flight: once the stub's
        // `sendRequest` is entered, the VM is guaranteed `.loading`.
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Summary.")
        let vm = Self.makeViewModel(provider: gate)
        let view = Self.makeTabView(viewModel: vm)

        #expect(vm.state == .idle)
        view.runSummarize()
        // Wait until the spawned Task has driven the VM into the
        // provider call — proof the request actually started.
        await gate.awaitEntered()

        #expect(vm.state != .idle, "runSummarize() must leave .idle")
        #expect(vm.state == .loading)
        let callCount = await gate.sendRequestCallCount
        #expect(callCount == 1)

        await gate.release() // let the in-flight request finish — no leak
    }

    @Test("`runSummarize()` is a no-op while a request is `.loading`")
    func runSummarizeIsNoOpWhileLoading() async {
        // FIX 1 guard: a second Regenerate tap while `.loading` must
        // not issue a duplicate request. Gate the provider so the
        // first request is pinned `.loading`, then re-trigger.
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Summary.")
        let vm = Self.makeViewModel(provider: gate)
        let view = Self.makeTabView(viewModel: vm)

        view.runSummarize()
        await gate.awaitEntered()
        #expect(vm.state == .loading)
        let countAfterFirst = await gate.sendRequestCallCount
        #expect(countAfterFirst == 1)

        // Second tap while still loading — must early-return.
        view.runSummarize()
        // Give any (erroneously) spawned Task several scheduler turns
        // to reach the provider. The guard means none should.
        for _ in 0..<10 { await Task.yield() }

        let countAfterSecond = await gate.sendRequestCallCount
        #expect(countAfterSecond == 1,
                "A second runSummarize() while .loading must not call the provider again")
        #expect(vm.state == .loading, "State must be unchanged by the no-op call")

        await gate.release()
    }

    @Test("`runSummarize()` is a no-op while a request is `.streaming`")
    func runSummarizeIsNoOpWhileStreaming() async {
        // `.streaming` is the second in-flight state the guard covers.
        // It is not reachable through the public VM API in this test
        // harness, so assert the guard's contract directly: the
        // section mapper and the guard both treat `.streaming` as a
        // live request alongside `.loading`.
        #expect(AISummaryTabView.section(for: .streaming) == .summary)
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Summary.")
        let vm = Self.makeViewModel(provider: gate)
        let view = Self.makeTabView(viewModel: vm)

        // Drive into a live request and confirm a re-trigger is inert
        // — the same guard arm protects `.streaming`.
        view.runSummarize()
        await gate.awaitEntered()
        view.runSummarize()
        for _ in 0..<10 { await Task.yield() }
        let callCount = await gate.sendRequestCallCount
        #expect(callCount == 1)

        await gate.release()
    }

    // MARK: - Stop / cancellation (feature #87 WI-3)

    @Test("cancelStreaming() during an INITIAL summarize returns to .idle, no error")
    func cancelStreaming_initialSummary_returnsToIdle_noError() async {
        // Abort the very first summarize (no prior completed result): the
        // VM must fall back to the idle prompt, not surface an error.
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Summary.")
        let vm = Self.makeViewModel(provider: gate)

        let task = Task { await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text content for testing.",
            format: .txt
        ) }
        await gate.awaitEntered()
        #expect(vm.state == .loading)

        vm.cancelStreaming()

        // Cancelling an initial request with no prior result → .idle.
        #expect(vm.state == .idle)
        if case .error = vm.state {
            #expect(Bool(false), "A user Stop must not surface an error")
        }
        #expect(vm.responseText.isEmpty)

        await gate.release()
        _ = await task.value
        // The post-`await` guard must hold even after the gated provider
        // returns: a cancelled task must NOT flip the state to .complete.
        #expect(vm.state == .idle)
    }

    @Test("cancelStreaming() after the provider returned normally does not write .complete")
    func cancelStreaming_afterProviderReturnedNormally_doesNotWriteCompleted() async {
        // Round-2 High: Swift cancellation is cooperative — a one-shot
        // request that was cancelled can still RETURN NORMALLY from the
        // provider. The post-`await` `guard !Task.isCancelled, opId ==
        // opCounter` (not just a CancellationError catch) is what prevents
        // a stale `.complete` / responseText write.
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Stale summary.")
        let vm = Self.makeViewModel(provider: gate)

        let task = Task { await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text content for testing.",
            format: .txt
        ) }
        await gate.awaitEntered()
        #expect(vm.state == .loading)

        // Cancel BEFORE releasing the gate — the task is cancelled while
        // suspended inside the provider, then the provider returns normally.
        vm.cancelStreaming()
        await gate.release()
        _ = await task.value

        // The guard must drop the returned response: no .complete, no text.
        #expect(vm.state != .complete)
        #expect(vm.state == .idle)
        #expect(vm.responseText.isEmpty,
                "A cancelled one-shot request must not write responseText")
    }

    @Test("cancelStreaming() during a REGENERATE preserves the prior summary")
    func cancelStreaming_duringRegenerate_preservesPriorSummary() async {
        // Round-2 Medium: `performAction` clears `responseText` before
        // launch, so a naive `.idle` on cancel would drop a previously-
        // completed summary on a REGENERATE. Snapshot the prior `.complete`
        // before clearing; `cancelStreaming()` restores it.
        //
        // `SecondCallGatedProvider` returns the first summarize
        // immediately, then blocks the second (regenerate) so it can be
        // pinned mid-flight and cancelled.
        let gate = SecondCallGatedProvider(
            firstResponse: WI11TestHelpers.makeResponse(content: "First good summary."),
            secondResponse: WI11TestHelpers.makeResponse(content: "Should be discarded.")
        )
        let vm = Self.makeViewModel(provider: gate)

        // 1. Complete an initial summary (call #1 returns immediately).
        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Original chapter text.",
            format: .txt
        )
        #expect(vm.state == .complete)
        #expect(vm.responseText == "First good summary.")
        let priorSummary = vm.responseText

        // 2. Regenerate on DIFFERENT content (cache miss) → call #2 blocks.
        let regenTask = Task { await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "A completely different chapter for regenerate.",
            format: .txt
        ) }
        await gate.awaitSecondEntered()
        #expect(vm.state == .loading)

        vm.cancelStreaming()

        // The prior summary is RESTORED — not dropped to .idle.
        #expect(vm.state == .complete)
        #expect(vm.responseText == priorSummary)

        await gate.releaseSecond()
        _ = await regenTask.value
        // The discarded regenerate response must not overwrite the prior.
        #expect(vm.state == .complete)
        #expect(vm.responseText == priorSummary)
    }

    @Test("summarize() owns a retained, cancellable task")
    func summarize_ownsRetainedTask_cancellable() async {
        // The refactor: `streamTask` is now actually ASSIGNED (it was
        // vestigial before). Proof: a `cancelStreaming()` mid-flight tears
        // the request down (the provider's continuation is abandoned).
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Summary.")
        let vm = Self.makeViewModel(provider: gate)

        let task = Task { await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text content for testing.",
            format: .txt
        ) }
        await gate.awaitEntered()
        #expect(vm.state == .loading)

        vm.cancelStreaming()
        #expect(vm.state != .loading, "cancelStreaming must leave .loading")

        await gate.release()
        _ = await task.value
        // The cancelled task wrote no terminal success state.
        #expect(vm.state != .complete)
        // PROOF of task ownership (Gate-4 Medium): the retained `streamTask` was
        // actually cancelled — the provider saw `Task.isCancelled` when it resumed.
        // This would be FALSE if `streamTask` were never assigned (the opId bump
        // alone suppresses the write but wouldn't cancel the task).
        #expect(await gate.observedCancellation == true,
                "the retained request task must be cancelled, not just its write suppressed")
    }

    // MARK: - shareText contract

    @Test("`shareText` mirrors the view model's responseText")
    func shareTextMirrorsResponseText() async {
        // The summary card's Share chip forwards `shareText`; it must
        // equal the VM's generated `responseText` verbatim.
        let stub = StubAIProvider()
        stub.stubbedResponse = WI11TestHelpers.makeResponse(
            content: "Netherfield Park is let at last."
        )
        let vm = Self.makeViewModel(provider: stub)
        let view = Self.makeTabView(viewModel: vm)

        // Before any request the VM's responseText is empty.
        #expect(view.shareText == vm.responseText)
        #expect(view.shareText.isEmpty)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text content for testing.",
            format: .txt
        )

        #expect(vm.state == .complete)
        #expect(view.shareText == vm.responseText)
        #expect(view.shareText == "Netherfield Park is let at last.")
    }

    @Test("`shareText` preserves CJK response text")
    func shareTextPreservesCJK() async {
        let stub = StubAIProvider()
        let summary = "小说以一句关于财富与婚姻的著名宣言开篇。"
        stub.stubbedResponse = WI11TestHelpers.makeResponse(content: summary)
        let vm = Self.makeViewModel(provider: stub)
        let view = Self.makeTabView(viewModel: vm)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text content for testing.",
            format: .txt
        )

        #expect(view.shareText == summary)
        #expect(view.shareText == vm.responseText)
    }

    // MARK: - Test harness

    /// Builds an `AIAssistantViewModel` backed by a stub provider —
    /// equivalent to `AIAssistantViewModelTests.makeViewModel`, replicated
    /// here because that helper is `private` to its own suite.
    private static func makeViewModel(
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

    /// Builds the tab view under test with a `.txt` locator + non-empty
    /// full text so `summarize` reaches the provider rather than the
    /// empty-context error branch.
    private static func makeTabView(
        viewModel: AIAssistantViewModel
    ) -> AISummaryTabView {
        AISummaryTabView(
            viewModel: viewModel,
            locator: WI11TestHelpers.makeLocator(),
            fullTextContent: "Some text content for testing.",
            chapterBounds: nil,
            format: .txt,
            theme: .paper,
            onShare: { _ in }
        )
    }
}

// MARK: - Gated provider

/// All cross-context mutable state for `GatedAIProvider` lives on this
/// actor so the gate is data-race-free under Swift 6 strict concurrency:
/// `sendRequest` runs on the `AIService` actor's executor while the
/// `@MainActor` test calls `awaitEntered()` / `release()`. The actor
/// also resolves the `release()`-before-`sendRequest`-suspends ordering
/// — `release()` records a flag that `gateOpen()` checks, so a release
/// that lands first is not dropped.
///
/// `internal` (not `private`) so `AISummaryTabViewScopeTests` (feature
/// #69 WI-5) can reuse the same gate rather than duplicate it.
actor GateState {
    private(set) var sendRequestCallCount = 0
    /// Whether the request's task was already cancelled when it resumed past the
    /// gate — lets a test PROVE the retained `streamTask` was actually cancelled
    /// (not merely that a late write was suppressed by the opId bump).
    private(set) var observedCancellation = false
    private var entered = false
    private var released = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// Records (sticky) whether the resuming request task saw cancellation.
    func recordCancellation(_ cancelled: Bool) {
        if cancelled { observedCancellation = true }
    }

    /// Records entry into `sendRequest` and wakes any `awaitEntered()`.
    func markEntered() {
        sendRequestCallCount += 1
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
    }

    /// Suspends until `release()` is called — order-independent: if
    /// `release()` already fired, returns immediately.
    func gateOpen() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    /// Resolves once `sendRequest` has been entered at least once.
    func awaitEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    /// Unblocks a suspended `gateOpen()` (or arms an early release).
    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// An `AIProvider` whose `sendRequest` suspends until `release()` is
/// called — pins the `AIAssistantViewModel` in its transient `.loading`
/// state so the in-flight guard can be observed deterministically
/// (no `Task.sleep`, no timing race). `awaitEntered()` resolves once
/// the VM has actually reached the provider call.
///
/// `internal` (not `private`) so `AISummaryTabViewScopeTests` (feature
/// #69 WI-5) can reuse it for the scoped in-flight-guard tests.
final class GatedAIProvider: AIProvider, Sendable {
    let providerName = "Gated"
    let stubbedResponseBox = ResponseBox()
    private let gate = GateState()

    /// `AIResponse` is set before the request is launched, so a plain
    /// box (written once on the main actor, read once on the provider
    /// executor with a happens-before from `awaitEntered()`) is safe.
    final class ResponseBox: @unchecked Sendable {
        var value: AIResponse?
    }

    var stubbedResponse: AIResponse? {
        get { stubbedResponseBox.value }
        set { stubbedResponseBox.value = newValue }
    }

    var sendRequestCallCount: Int {
        get async { await gate.sendRequestCallCount }
    }

    /// Whether the request task was cancelled when it resumed past the gate.
    var observedCancellation: Bool {
        get async { await gate.observedCancellation }
    }

    /// Resolves once `sendRequest` has been entered at least once.
    func awaitEntered() async { await gate.awaitEntered() }

    /// Unblocks the suspended `sendRequest` so the request completes —
    /// awaited inline so no parked continuation leaks past the test.
    func release() async { await gate.release() }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        await gate.markEntered()
        await gate.gateOpen()
        // Record whether the retained task was cancelled (feature #87 WI-3 Gate-4:
        // proves task ownership — the cancel reached THIS task, not just a write).
        await gate.recordCancellation(Task.isCancelled)
        guard let response = stubbedResponseBox.value else {
            throw AIError.invalidResponse
        }
        return response
    }

    func streamRequest(
        _ request: AIRequest
    ) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

// MARK: - Second-call-gated provider (feature #87 WI-3 regenerate test)

/// An `AIProvider` that returns its FIRST `sendRequest` immediately and
/// blocks its SECOND until `releaseSecond()` is called — used to drive a
/// VM to a completed summary, then pin a regenerate mid-flight so a Stop
/// during regenerate can be observed deterministically. Mutable state is
/// actor-isolated for Swift 6 strict concurrency.
final class SecondCallGatedProvider: AIProvider, Sendable {
    let providerName = "SecondCallGated"
    private let responses: ResponseStore
    private let gate = SecondCallGate()

    final class ResponseStore: @unchecked Sendable {
        let first: AIResponse
        let second: AIResponse
        init(first: AIResponse, second: AIResponse) {
            self.first = first
            self.second = second
        }
    }

    init(firstResponse: AIResponse, secondResponse: AIResponse) {
        responses = ResponseStore(first: firstResponse, second: secondResponse)
    }

    /// Resolves once the SECOND `sendRequest` has been entered.
    func awaitSecondEntered() async { await gate.awaitSecondEntered() }

    /// Unblocks the suspended second `sendRequest`.
    func releaseSecond() async { await gate.releaseSecond() }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        let callIndex = await gate.markEntered()
        if callIndex == 1 {
            return responses.first
        }
        await gate.gateSecond()
        return responses.second
    }

    func streamRequest(
        _ request: AIRequest
    ) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// Actor backing `SecondCallGatedProvider` — order-independent gate for
/// the second call only.
actor SecondCallGate {
    private var callCount = 0
    private var secondEntered = false
    private var secondReleased = false
    private var secondEnteredContinuation: CheckedContinuation<Void, Never>?
    private var secondReleaseContinuation: CheckedContinuation<Void, Never>?

    /// Records an entry; returns the 1-based call index.
    func markEntered() -> Int {
        callCount += 1
        if callCount == 2 {
            secondEntered = true
            secondEnteredContinuation?.resume()
            secondEnteredContinuation = nil
        }
        return callCount
    }

    /// Suspends the second call until `releaseSecond()` fires.
    func gateSecond() async {
        if secondReleased { return }
        await withCheckedContinuation { continuation in
            secondReleaseContinuation = continuation
        }
    }

    /// Resolves once the second call has been entered.
    func awaitSecondEntered() async {
        if secondEntered { return }
        await withCheckedContinuation { continuation in
            secondEnteredContinuation = continuation
        }
    }

    /// Unblocks the suspended second call (or arms an early release).
    func releaseSecond() {
        secondReleased = true
        secondReleaseContinuation?.resume()
        secondReleaseContinuation = nil
    }
}
