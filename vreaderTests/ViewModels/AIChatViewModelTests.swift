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

    // MARK: - Feature #87 WI-1: Chat cancellation primitive

    /// Builds a VM wired to a `GatedChatAIProvider` so a test can stream a
    /// partial reply and pin exactly when the (cancelled) producer would emit
    /// its remaining chunk.
    @MainActor
    private func makeGatedSUT(
        provider: GatedChatAIProvider,
        bookFingerprint: DocumentFingerprint? = nil
    ) -> AIChatViewModel {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: provider
        )
        return AIChatViewModel(
            aiService: service,
            bookFingerprint: bookFingerprint,
            contextWindowSize: 10
        )
    }

    @Test @MainActor func sendMessage_thenCancelStreaming_keepsPartial() async {
        // The view's pattern: fire-and-forget the launcher Task, then cancel.
        let gated = GatedChatAIProvider()
        gated.firstChunk = "partial reply "
        gated.secondChunk = "that should never land"
        let vm = makeGatedSUT(provider: gated)

        let send = Task { @MainActor in await vm.sendMessage("Explain this") }

        // Wait until the first chunk has streamed into the assistant message.
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        #expect(vm.messages.last?.content == "partial reply ")

        vm.cancelStreaming()
        // cancelStreaming clears isLoading optimistically.
        #expect(vm.isLoading == false)

        // Release the now-stale producer; its second chunk must be discarded.
        await gated.releaseGate(callIndex: 0)
        await send.value

        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.content == "partial reply ",
                "the streamed-so-far partial must be kept; the post-cancel chunk dropped")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil, "a user stop is not an error")
    }

    @Test @MainActor func cancelStreaming_beforeFirstChunk_removesEmptyAssistantPlaceholder() async {
        let gated = GatedChatAIProvider()
        gated.withholdFirstChunk = true   // nothing streams until the gate releases
        let vm = makeGatedSUT(provider: gated)

        let send = Task { @MainActor in await vm.sendMessage("Hi") }

        // Wait until the empty assistant placeholder has been appended.
        while vm.messages.count < 2 { await Task.yield() }
        #expect(vm.messages.last?.content.isEmpty == true)

        vm.cancelStreaming()
        await gated.releaseGate(callIndex: 0)   // let the cancelled producer unwind
        await send.value

        // The empty placeholder is removed; the user message remains.
        #expect(vm.messages.count == 1)
        #expect(vm.messages.first?.role == .user)
        #expect(vm.messages.first?.content == "Hi")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor func cancelStreaming_noActiveStream_isNoOp() {
        let (vm, _) = makeSUT()
        // Nothing in flight — must not crash or mutate state.
        vm.cancelStreaming()
        #expect(vm.messages.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor func resendDoesNotClobberLoading() async {
        // op1 in flight; op2 supersedes it. When op1's now-stale task finally
        // unwinds, its teardown must NOT clobber op2's isLoading.
        let gated = GatedChatAIProvider()
        let vm = makeGatedSUT(provider: gated)

        let first = Task { @MainActor in await vm.sendMessage("First") }
        // op1 reached the provider (first chunk streamed into the assistant msg).
        while await gated.streamRequestCallCount < 1 { await Task.yield() }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        #expect(vm.isLoading == true)

        // op2 supersedes op1 (sendMessage cancels the in-flight task first).
        let second = Task { @MainActor in await vm.sendMessage("Second") }
        while await gated.streamRequestCallCount < 2 { await Task.yield() }
        #expect(vm.isLoading == true)

        // Release op1's stale producer (callIndex 0) FIRST; its late teardown
        // must be ignored (opId != opCounter).
        await gated.releaseGate(callIndex: 0)
        await first.value
        #expect(vm.isLoading == true, "the superseded op's teardown must not clear op2's isLoading")

        // Now let op2 finish (callIndex 1).
        await gated.releaseGate(callIndex: 1)
        await second.value
        #expect(vm.isLoading == false)
    }

    @Test @MainActor func clearHistory_midStream_cancelsAndDoesNotCorrupt() async {
        let gated = GatedChatAIProvider()
        let vm = makeGatedSUT(provider: gated)

        let send = Task { @MainActor in await vm.sendMessage("Question") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }

        vm.clearHistory()
        #expect(vm.messages.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)

        // Let the cancelled producer unwind — no crash, history stays empty.
        await gated.releaseGate(callIndex: 0)
        await send.value
        #expect(vm.messages.isEmpty)
        #expect(vm.isLoading == false)
    }

    @Test @MainActor func cancelStreaming_duringWholeBookPreRead_clearsLoadingImmediately_landsNoReply() async {
        // .wholeBook scope awaits `onWholeBookReadRequested` BEFORE the provider
        // request. A Stop during that pre-read must clear isLoading immediately
        // and land NO assistant reply (the post-await guard holds).
        let gated = GatedChatAIProvider()
        let vm = makeGatedSUT(provider: gated)

        // Drive the .wholeBook pre-read branch: scope == .wholeBook + a not-ready
        // retrieval VM + a gated read closure.
        let readGate = ChatStreamGate()
        vm.wholeBookRetrieval = WholeBookRetrievalViewModel()
        vm.onWholeBookReadRequested = { await readGate.waitForRelease() }
        vm.setScope(.wholeBook)

        let send = Task { @MainActor in await vm.sendMessage("Summarize the whole book") }
        // Wait until the send is parked on the pre-read await (isLoading true).
        while vm.isLoading == false { await Task.yield() }

        vm.cancelStreaming()
        #expect(vm.isLoading == false, "Stop during pre-read clears isLoading immediately")

        // Release the pre-read; the cancelled task's post-await guard must prevent
        // any provider call / assistant reply.
        await readGate.release()
        await send.value

        let providerCalls = await gated.streamRequestCallCount
        #expect(providerCalls == 0, "no provider request after a pre-read Stop")
        let assistantReplies = vm.messages.filter { $0.role == .assistant && !$0.content.isEmpty }
        #expect(assistantReplies.isEmpty, "no assistant reply lands after a pre-read Stop")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor func cancelledOpErroring_doesNotSurfaceStaleError() async {
        // Gate-4 High: cooperative cancellation also applies to the ERROR catch
        // arms. A cancelled op whose provider throws a NON-CancellationError (a late
        // network/provider failure) must NOT surface `errorMessage` — "a user stop
        // is not an error". Drive: stream a partial, cancel, then let the gated
        // stream finish-throwing; assert no error surfaces and the partial is kept.
        let gated = GatedChatAIProvider()
        gated.firstChunk = "partial "
        gated.errorAfterGate = AIError.networkError("late provider failure")
        let vm = makeGatedSUT(provider: gated)

        let send = Task { @MainActor in await vm.sendMessage("Hi") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }   // first chunk landed

        vm.cancelStreaming()                    // cancel mid-stream
        await gated.releaseGate(callIndex: 0)   // gate releases → stream finishes THROWING
        await send.value

        #expect(vm.errorMessage == nil,
                "a cancelled op's late provider error must not surface (Gate-4 High)")
        #expect(vm.isLoading == false)
        #expect(vm.messages.last?.content == "partial ", "the partial reply is kept on cancel")
    }

    @Test @MainActor func supersededOpErroring_doesNotSurfaceStaleError() async {
        // Gate-4 r2 Medium: pins the RESEND path through the catch-arm guard — a
        // superseded op whose provider throws must not surface `errorMessage` while
        // a newer op is in flight.
        let gated = GatedChatAIProvider()
        gated.firstChunk = "op1 "
        gated.errorAfterGate = AIError.networkError("op1 late failure")
        let vm = makeGatedSUT(provider: gated)

        let t1 = Task { @MainActor in await vm.sendMessage("first") }
        while await gated.streamRequestCallCount < 1 { await Task.yield() }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }   // op1 streamed

        // op2 supersedes op1 (cancels op1's task + bumps opCounter).
        let t2 = Task { @MainActor in await vm.sendMessage("second") }
        while await gated.streamRequestCallCount < 2 { await Task.yield() }

        // Release op1's now-stale gate → op1's stream finishes-throwing.
        await gated.releaseGate(callIndex: 0)
        await t1.value

        #expect(vm.errorMessage == nil,
                "a superseded op's late provider error must not surface (catch-arm guard)")

        // Clean up op2 (it errors as the current op — fine, the assertion is done).
        await gated.releaseGate(callIndex: 1)
        await t2.value
    }
}

