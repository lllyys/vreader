// Purpose: Feature #88 WI-5 — pin the Conversations-sheet VM surface:
// `loadSessionSummaries()` (the sheet's list source) and `renameSession(id:to:)`
// (rename ANY session, not just the active one). Also pins the M1 follow-up that
// `renameActiveSession(_:)` now updates `storedActiveTitle` so the bar repaints.
// Reuses the shared MockChatSessionStore helper
// (AIChatViewModelSessionsTestHelpers.swift).
//
// SwiftUI button-tap tests are out of scope (rule 10 — test the VM surface, not
// pixels).
//
// @coordinates-with: AIChatViewModel.swift, AIChatViewModel+Sessions.swift,
//   AIChatViewModel+SessionTransitions.swift, ChatSessionPersisting.swift,
//   ConversationsSheet.swift,
//   dev-docs/designs/vreader-fidelity-v1/project/session-switcher-artboards.jsx

import Testing
import Foundation
@testable import vreader

@Suite("AIChatViewModelSummaries")
struct AIChatViewModelSummariesTests {

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
    private func makeSUT(store: MockChatSessionStore?, bookChat: Bool = true) -> AIChatViewModel {
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
            bookFingerprint: bookChat ? makeFingerprint() : nil,
            contextWindowSize: 10,
            chatSessionStore: store
        )
    }

    // MARK: - loadSessionSummaries returns seeded summaries (most-recent first)

    @Test @MainActor func loadSessionSummaries_returnsSeeded_mostRecentFirst() async {
        let store = MockChatSessionStore()
        _ = store.seed(key: Self.bookKey, title: "Older",
            messages: [ChatMessage(role: .user, content: "old q")],
            updatedAt: Date(timeIntervalSince1970: 100))
        let newer = store.seed(key: Self.bookKey, title: "Newer",
            messages: [ChatMessage(role: .user, content: "new q"),
                       ChatMessage(role: .assistant, content: "new a")],
            updatedAt: Date(timeIntervalSince1970: 200))
        let vm = makeSUT(store: store)

        let summaries = await vm.loadSessionSummaries()

        #expect(summaries.count == 2)
        #expect(summaries.first?.id == newer, "sorted most-recent first")
        #expect(summaries.first?.title == "Newer")
        #expect(summaries.first?.messageCount == 2)
        #expect(summaries.last?.title == "Older")
    }

    // MARK: - loadSessionSummaries — empty for nil store / nil fingerprint

    @Test @MainActor func loadSessionSummaries_nilStore_isEmpty() async {
        let vm = makeSUT(store: nil)
        let summaries = await vm.loadSessionSummaries()
        #expect(summaries.isEmpty)
    }

    @Test @MainActor func loadSessionSummaries_generalChat_nilFingerprint_isEmpty() async {
        let store = MockChatSessionStore()
        _ = store.seed(key: Self.bookKey, title: "x",
            messages: [ChatMessage(role: .user, content: "q")], updatedAt: Date())
        let vm = makeSUT(store: store, bookChat: false)

        let summaries = await vm.loadSessionSummaries()

        #expect(summaries.isEmpty, "general chat (nil fingerprint) has no per-book sessions")
        #expect(store.fetchSummariesCallCount == 0)
    }

    @Test @MainActor func loadSessionSummaries_noSessions_isEmpty() async {
        let store = MockChatSessionStore()
        let vm = makeSUT(store: store)
        let summaries = await vm.loadSessionSummaries()
        #expect(summaries.isEmpty)
    }

    // MARK: - renameSession(activeId,…) renames the store AND repaints the bar

    @Test @MainActor func renameSession_activeSession_renamesStoreAndUpdatesTitle() async {
        let store = MockChatSessionStore()
        let vm = makeSUT(store: store)
        await vm.loadSessions()
        await vm.sendMessage("hi there")
        let activeId = vm.activeSessionId!

        await vm.renameSession(id: activeId, to: "Renamed active")

        #expect(store.lastRenamedTitle(for: activeId) == "Renamed active")
        #expect(vm.activeSessionTitle == "Renamed active", "the bar repaints to the new title")
        #expect(vm.storedActiveTitle == "Renamed active")
    }

    // MARK: - renameSession(non-active,…) renames the store, leaves the bar title

    @Test @MainActor func renameSession_nonActiveSession_doesNotChangeActiveTitle() async {
        let store = MockChatSessionStore()
        let other = store.seed(key: Self.bookKey, title: "Other thread",
            messages: [ChatMessage(role: .user, content: "other q")],
            updatedAt: Date(timeIntervalSince1970: 10))
        let vm = makeSUT(store: store)
        await vm.loadSessions()          // loads "Other thread" as the active session
        // Move onto a distinct active session so `other` is non-active.
        await vm.newConversation()
        await vm.sendMessage("active thread")
        let activeId = vm.activeSessionId!
        let activeTitleBefore = vm.activeSessionTitle
        #expect(other != activeId)

        await vm.renameSession(id: other, to: "Renamed other")

        #expect(store.lastRenamedTitle(for: other) == "Renamed other", "the non-active session is renamed in the store")
        #expect(vm.activeSessionId == activeId, "the active session is unchanged")
        #expect(vm.activeSessionTitle == activeTitleBefore,
                "renaming a NON-active session does not touch the bar title")
    }

    // MARK: - renameSession with whitespace-only title → no-op

    @Test @MainActor func renameSession_whitespaceOnlyTitle_isNoOp() async {
        let store = MockChatSessionStore()
        let vm = makeSUT(store: store)
        await vm.loadSessions()
        await vm.sendMessage("hello")
        let id = vm.activeSessionId!
        let titleBefore = vm.activeSessionTitle

        await vm.renameSession(id: id, to: "   \n  ")

        #expect(store.lastRenamedTitle(for: id) == nil, "a whitespace-only title is a no-op (never reaches the store)")
        #expect(vm.activeSessionTitle == titleBefore)
    }

    // MARK: - renameActiveSession updates the bar title (M1 follow-up)

    @Test @MainActor func renameActiveSession_updatesActiveTitle() async {
        let store = MockChatSessionStore()
        let vm = makeSUT(store: store)
        await vm.loadSessions()
        await vm.sendMessage("first question")
        let id = vm.activeSessionId!

        await vm.renameActiveSession("Z renamed")

        #expect(store.lastRenamedTitle(for: id) == "Z renamed")
        #expect(vm.activeSessionTitle == "Z renamed", "renameActiveSession repaints the bar (M1 follow-up)")
        #expect(vm.storedActiveTitle == "Z renamed")
    }
}
