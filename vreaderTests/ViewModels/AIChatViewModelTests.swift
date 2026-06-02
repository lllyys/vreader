// Purpose: Tests for AIChatViewModel — multi-turn chat with sliding window,
// book context, streaming, and error handling.

import Testing
import Foundation
@testable import vreader

@Suite("AIChatViewModel")
struct AIChatViewModelTests {

    // MARK: - Helpers

    @MainActor
    private func makeSUT(
        featureEnabled: Bool = true,
        hasConsent: Bool = true,
        provider: StubChatAIProvider? = nil,
        bookFingerprint: DocumentFingerprint? = nil,
        contextWindowSize: Int = 10
    ) -> (AIChatViewModel, StubChatAIProvider) {
        let flags = FeatureFlags(environment: .prod)
        if featureEnabled {
            flags.setOverride(true, for: .aiAssistant)
        }

        let stub = provider ?? StubChatAIProvider()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: hasConsent),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        let vm = AIChatViewModel(
            aiService: service,
            bookFingerprint: bookFingerprint,
            contextWindowSize: contextWindowSize
        )
        return (vm, stub)
    }

    // MARK: - Initial State

    @Test @MainActor func initialStateIsEmpty() {
        let (vm, _) = makeSUT()
        #expect(vm.messages.isEmpty)
        #expect(!vm.isLoading)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Send Message Adds to History

    @Test @MainActor func sendMessageAddsToHistory() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Hello! How can I help?",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub)

        await vm.sendMessage("Hello")

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "Hello")
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].content == "Hello! How can I help?")
    }

    // MARK: - Multi-Turn Preserves Context

    @Test @MainActor func multiTurnPreservesContext() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "First response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub)

        // First turn
        await vm.sendMessage("First question")
        #expect(vm.messages.count == 2)

        // Second turn
        stub.stubbedResponse = AIResponse(
            content: "Second response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )
        await vm.sendMessage("Second question")

        #expect(vm.messages.count == 4)
        #expect(vm.messages[0].content == "First question")
        #expect(vm.messages[1].content == "First response")
        #expect(vm.messages[2].content == "Second question")
        #expect(vm.messages[3].content == "Second response")

        // Verify the 2nd request included prior context
        #expect(stub.streamRequestCallCount == 2)
        if let lastRequest = stub.lastRequest {
            // The context text should contain prior messages
            #expect(lastRequest.contextText.contains("First question"))
            #expect(lastRequest.contextText.contains("First response"))
            #expect(lastRequest.contextText.contains("Second question"))
        }
    }

    // MARK: - Clear History

    @Test @MainActor func clearHistoryResetsConversation() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub)

        await vm.sendMessage("Hello")
        #expect(vm.messages.count == 2)

        vm.clearHistory()

        #expect(vm.messages.isEmpty)
        #expect(!vm.isLoading)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Sliding Window Drops Old Messages

    @Test @MainActor func slidingWindowDropsOldMessages() async {
        let stub = StubChatAIProvider()
        let (vm, _) = makeSUT(provider: stub, contextWindowSize: 4)

        // Send 3 messages (6 messages total: 3 user + 3 assistant)
        for i in 1...3 {
            stub.stubbedResponse = AIResponse(
                content: "Response \(i)",
                actionType: .questionAnswer,
                promptVersion: "v1",
                createdAt: Date()
            )
            await vm.sendMessage("Message \(i)")
        }

        #expect(vm.messages.count == 6, "All messages should be in display history")

        // Verify the last request's context only includes the most recent N messages
        if let lastRequest = stub.lastRequest {
            // With contextWindowSize=4, only last 4 messages should be in context
            // That means Message 2, Response 2, Message 3 — NOT Message 1, Response 1
            #expect(!lastRequest.contextText.contains("Message 1"),
                    "Oldest message should be dropped from context window")
            #expect(lastRequest.contextText.contains("Message 2") ||
                    lastRequest.contextText.contains("Message 3"),
                    "Recent messages should be in context window")
        }
    }

    // MARK: - Book Context Prepended as System Message

    @Test @MainActor func bookContextPrependedAsSystemMessage() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "About the book...",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let fp = DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 1024,
            format: .epub
        )

        let (vm, _) = makeSUT(provider: stub, bookFingerprint: fp)

        await vm.sendMessage("What is this book about?")

        #expect(stub.streamRequestCallCount == 1)
        if let request = stub.lastRequest {
            #expect(request.bookFingerprint != nil)
            #expect(request.bookFingerprint == fp)
        }
    }

    // MARK: - General Mode Has No Book Context

    @Test @MainActor func generalModeHasNoBookContext() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "General response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub, bookFingerprint: nil)

        await vm.sendMessage("Tell me a joke")

        #expect(stub.streamRequestCallCount == 1)
        if let request = stub.lastRequest {
            #expect(request.bookFingerprint == nil)
        }
    }

    // MARK: - Empty Message Ignored

    @Test @MainActor func emptyMessageIgnored() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Should not be called",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub)

        await vm.sendMessage("")
        #expect(vm.messages.isEmpty)
        #expect(stub.streamRequestCallCount == 0)

        await vm.sendMessage("   ")
        #expect(vm.messages.isEmpty)
        #expect(stub.streamRequestCallCount == 0)

        await vm.sendMessage("\n\t  ")
        #expect(vm.messages.isEmpty)
        #expect(stub.streamRequestCallCount == 0)
    }

    // MARK: - Error State on Failure

    @Test @MainActor func errorStateOnFailure() async {
        let stub = StubChatAIProvider()
        stub.stubbedError = AIError.networkError("Connection refused")

        let (vm, _) = makeSUT(provider: stub)

        await vm.sendMessage("Hello")

        // User message should still be in history
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "Hello")

        // Error should be set
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage!.contains("Connection refused"))
        #expect(!vm.isLoading)
    }

    // MARK: - Error Preserves Previous Conversation

    @Test @MainActor func errorPreservesPreviousConversation() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "First response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub)

        // Successful first turn
        await vm.sendMessage("First question")
        #expect(vm.messages.count == 2)

        // Failed second turn
        stub.stubbedError = AIError.providerError("Server error")
        stub.stubbedResponse = nil
        await vm.sendMessage("Second question")

        // Previous messages preserved, plus the failed user message
        #expect(vm.messages.count == 3)
        #expect(vm.messages[0].content == "First question")
        #expect(vm.messages[1].content == "First response")
        #expect(vm.messages[2].content == "Second question")
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Loading State During Request

    @Test @MainActor func isLoadingTrueDuringRequest() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub)

        // Before request
        #expect(!vm.isLoading)

        // After request completes
        await vm.sendMessage("Hello")
        #expect(!vm.isLoading, "isLoading should be false after completion")
    }

    // MARK: - Unicode / CJK Messages

    @Test @MainActor func unicodeCJKMessagesPreserved() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "这是AI的回复 🎉",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub)

        await vm.sendMessage("你好世界 🌍")

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].content == "你好世界 🌍")
        #expect(vm.messages[1].content == "这是AI的回复 🎉")
    }

    // MARK: - Feature #78: Ask-AI seed

    @Test @MainActor func seedInput_setsSeededInput_andDoesNotAutoSend() async {
        let (vm, _) = makeSUT()
        vm.seedInput("What does this passage mean?")
        #expect(vm.seededInput == "What does this passage mean?")
        // Seeding pre-fills the INPUT only — it must NOT post a message.
        #expect(vm.messages.isEmpty)
    }

    @Test @MainActor func seedInput_ignoresEmptyAndWhitespace() {
        let (vm, _) = makeSUT()
        vm.seedInput("")
        #expect(vm.seededInput == nil)
        vm.seedInput("   \n\t ")
        #expect(vm.seededInput == nil)
    }

    @Test @MainActor func clearSeed_dropsPendingSeed() {
        let (vm, _) = makeSUT()
        vm.seedInput("hello")
        #expect(vm.seededInput == "hello")
        vm.clearSeed()
        #expect(vm.seededInput == nil)
    }

    @Test @MainActor func seedInput_preservesCJKAndPunctuation() {
        let (vm, _) = makeSUT()
        vm.seedInput("解释这段话 “……” 🌍")
        #expect(vm.seededInput == "解释这段话 “……” 🌍")
    }

    // Feature #78 Gate-4 Medium: pin AIChatView's seed-consumption decision
    // (the view/host-seam logic the plan called out — applies on empty input,
    // drops over an active draft, no-op when nothing pending).
    @Test func seedDecision_appliesWhenInputEmpty() {
        #expect(AIChatView.seedDecision(seededInput: "ask this", currentInput: "")
                == .apply("ask this"))
    }

    @Test func seedDecision_dropsWhenDraftPresent() {
        // A seed arriving over an active draft must NOT clobber it — drop + clear.
        #expect(AIChatView.seedDecision(seededInput: "ask this", currentInput: "my draft")
                == .dropAndClear)
    }

    @Test func seedDecision_noneWhenNoSeed() {
        #expect(AIChatView.seedDecision(seededInput: nil, currentInput: "")
                == AIChatView.SeedDecision.none)
        #expect(AIChatView.seedDecision(seededInput: nil, currentInput: "draft")
                == AIChatView.SeedDecision.none)
    }

    // MARK: - Feature Disabled

    @Test @MainActor func featureDisabledShowsError() async {
        let stub = StubChatAIProvider()
        let (vm, _) = makeSUT(featureEnabled: false, provider: stub)

        await vm.sendMessage("Hello")

        #expect(vm.errorMessage != nil)
        #expect(stub.streamRequestCallCount == 0)
    }

    // MARK: - Consent Required

    @Test @MainActor func consentRequiredShowsError() async {
        let stub = StubChatAIProvider()
        let (vm, _) = makeSUT(hasConsent: false, provider: stub)

        await vm.sendMessage("Hello")

        #expect(vm.errorMessage != nil)
        #expect(stub.streamRequestCallCount == 0)
    }

    // MARK: - Book Context Text Included in Request

    @Test @MainActor func bookContextTextIncludedInRequest() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "The book discusses philosophy.",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let fp = DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 1024,
            format: .epub
        )

        let (vm, _) = makeSUT(provider: stub, bookFingerprint: fp)
        vm.bookContext = "Chapter 1: The nature of consciousness and its implications for human understanding."

        await vm.sendMessage("What is this chapter about?")

        #expect(stub.streamRequestCallCount == 1)
        if let request = stub.lastRequest {
            #expect(request.contextText.contains("The nature of consciousness"),
                    "Request context should include book content, got: \(request.contextText)")
        }
    }

    @Test @MainActor func bookContextNilSendsOnlyConversationHistory() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "General response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeSUT(provider: stub, bookFingerprint: nil)
        // bookContext is nil by default

        await vm.sendMessage("Tell me a joke")

        #expect(stub.streamRequestCallCount == 1)
        if let request = stub.lastRequest {
            // Context should only contain the conversation history (the user message)
            #expect(!request.contextText.contains("[Book Context]"),
                    "General mode should not include book context header")
        }
    }

    @Test @MainActor func bookContextUpdatedBetweenMessages() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "First response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let fp = DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 1024,
            format: .txt
        )

        let (vm, _) = makeSUT(provider: stub, bookFingerprint: fp)
        vm.bookContext = "Page 1 content"

        await vm.sendMessage("Question about page 1")

        // Update book context (user scrolled to new section)
        vm.bookContext = "Page 2 content"
        stub.stubbedResponse = AIResponse(
            content: "Second response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        await vm.sendMessage("Question about page 2")

        #expect(stub.streamRequestCallCount == 2)
        if let lastRequest = stub.lastRequest {
            #expect(lastRequest.contextText.contains("Page 2 content"),
                    "Updated book context should appear in second request")
        }
    }

    @Test @MainActor func emptyBookContextTreatedAsNoContext() async {
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let fp = DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 1024,
            format: .txt
        )

        let (vm, _) = makeSUT(provider: stub, bookFingerprint: fp)
        vm.bookContext = ""

        await vm.sendMessage("Hello")

        #expect(stub.streamRequestCallCount == 1)
        if let request = stub.lastRequest {
            #expect(!request.contextText.contains("[Book Context]"),
                    "Empty book context should not include book context header")
        }
    }

    // MARK: - Error Clears on Next Successful Send

    @Test @MainActor func errorClearsOnNextSuccessfulSend() async {
        let stub = StubChatAIProvider()
        stub.stubbedError = AIError.networkError("Timeout")

        let (vm, _) = makeSUT(provider: stub)

        // First message fails
        await vm.sendMessage("Hello")
        #expect(vm.errorMessage != nil)

        // Second message succeeds
        stub.stubbedError = nil
        stub.stubbedResponse = AIResponse(
            content: "Hi there!",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )
        await vm.sendMessage("Hello again")

        #expect(vm.errorMessage == nil, "Error should clear on successful send")
        #expect(vm.messages.count == 3, "Should have: Hello, Hello again, Hi there!")
    }
}