// MARK: - ComposerSendState (feature #87 WI-1)

@Suite("ComposerSendState")
struct ComposerSendStateTests {

    @Test(arguments: [
        // (isLoading, hasInput, isComposerDisabled, expected)
        (true,  true,  false, ComposerSendState.stop),     // loading → stop regardless
        (true,  false, false, ComposerSendState.stop),     // loading wins even w/o input
        (true,  true,  true,  ComposerSendState.stop),     // loading wins even when disabled
        (false, true,  false, ComposerSendState.send),     // has input, not disabled → send
        (false, false, false, ComposerSendState.disabled), // no input → disabled
        (false, true,  true,  ComposerSendState.disabled), // composer disabled → disabled
        (false, false, true,  ComposerSendState.disabled), // no input + disabled → disabled
    ])
    func resolve(_ isLoading: Bool, _ hasInput: Bool, _ isComposerDisabled: Bool,
                 _ expected: ComposerSendState) {
        #expect(ComposerSendState.resolve(
            isLoading: isLoading,
            hasInput: hasInput,
            isComposerDisabled: isComposerDisabled) == expected)
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

// MARK: - GatedChatAIProvider (feature #87 WI-1)

/// A single-shot gate (one continuation) that a test releases to let a parked
/// stream producer proceed. One instance PER `streamRequest` call so two
/// overlapping streams (resend) never share/clobber a continuation. Safe to
/// release before or after the producer parks.
private actor ChatStreamGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released: Bool

    init(preReleased: Bool = false) { released = preReleased }

    func release() {
        if let continuation {
            self.continuation = nil
            continuation.resume()
        } else {
            released = true
        }
    }

    func waitForRelease() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if released {
                released = false
                cont.resume()
            } else {
                continuation = cont
            }
        }
    }
}

