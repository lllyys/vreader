// Purpose: Feature #88 WI-4 — pin `AIChatViewModel.activeSessionTitle`, the
// display title the Chat-tab session bar renders. Covers: empty thread →
// default title, derived-from-first-user-message (incl. CJK), and the
// post-`switchToSession` derived title. Reuses the shared MockChatSessionStore
// helper (AIChatViewModelSessionsTestHelpers.swift).
//
// SwiftUI button-tap tests are out of scope (rule 10 — test the VM resolver,
// not pixels).
//
// @coordinates-with: AIChatViewModel.swift, AIChatViewModel+Sessions.swift,
//   ChatSessionPersisting.swift,
//   dev-docs/designs/vreader-fidelity-v1/project/session-switcher-artboards.jsx

import Testing
import Foundation
@testable import vreader

@Suite("AIChatViewModelTitle")
struct AIChatViewModelTitleTests {

    // MARK: - SUT helpers

    private static let bookKey =
        "epub:aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233:1024"

    @MainActor
    private func makeFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 1024,
            format: .epub
        )
    }

    @MainActor
    private func makeSUT(store: MockChatSessionStore?) -> AIChatViewModel {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let stub = StubChatAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "AI reply", actionType: .questionAnswer,
            promptVersion: "v1", createdAt: Date())
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )
        return AIChatViewModel(
            aiService: service,
            bookFingerprint: makeFingerprint(),
            contextWindowSize: 10,
            chatSessionStore: store
        )
    }

    // MARK: - empty thread → default title

    @Test @MainActor func activeSessionTitle_emptyThread_isDefault() {
        let vm = makeSUT(store: MockChatSessionStore())
        #expect(vm.messages.isEmpty)
        #expect(vm.activeSessionTitle == AIChatViewModel.defaultSessionTitle)
        #expect(vm.activeSessionTitle == "New conversation")
    }

    // MARK: - derived from first user message

    @Test @MainActor func activeSessionTitle_derivesFromFirstUserMessage() {
        let vm = makeSUT(store: MockChatSessionStore())
        vm.messages = [
            ChatMessage(role: .user, content: "What is this book about?"),
            ChatMessage(role: .assistant, content: "It's about a lot of things."),
        ]
        #expect(vm.activeSessionTitle == "What is this book about?")
    }

    // MARK: - CJK first user message preserved

    @Test @MainActor func activeSessionTitle_preservesCJKFirstUserMessage() {
        let vm = makeSUT(store: MockChatSessionStore())
        vm.messages = [
            ChatMessage(role: .user, content: "这本书讲什么？"),
            ChatMessage(role: .assistant, content: "这本书讲述了……"),
        ]
        #expect(vm.activeSessionTitle == "这本书讲什么？")
    }

    // MARK: - whitespace-only first user → falls back to default

    @Test @MainActor func activeSessionTitle_whitespaceOnlyFirstUser_isDefault() {
        let vm = makeSUT(store: MockChatSessionStore())
        vm.messages = [
            ChatMessage(role: .user, content: "   \n  "),
        ]
        #expect(vm.activeSessionTitle == AIChatViewModel.defaultSessionTitle)
    }

    // MARK: - after switchToSession → that session's STORED title (not the derived one)

    @Test @MainActor func activeSessionTitle_afterSwitch_showsStoredTitle() async {
        let store = MockChatSessionStore()
        // A session whose STORED title differs from its first-message-derived title
        // (e.g. a renamed thread). The bar must show the stored title, not the prompt.
        let seededId = store.seed(
            key: Self.bookKey, title: "Stored heading",
            messages: [
                ChatMessage(role: .user, content: "Who is Mr. Darcy?"),
                ChatMessage(role: .assistant, content: "Fitzwilliam Darcy is…"),
            ],
            updatedAt: Date(timeIntervalSince1970: 50))
        let vm = makeSUT(store: store)

        await vm.switchToSession(seededId)

        #expect(vm.activeSessionId == seededId)
        #expect(vm.activeSessionTitle == "Stored heading",
                "the bar shows the STORED session title, not the first-message-derived one")
    }

    // MARK: - after loadSessions → the loaded session's STORED title

    @Test @MainActor func activeSessionTitle_afterLoad_showsStoredTitle() async {
        let store = MockChatSessionStore()
        _ = store.seed(
            key: Self.bookKey, title: "Renamed Topic",
            messages: [ChatMessage(role: .user, content: "what is the entail")],
            updatedAt: Date(timeIntervalSince1970: 60))
        let vm = makeSUT(store: store)

        await vm.loadSessions()

        #expect(vm.activeSessionTitle == "Renamed Topic",
                "a loaded session shows its stored title, not the derived one")
    }

    // MARK: - after newConversation → resets to the default title

    @Test @MainActor func activeSessionTitle_afterNewConversation_isDefault() async {
        let store = MockChatSessionStore()
        let seededId = store.seed(
            key: Self.bookKey, title: "Stored heading",
            messages: [ChatMessage(role: .user, content: "Who is Mr. Darcy?")],
            updatedAt: Date(timeIntervalSince1970: 50))
        let vm = makeSUT(store: store)
        await vm.switchToSession(seededId)
        #expect(vm.activeSessionTitle == "Stored heading")

        await vm.newConversation()

        #expect(vm.activeSessionTitle == AIChatViewModel.defaultSessionTitle,
                "starting a new conversation clears the stored title back to the default")
    }

    // MARK: - assistant-first thread (no user message) → default title

    @Test @MainActor func activeSessionTitle_assistantFirstThread_isDefault() {
        // A thread with no user message can't derive a title — fall back to the
        // default. (In practice the user always sends first, so this is a guard.)
        let vm = makeSUT(store: MockChatSessionStore())
        vm.messages = [ChatMessage(role: .assistant, content: "Hello, ask me anything.")]
        #expect(vm.activeSessionTitle == AIChatViewModel.defaultSessionTitle)
    }

    // MARK: - stored title survives a later settled turn (no derived-title overwrite)

    @Test @MainActor func storedTitle_survivesLaterSettledTurn() async {
        let store = MockChatSessionStore()
        // A renamed session: stored title "Renamed Topic" ≠ its derived title.
        let id = store.seed(
            key: Self.bookKey, title: "Renamed Topic",
            messages: [
                ChatMessage(role: .user, content: "what is the entail"),
                ChatMessage(role: .assistant, content: "An entail restricts inheritance…"),
            ],
            updatedAt: Date(timeIntervalSince1970: 60))
        let vm = makeSUT(store: store)
        await vm.loadSessions()
        #expect(vm.activeSessionTitle == "Renamed Topic")

        // Send another turn — the settled-turn save must PRESERVE the stored title,
        // not rewrite the persisted title back to the first user message.
        await vm.sendMessage("and who inherits Longbourn")

        #expect(store.lastSavedTitle(for: id) == "Renamed Topic",
                "a later settled turn preserves the stored/renamed title")
        #expect(vm.activeSessionTitle == "Renamed Topic")
    }

    // MARK: - stored title survives the transition seal (new / switch away)

    @Test @MainActor func storedTitle_survivesNewConversationSeal() async {
        let store = MockChatSessionStore()
        let id = store.seed(
            key: Self.bookKey, title: "Renamed Topic",
            messages: [
                ChatMessage(role: .user, content: "what is the entail"),
                ChatMessage(role: .assistant, content: "An entail restricts inheritance…"),
            ],
            updatedAt: Date(timeIntervalSince1970: 60))
        let vm = makeSUT(store: store)
        await vm.loadSessions()

        // Leaving the session (new conversation) seals it — the seal must NOT revert
        // the persisted title to the derived one.
        await vm.newConversation()

        #expect(store.lastSavedTitle(for: id) == "Renamed Topic",
                "the transition seal preserves the stored/renamed title")
    }
}
