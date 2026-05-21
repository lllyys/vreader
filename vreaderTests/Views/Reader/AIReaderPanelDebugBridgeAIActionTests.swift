// Purpose: Tests for AIReaderPanel.handleDebugAIAction — the Bug #255
// DebugBridge AI-action observer. Pins the fidelity invariant behaviorally:
// the harness fires the SAME view-model path the chrome buttons take
// (summarize with the in-flight guard + scope; chat with the isLoading
// gate; translate with the language override), with NO duplicate/parallel
// AI call. Mirrors AISummaryTabViewTests' gated-provider technique.

#if DEBUG
#if canImport(UIKit)

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("AIReaderPanel DebugBridge AI-action observer (Bug #255)")
struct AIReaderPanelDebugBridgeAIActionTests {

    // MARK: - summarize

    @Test("summarize fires the same VM summarize path the Summarize button takes")
    func summarizeFiresViewModelPath() async {
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Summary.")
        let env = makeEnvironment(summarizeProvider: gate)

        #expect(env.summaryVM.state == .idle)
        env.panel.handleDebugAIAction(action: "summarize", scope: nil, text: nil)
        await gate.awaitEntered()

        #expect(env.summaryVM.state == .loading,
                "summarize must drive the VM into the provider call — the real summarize path")
        let count = await gate.sendRequestCallCount
        #expect(count == 1)