/// The actor that owns the per-call gates for `GatedChatAIProvider`, so a test
/// can release each `streamRequest` call's gate independently and in a pinned
/// order (mirrors `WI3TranslationGate`, but gates a STREAM's chunks).
private actor ChatStreamGateRegistry {
    private var gates: [Int: ChatStreamGate] = [:]
    /// Releases that arrived BEFORE their call registered (Gate-4 r2 Medium: a
    /// release of an unregistered index must not be lost, else the producer parks
    /// forever and the test hangs).
    private var pendingReleases: Set<Int> = []
    private(set) var callCount = 0

    /// Registers a new stream call and returns its 0-based index + its gate. If a
    /// release for this index already arrived, the gate is created pre-released.
    func registerCall() -> (index: Int, gate: ChatStreamGate) {
        let index = callCount
        callCount += 1
        let gate = ChatStreamGate(preReleased: pendingReleases.remove(index) != nil)
        gates[index] = gate
        return (index, gate)
    }

    /// Releases the gate for `index`; if the call hasn't registered yet, the
    /// release is buffered and applied at registration (tolerant of order).
    func release(callIndex index: Int) async {
        if let gate = gates[index] {
            await gate.release()
        } else {
            pendingReleases.insert(index)
        }
    }
}

/// A chat provider whose `streamRequest` yields ONE chunk immediately, then
/// suspends on a PER-CALL actor gate until `releaseGate(callIndex:)` is called —
/// so a test can stream a partial reply, cancel mid-stream, and deterministically
/// control when each (possibly cancelled) producer would emit its second chunk.
/// No `Task.sleep`. `releaseNextGate()` is a convenience that releases gates in
/// call order for the single-stream tests.
final class GatedChatAIProvider: AIProvider, @unchecked Sendable {
    let providerName = "GatedChat"

    /// Text of the first (pre-gate) chunk.
    var firstChunk: String = "partial "
    /// Text of the second (post-gate) chunk — only reached if the consumer is
    /// still alive when the gate releases.
    var secondChunk: String = "rest"
    /// When true the first chunk is also withheld until the gate releases, so a
    /// test can cancel BEFORE any chunk lands.
    var withholdFirstChunk: Bool = false
    /// When set, the stream FINISHES THROWING this error after the gate releases
    /// (instead of yielding `secondChunk`) — used to drive the cooperative-cancel
    /// stale-error race (Gate-4 High): a cancelled/superseded op's late provider
    /// error must not surface.
    var errorAfterGate: Error?

    private let registry = ChatStreamGateRegistry()

    /// The number of `streamRequest` calls observed so far.
    var streamRequestCallCount: Int { get async { await registry.callCount } }

    /// Releases the gate for the given call index (0-based).
    func releaseGate(callIndex index: Int) async { await registry.release(callIndex: index) }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        throw AIError.invalidResponse
    }

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        let registry = self.registry
        let first = firstChunk
        let second = secondChunk
        let withholdFirst = withholdFirstChunk
        let errAfter = errorAfterGate
        return AsyncThrowingStream { continuation in
            Task {
                let (_, gate) = await registry.registerCall()
                if withholdFirst {
                    await gate.waitForRelease()
                    if let errAfter { continuation.finish(throwing: errAfter); return }
                    continuation.yield(AIStreamChunk(text: first, isComplete: false))
                } else {
                    continuation.yield(AIStreamChunk(text: first, isComplete: false))
                    await gate.waitForRelease()
                    if let errAfter { continuation.finish(throwing: errAfter); return }
                }
                continuation.yield(AIStreamChunk(text: second, isComplete: true))
                continuation.finish()
            }
        }
    }
}
