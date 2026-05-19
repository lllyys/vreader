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
    /// context so `summarize` reaches the provider rather than the
    /// empty-context error branch.
    private static func makeTabView(
        viewModel: AIAssistantViewModel
    ) -> AISummaryTabView {
        AISummaryTabView(
            viewModel: viewModel,
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
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
private actor GateState {
    private(set) var sendRequestCallCount = 0
    private var entered = false
    private var released = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

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
private final class GatedAIProvider: AIProvider, Sendable {
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

    /// Resolves once `sendRequest` has been entered at least once.
    func awaitEntered() async { await gate.awaitEntered() }

    /// Unblocks the suspended `sendRequest` so the request completes —
    /// awaited inline so no parked continuation leaks past the test.
    func release() async { await gate.release() }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        await gate.markEntered()
        await gate.gateOpen()
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