        await gate.release()
    }

    @Test("summarize applies the URL scope override before running (chip-tap path)")
    func summarizeAppliesScopeOverride() async {
        // `setScope` runs synchronously before the spawned summarize Task, so
        // assert the scope mutation directly — no need to await the provider
        // (which a `.bookSoFar` scope at offset 0 would never reach via the
        // empty-context error branch). This isolates the scope-override
        // contract from the request lifecycle.
        let env = makeEnvironment(summarizeProvider: ImmediateSummaryProvider())

        #expect(env.summaryVM.selectedScope == .section, "default scope is Section")
        env.panel.handleDebugAIAction(action: "summarize", scope: "bookSoFar", text: nil)

        #expect(env.summaryVM.selectedScope == .bookSoFar,
                "the scope override must be applied via setScope — the same chip-tap path")
    }

    @Test("summarize with no scope keeps the panel's current scope chip")
    func summarizeNoScopeKeepsCurrentChip() async {
        let env = makeEnvironment(summarizeProvider: ImmediateSummaryProvider())
        env.summaryVM.setScope(.chapter)

        env.panel.handleDebugAIAction(action: "summarize", scope: nil, text: nil)

        #expect(env.summaryVM.selectedScope == .chapter,
                "a scopeless summarize must NOT reset the panel's selected chip")
    }

    @Test("summarize is a no-op while a request is already in flight (in-flight guard)")
    func summarizeNoOpWhileLoading() async {
        let gate = GatedAIProvider()
        gate.stubbedResponse = WI11TestHelpers.makeResponse(content: "Summary.")
        let env = makeEnvironment(summarizeProvider: gate)

        env.panel.handleDebugAIAction(action: "summarize", scope: nil, text: nil)
        await gate.awaitEntered()
        #expect(env.summaryVM.state == .loading)
        let afterFirst = await gate.sendRequestCallCount
        #expect(afterFirst == 1)

        // Second fire while still loading — the same guard runSummarize() has.
        env.panel.handleDebugAIAction(action: "summarize", scope: nil, text: nil)
        for _ in 0..<10 { await Task.yield() }

        let afterSecond = await gate.sendRequestCallCount
        #expect(afterSecond == 1,
                "a re-fire while .loading must not issue a duplicate summarize request")
        await gate.release()
    }

    // MARK: - chat (the High-severity Codex round-1 fix: isLoading gate)

    @Test("chat sends the message through the VM (same path as the send button)")
    func chatSendsMessage() async {
        let stub = ImmediateChatProvider()
        let env = makeEnvironment(chatProvider: stub)

        env.panel.handleDebugAIAction(action: "chat", scope: nil, text: "who is the narrator?")
        // Poll until the assistant reply has streamed in — the VM appends an
        // empty assistant message first, then accumulates the chunk, so wait
        // for the non-empty content (deterministic, no count race). This
        // proves the real sendMessage path consumed the stream end-to-end.
        await pollUntil {
            env.chatVM.messages.contains { $0.role == .assistant && !$0.content.isEmpty }
        }

        #expect(env.chatVM.messages.contains { $0.role == .user && $0.content == "who is the narrator?" },
                "the user message must be appended via the real sendMessage path")
        #expect(env.chatVM.messages.contains { $0.role == .assistant && $0.content == "Reply." },
                "the assistant reply must stream in via the real sendMessage path")
        let count = await stub.streamCallCount
        #expect(count == 1)
    }

    @Test("chat is a no-op while a chat request is already in flight (isLoading gate)")
    func chatNoOpWhileLoading() async {
        // Codex round-1 High: the chat handler must mirror AIChatView's
        // `canSend` gate (disabled while isLoading). AIChatViewModel does NOT
        // coalesce, so without the guard two rapid fires start overlapping
        // requests the chrome button cannot trigger. Gate the stream so the
        // first request is pinned isLoading, then re-fire.
        let stub = GatedChatProvider()
        let env = makeEnvironment(chatProvider: stub)

        env.panel.handleDebugAIAction(action: "chat", scope: nil, text: "first")
        await stub.awaitEntered()
        #expect(env.chatVM.isLoading, "first chat request must pin isLoading")
        let afterFirst = await stub.streamCallCount
        #expect(afterFirst == 1)

        // Second fire while loading — must early-return on the isLoading gate.
        env.panel.handleDebugAIAction(action: "chat", scope: nil, text: "second")
        for _ in 0..<10 { await Task.yield() }

        let afterSecond = await stub.streamCallCount
        #expect(afterSecond == 1,
                "a chat re-fire while isLoading must not start a second overlapping request")
        await stub.release()
    }

    // MARK: - translate

    @Test("translate runs with the language override (same path as the pill tap)")
    func translateWithLanguageOverride() async {
        let stub = ImmediateTranslateProvider()
        let env = makeEnvironment(translateProvider: stub)

        env.panel.handleDebugAIAction(action: "translate", scope: nil, text: "Spanish")
        // Poll on observable VM state — translatedText is set only after the
        // real translate path completes (deterministic, no count race).
        await pollUntil { env.translateVM.translatedText != nil }

        #expect(env.translateVM.targetLanguage == "Spanish",
                "the URL `text` override must set the translate target language")
        #expect(env.translateVM.translatedText == "Translated.",
                "the translation result must arrive via the real translate path")
        let count = await stub.sendCallCount
        #expect(count == 1)
    }

    @Test("translate with no override uses the VM's current target language")
    func translateNoOverrideUsesCurrentLanguage() async {
        let stub = ImmediateTranslateProvider()
        let env = makeEnvironment(translateProvider: stub)
        // Default targetLanguage is "Chinese".
        let original = env.translateVM.targetLanguage

        env.panel.handleDebugAIAction(action: "translate", scope: nil, text: nil)
        for _ in 0..<20 { await Task.yield() }

        #expect(env.translateVM.targetLanguage == original,
                "a translate with no `text` must keep the pre-selected target language")
    }

    // MARK: - tab routing

    @Test("each action lands the panel on the matching tab")
    func eachActionLandsOnMatchingTab() async {
        // The observer switches selectedTab so a post-action snapshot
        // reflects the right surface. Assert via the pure effect mapper that
        // backs the observer's tab decision (the observer sets
        // `selectedTab = effect.tab`).
        #expect(DebugAIActionEffect.resolve(action: .summarize, scope: nil, text: nil).tab == .summarize)
        #expect(DebugAIActionEffect.resolve(action: .chat, scope: nil, text: "hi").tab == .chat)
        #expect(DebugAIActionEffect.resolve(action: .translate, scope: nil, text: nil).tab == .translate)
    }

    @Test("an unknown action string is ignored (no crash)")
    func unknownActionIsIgnored() async {
        let env = makeEnvironment()
        // Should not crash or mutate state — the parser validates AIActionKind,
        // but the observer must be defensive.
        env.panel.handleDebugAIAction(action: "explode", scope: nil, text: nil)
        #expect(env.summaryVM.state == .idle)
        #expect(env.chatVM.messages.isEmpty)
        #expect(env.translateVM.translatedText == nil)
    }

    // MARK: - Harness

    /// Yields the cooperative thread until `condition` holds or a bounded
    /// number of turns elapse. Used to await an observable VM state the
    /// handler's spawned `Task` drives — deterministic without a fixed sleep.
    private func pollUntil(_ condition: () -> Bool, maxTurns: Int = 200) async {
        var turns = 0
        while !condition() && turns < maxTurns {
            await Task.yield()
            turns += 1
        }
    }

    struct PanelEnvironment {
        let panel: AIReaderPanel
        let summaryVM: AIAssistantViewModel
        let chatVM: AIChatViewModel
        let translateVM: AITranslationViewModel
    }

    /// Builds an `AIReaderPanel` wired to three independent VMs so each
    /// action path can be observed in isolation. Each VM gets its own
    /// `AIService` backed by the supplied (or a default) provider.
    /// A mid-document locator (charOffset 50 into the ~80-char fullText) so a
    /// `.section` summarize yields non-empty context and actually reaches the
    /// provider. `.bookSoFar` at offset 0 would error on empty context — the
    /// scope-override tests assert `setScope` synchronously instead of awaiting
    /// the provider, so they don't depend on this offset.
    private static func midLocator() -> Locator {
        WI11TestHelpers.makeLocator(format: .txt, charOffset: 50)
    }

    private func makeEnvironment(
        summarizeProvider: (any AIProvider)? = nil,
        chatProvider: (any AIProvider)? = nil,
        translateProvider: (any AIProvider)? = nil
    ) -> PanelEnvironment {
        let locator = Self.midLocator()
        let fingerprint = locator.bookFingerprint

        let summaryVM = AIAssistantViewModel(
            aiService: makeService(provider: summarizeProvider ?? ImmediateSummaryProvider())
        )
        let translateVM = AITranslationViewModel(
            aiService: makeService(provider: translateProvider ?? ImmediateTranslateProvider())
        )
        let chatVM = AIChatViewModel(
            aiService: makeService(provider: chatProvider ?? ImmediateChatProvider()),
            bookFingerprint: fingerprint
        )

        let panel = AIReaderPanel(
            viewModel: summaryVM,
            translationViewModel: translateVM,
            chatViewModel: chatVM,
            locator: locator,
            textContent: "Section text to translate.",
            fullTextContent: "Full book text content for the scoped summary extraction path in tests.",
            chapterBounds: nil,
            format: .txt,
            onDismiss: {},
            theme: .paper,
            initialTab: .summarize
        )
        return PanelEnvironment(
            panel: panel,
            summaryVM: summaryVM,
            chatVM: chatVM,
            translateVM: translateVM
        )
    }

    private func makeService(provider: any AIProvider) -> AIService {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        return AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: provider
        )
    }
}

