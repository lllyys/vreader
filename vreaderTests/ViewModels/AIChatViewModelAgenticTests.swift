// Purpose: Feature #91 WI-8b — pin the AIChatViewModel agentic branch: when the
// live `agenticTools` flag is ON, a non-empty registry is injected, AND the
// resolved provider supports tool-use, the chat routes through AgenticChatDriver
// (single final answer, no streaming) and suppresses citations on a tool reply;
// otherwise it falls back to streaming (flag OFF, no registry, or non-tool
// provider — via the SAME resolved config). Plus the branch cleanup paths.
//
// @coordinates-with: AIChatViewModel.swift, AgenticChatDriver.swift,
//   AIChatAgenticSupport.swift, dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Testing
import Foundation
@testable import vreader

private final class ScriptedToolProvider: AIProvider, @unchecked Sendable {
    let providerName = "Scripted"
    let supports: Bool
    private var turns: [AIToolTurn]
    let throwsOnTool: Bool
    private(set) var streamCalled = false

    init(supports: Bool = true, turns: [AIToolTurn] = [.text("agentic answer")], throwsOnTool: Bool = false) {
        self.supports = supports
        self.turns = turns
        self.throwsOnTool = throwsOnTool
    }
    var supportsToolUse: Bool { supports }
    func sendRequest(_ request: AIRequest) async throws -> AIResponse { throw AIError.invalidResponse }
    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        streamCalled = true
        return AsyncThrowingStream { c in
            c.yield(AIStreamChunk(text: "STREAMED", isComplete: true)); c.finish()
        }
    }
    func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn {
        if throwsOnTool { throw AIError.invalidResponse }
        return turns.isEmpty ? .text("(end)") : turns.removeFirst()
    }
}

private struct NoopTool: AITool {
    var definition: ToolDefinition {
        ToolDefinition(name: "noop", description: "noop", inputSchema: .object([:]))
    }
    func run(_ input: JSONValue) async -> ToolResult {
        ToolResult(toolUseID: "", content: "noop ran", isError: false)
    }
}

@Suite("Feature #91 WI-8b — AIChatViewModel agentic branch")
struct AIChatViewModelAgenticTests {

    @MainActor
    private func makeSUT(
        provider: ScriptedToolProvider, registry: AIToolRegistry?, flagOn: Bool = true
    ) async -> AIChatViewModel {
        let prefs = MockPreferenceStore()
        prefs.set("true", forKey: DefaultProviderProfileMigrator.migrationFlagKey)
        let keychain = KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
        let store = ProviderProfileStore(
            preferences: prefs, migrator: DefaultProviderProfileMigrator(), keychain: keychain)
        let profile = ProviderProfile(
            id: UUID(), name: "T", kind: .openAICompatible,
            baseURL: URL(string: "https://x.example.com/v1")!, model: "m",
            temperature: 0.5, maxTokens: 1000)
        try? keychain.saveAPIKey("sk-test", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        if flagOn { flags.setOverride(true, for: .agenticTools) }
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain, provider: provider, profileStore: store)
        return AIChatViewModel(
            aiService: service, featureFlags: flags, agenticRegistry: registry)
    }

    @Test @MainActor func agenticPath_producesFinalAnswer_withoutStreaming() async {
        let provider = ScriptedToolProvider(turns: [.text("agentic answer")])
        let vm = await makeSUT(provider: provider, registry: AIToolRegistry([NoopTool()]))
        await vm.sendMessage("what is X?")
        #expect(vm.messages.last?.content == "agentic answer")
        #expect(provider.streamCalled == false)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor func flagOff_fallsBackToStreaming() async {
        // Live flag re-check: registry injected but the flag is OFF → streaming.
        let provider = ScriptedToolProvider()
        let vm = await makeSUT(provider: provider, registry: AIToolRegistry([NoopTool()]), flagOn: false)
        await vm.sendMessage("hi")
        #expect(provider.streamCalled == true)
        #expect(vm.messages.last?.content == "STREAMED")
    }

    @Test @MainActor func noRegistry_fallsBackToStreaming() async {
        let provider = ScriptedToolProvider()
        let vm = await makeSUT(provider: provider, registry: nil)
        await vm.sendMessage("hi")
        #expect(provider.streamCalled == true)
        #expect(vm.messages.last?.content == "STREAMED")
    }

    @Test @MainActor func nonToolProvider_fallsBackToStreaming() async {
        let provider = ScriptedToolProvider(supports: false)
        let vm = await makeSUT(provider: provider, registry: AIToolRegistry([NoopTool()]))
        await vm.sendMessage("hi")
        #expect(provider.streamCalled == true)
        #expect(vm.messages.last?.content == "STREAMED")
    }

    @Test @MainActor func toolDrivenReply_suppressesCitations() async {
        let provider = ScriptedToolProvider(turns: [
            .toolUse(blocks: [.toolUse(ToolCall(id: "c", name: "noop", input: .object([:])))]),
            .text("done"),
        ])
        let vm = await makeSUT(provider: provider, registry: AIToolRegistry([NoopTool()]))
        vm.pendingCitations = [ChatCitation(sourceKind: .scope, label: "Chapter 1")]
        await vm.sendMessage("q")
        #expect(vm.messages.last?.content == "done")
        #expect(vm.messages.last?.citations.isEmpty == true)
    }

    @Test @MainActor func agenticThrow_removesPlaceholder_setsError() async {
        let provider = ScriptedToolProvider(throwsOnTool: true)
        let vm = await makeSUT(provider: provider, registry: AIToolRegistry([NoopTool()]))
        await vm.sendMessage("q")
        #expect(vm.errorMessage != nil)
        // The empty assistant placeholder was removed; only the user message remains.
        #expect(vm.messages.last?.role == .user)
        #expect(vm.messages.count == 1)
    }

    @Test @MainActor func agenticEmptyFinalText_removesMessage() async {
        let provider = ScriptedToolProvider(turns: [.text("")])
        let vm = await makeSUT(provider: provider, registry: AIToolRegistry([NoopTool()]))
        await vm.sendMessage("q")
        #expect(vm.errorMessage == nil)
        #expect(vm.messages.last?.role == .user)   // empty agentic answer → message removed
        #expect(vm.messages.count == 1)
    }
}