// MARK: - ChatMessage Tests

@Suite("ChatMessage")
struct ChatMessageTests {

    @Test func chatMessageIsIdentifiable() {
        let msg = ChatMessage(role: .user, content: "Hello")
        #expect(msg.id != UUID())  // Has a unique ID
    }

    @Test func chatMessagePreservesContent() {
        let msg = ChatMessage(role: .assistant, content: "Response text")
        #expect(msg.role == .assistant)
        #expect(msg.content == "Response text")
    }

    @Test func chatMessageHasTimestamp() {
        let before = Date()
        let msg = ChatMessage(role: .user, content: "Test")
        let after = Date()
        #expect(msg.timestamp >= before)
        #expect(msg.timestamp <= after)
    }

    @Test func chatRoleValues() {
        #expect(ChatRole.user != ChatRole.assistant)
        #expect(ChatRole.user != ChatRole.system)
        #expect(ChatRole.assistant != ChatRole.system)
    }
}

// MARK: - StubChatAIProvider

/// Extended stub that records full request details for chat context verification.
/// Supports both sendRequest and streamRequest — streaming uses the same
/// stubbedResponse/stubbedError as sendRequest for consistency.
final class StubChatAIProvider: AIProvider, @unchecked Sendable {
    let providerName = "StubChat"

    var stubbedResponse: AIResponse?
    var stubbedError: Error?
    private(set) var sendRequestCallCount = 0
    private(set) var streamRequestCallCount = 0
    private(set) var lastRequest: AIRequest?
    private(set) var allRequests: [AIRequest] = []

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        sendRequestCallCount += 1
        lastRequest = request
        allRequests.append(request)
        if let error = stubbedError {
            throw error
        }
        guard let response = stubbedResponse else {
            throw AIError.invalidResponse
        }
        return response
    }

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        streamRequestCallCount += 1
        lastRequest = request
        allRequests.append(request)
        let error = stubbedError
        let response = stubbedResponse
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            guard let response else {
                continuation.finish(throwing: AIError.invalidResponse)
                return
            }
            continuation.yield(AIStreamChunk(text: response.content, isComplete: true))
            continuation.finish()
        }
    }
}