// MARK: - Local provider stubs (self-contained — shared infra untouched)

/// Completes summarize immediately with a stub response.
private final class ImmediateSummaryProvider: AIProvider, @unchecked Sendable {
    let providerName = "ImmediateSummary"
    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        WI11TestHelpers.makeResponse(content: "Summary.")
    }
    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Completes translate immediately; records send-call count.
private final class ImmediateTranslateProvider: AIProvider, @unchecked Sendable {
    let providerName = "ImmediateTranslate"
    private let counter = CallCounter()
    var sendCallCount: Int { get async { await counter.value } }
    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        await counter.increment()
        return WI11TestHelpers.makeResponse(content: "Translated.", actionType: .translate)
    }
    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Completes chat (stream) immediately with a one-chunk response; records
/// stream-call count.
private final class ImmediateChatProvider: AIProvider, @unchecked Sendable {
    let providerName = "ImmediateChat"
    private let counter = CallCounter()
    var streamCallCount: Int { get async { await counter.value } }
    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        WI11TestHelpers.makeResponse(content: "Reply.")
    }
    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await counter.increment()
                continuation.yield(AIStreamChunk(text: "Reply.", isComplete: true))
                continuation.finish()
            }
        }
    }
}

/// A chat provider whose stream suspends until `release()` — pins the
/// AIChatViewModel in `isLoading` so the isLoading-gate can be observed
/// deterministically (the chat analogue of GatedAIProvider).
private final class GatedChatProvider: AIProvider, @unchecked Sendable {
    let providerName = "GatedChat"
    private let gate = ChatGateState()
    var streamCallCount: Int { get async { await gate.streamCallCount } }
    func awaitEntered() async { await gate.awaitEntered() }
    func release() async { await gate.release() }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        WI11TestHelpers.makeResponse(content: "Reply.")
    }
    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await gate.markEntered()
                await gate.gateOpen()
                continuation.yield(AIStreamChunk(text: "Reply.", isComplete: true))
                continuation.finish()
            }
        }
    }
}

/// Cross-context call counter (provider executor writes, @MainActor test reads).
private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Gate state for `GatedChatProvider` — order-independent release, mirrors
/// the `GateState` actor used by `GatedAIProvider`.
private actor ChatGateState {
    private(set) var streamCallCount = 0
    private var entered = false
    private var released = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func markEntered() {
        streamCallCount += 1
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
    }
    func gateOpen() async {
        if released { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }
    func awaitEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }
    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

#endif
#endif
