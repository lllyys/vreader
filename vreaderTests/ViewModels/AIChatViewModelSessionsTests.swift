// Purpose: Feature #88 WI-3 — pin AIChatViewModel session lifecycle + streaming
// handoff. Covers: load most-recent-non-empty / no-persist-empty-on-open /
// lazy-create-on-first-turn / save-on-settled-turn / newConversation
// seals+resets / switch replaces messages / delete-active falls back /
// title-from-first-user-message, PLUS the three async-race guards (cold-open,
// transition token, streaming handoff) hardened by the Gate-2 audit.
//
// @coordinates-with: AIChatViewModel.swift, AIChatViewModel+Sessions.swift,
//   AIChatViewModel+Streaming.swift, ChatSessionPersisting.swift,
//   dev-docs/plans/20260605-feature-88-conversation-sessions.md (WI-3)

import Testing
import Foundation
@testable import vreader

@Suite("AIChatViewModelSessions")
struct AIChatViewModelSessionsTests {

    // MARK: - SUT helpers

    private static let bookKey = "epub:aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233:1024"

    @MainActor
    private func makeFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 1024,
            format: .epub
        )
    }

    @MainActor
    private func makeSUT(
        store: MockChatSessionStore?,
        provider: AIProvider? = nil,
        bookChat: Bool = true
    ) -> (AIChatViewModel, MockChatSessionStore?) {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let stub = provider ?? {
            let s = StubChatAIProvider()
            s.stubbedResponse = AIResponse(
                content: "AI reply", actionType: .questionAnswer,
                promptVersion: "v1", createdAt: Date())
            return s
        }()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )
        let vm = AIChatViewModel(
            aiService: service,
            bookFingerprint: bookChat ? makeFingerprint() : nil,
            contextWindowSize: 10,
            chatSessionStore: store
        )
        return (vm, store)
    }

    // MARK: - loadSessions — load most-recent NON-EMPTY

    @Test @MainActor func loadSessions_loadsMostRecentNonEmpty() async {
        let store = MockChatSessionStore()
        let older = store.seed(key: Self.bookKey, title: "Older",
            messages: [ChatMessage(role: .user, content: "old q")], updatedAt: Date(timeIntervalSince1970: 100))
        let newer = store.seed(key: Self.bookKey, title: "Newer",
            messages: [ChatMessage(role: .user, content: "new q"),
                       ChatMessage(role: .assistant, content: "new a")],
            updatedAt: Date(timeIntervalSince1970: 200))
        _ = older
        let (vm, _) = makeSUT(store: store)

        await vm.loadSessions()

        #expect(vm.activeSessionId == newer)
        #expect(vm.messages.count == 2)
        #expect(vm.messages.first?.content == "new q")
    }

    @Test @MainActor func loadSessions_skipsEmptySessions_loadsFirstNonEmpty() async {
        let store = MockChatSessionStore()
        // The most-recent has 0 messages (a stale empty row); the load must skip it
        // and pick the most-recent NON-EMPTY one.
        _ = store.seed(key: Self.bookKey, title: "Empty", messages: [],
                       updatedAt: Date(timeIntervalSince1970: 300))
        let withContent = store.seed(key: Self.bookKey, title: "Has content",
            messages: [ChatMessage(role: .user, content: "hi")],
            updatedAt: Date(timeIntervalSince1970: 200))
        let (vm, _) = makeSUT(store: store)

        await vm.loadSessions()

        #expect(vm.activeSessionId == withContent)
        #expect(vm.messages.count == 1)
    }

    // MARK: - No persist empty on open

    @Test @MainActor func loadSessions_noSessions_leavesEmptyState_noPersist() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)

        await vm.loadSessions()

        #expect(vm.activeSessionId == nil)
        #expect(vm.messages.isEmpty)
        #expect(store.createCallCount == 0, "no empty session is persisted on open")
    }

    @Test @MainActor func loadSessions_nilStore_isNoOp() async {
        let (vm, _) = makeSUT(store: nil)
        await vm.loadSessions()
        #expect(vm.activeSessionId == nil)
        #expect(vm.messages.isEmpty)
    }

    @Test @MainActor func loadSessions_generalChat_nilFingerprint_isNoOp() async {
        let store = MockChatSessionStore()
        _ = store.seed(key: Self.bookKey, title: "x",
            messages: [ChatMessage(role: .user, content: "q")], updatedAt: Date())
        let (vm, _) = makeSUT(store: store, bookChat: false)

        await vm.loadSessions()

        #expect(vm.activeSessionId == nil)
        #expect(vm.messages.isEmpty)
        #expect(store.fetchSummariesCallCount == 0)
    }

    @Test @MainActor func loadSessions_idempotent_secondCallNoOps() async {
        let store = MockChatSessionStore()
        _ = store.seed(key: Self.bookKey, title: "x",
            messages: [ChatMessage(role: .user, content: "q")], updatedAt: Date())
        let (vm, _) = makeSUT(store: store)

        await vm.loadSessions()
        let firstFetchCount = store.fetchSummariesCallCount
        await vm.loadSessions()

        #expect(store.fetchSummariesCallCount == firstFetchCount, "second load is a no-op once loaded for the key")
    }

    @Test @MainActor func loadSessions_nonClobbering_skipsWhenMessagesPresent() async {
        let store = MockChatSessionStore()
        let seeded = store.seed(key: Self.bookKey, title: "x",
            messages: [ChatMessage(role: .user, content: "q")], updatedAt: Date())
        _ = seeded
        let (vm, _) = makeSUT(store: store)
        // Local state already has content (e.g. a fresh thread) → load must not run.
        vm.messages = [ChatMessage(role: .user, content: "fresh local")]

        await vm.loadSessions()

        #expect(vm.messages.count == 1)
        #expect(vm.messages.first?.content == "fresh local")
        #expect(store.fetchSummariesCallCount == 0)
    }

    // MARK: - Lazy create on first turn + save on settled turn

    @Test @MainActor func firstTurn_lazyCreatesSession_persistsOnSettled() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()      // empty book → no active session

        await vm.sendMessage("What is this book about?")

        #expect(vm.activeSessionId != nil, "the first real turn lazily creates a session")
        #expect(store.createCallCount == 1)
        // The created/updated session holds the user + assistant turn.
        let saved = store.lastSavedMessages(for: vm.activeSessionId!)
        #expect(saved?.count == 2)
        #expect(saved?.first?.content == "What is this book about?")
    }

    @Test @MainActor func settledTurn_savesDebounced_notPerChunk() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()

        await vm.sendMessage("hello")
        // One persisted write for the settled turn (create), not per streamed chunk.
        #expect(store.createCallCount + store.updateCallCount == 1)
    }

    @Test @MainActor func secondTurn_updatesExistingSession() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()

        await vm.sendMessage("first")
        let id = vm.activeSessionId
        await vm.sendMessage("second")

        #expect(vm.activeSessionId == id, "same session across turns")
        #expect(store.createCallCount == 1)
        #expect(store.updateCallCount >= 1)
        #expect(store.lastSavedMessages(for: id!)?.count == 4)
    }

    // MARK: - Title from first user message

    @Test @MainActor func title_derivedFromFirstUserMessage() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()

        await vm.sendMessage("Explain the theme of loneliness")

        let title = store.lastSavedTitle(for: vm.activeSessionId!)
        #expect(title == "Explain the theme of loneliness")
    }

    @Test @MainActor func title_cjkFirstMessage_preserved() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()

        await vm.sendMessage("解释这本书的主题")

        #expect(store.lastSavedTitle(for: vm.activeSessionId!) == "解释这本书的主题")
    }

    // MARK: - newConversation seals + resets

    @Test @MainActor func newConversation_sealsCurrent_resetsToEmpty() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()
        await vm.sendMessage("first thread")
        let firstId = vm.activeSessionId

        await vm.newConversation()

        #expect(vm.activeSessionId == nil, "reset to the empty state")
        #expect(vm.messages.isEmpty)
        // The sealed session still exists in the store with its content.
        #expect(store.lastSavedMessages(for: firstId!)?.isEmpty == false)
        // No empty session is created for the new (not-yet-used) thread.
        #expect(store.createCallCount == 1)
    }

    @Test @MainActor func newConversation_thenSend_createsSecondSession() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()
        await vm.sendMessage("thread A")
        let a = vm.activeSessionId
        await vm.newConversation()
        await vm.sendMessage("thread B")
        let b = vm.activeSessionId

        #expect(a != b)
        #expect(store.createCallCount == 2)
    }

    // MARK: - switch replaces messages

    @Test @MainActor func switchToSession_replacesMessages_savesCurrent() async {
        let store = MockChatSessionStore()
        let target = store.seed(key: Self.bookKey, title: "Target",
            messages: [ChatMessage(role: .user, content: "target q"),
                       ChatMessage(role: .assistant, content: "target a")],
            updatedAt: Date(timeIntervalSince1970: 50))
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()           // loads "Target" (only non-empty)
        // Move off Target onto a fresh thread with content.
        await vm.newConversation()
        await vm.sendMessage("current thread")
        let current = vm.activeSessionId

        await vm.switchToSession(target)

        #expect(vm.activeSessionId == target)
        #expect(vm.messages.count == 2)
        #expect(vm.messages.first?.content == "target q")
        // The previously-active thread was saved before switching away.
        #expect(store.lastSavedMessages(for: current!)?.isEmpty == false)
    }

    // MARK: - delete active falls back

    @Test @MainActor func deleteActiveSession_fallsBackToMostRecentRemaining() async {
        let store = MockChatSessionStore()
        let other = store.seed(key: Self.bookKey, title: "Other",
            messages: [ChatMessage(role: .user, content: "other")],
            updatedAt: Date(timeIntervalSince1970: 10))
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()
        await vm.newConversation()
        await vm.sendMessage("to be deleted")
        let active = vm.activeSessionId!

        await vm.deleteSession(active)

        #expect(store.deletedIds.contains(active))
        #expect(vm.activeSessionId == other, "falls back to the most-recent remaining")
        #expect(vm.messages.first?.content == "other")
    }

    @Test @MainActor func deleteActiveSession_noneRemaining_resetsToEmpty() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()
        await vm.sendMessage("only thread")
        let active = vm.activeSessionId!

        await vm.deleteSession(active)

        #expect(vm.activeSessionId == nil)
        #expect(vm.messages.isEmpty)
    }

    // MARK: - rename active

    @Test @MainActor func renameActiveSession_renamesInStore() async {
        let store = MockChatSessionStore()
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()
        await vm.sendMessage("hi")
        let id = vm.activeSessionId!

        await vm.renameActiveSession("My renamed thread")

        #expect(store.lastRenamedTitle(for: id) == "My renamed thread")
    }

    // MARK: - RACE: switch mid-send cancels stream + reply does NOT land in new session

    @Test @MainActor func switchMidSend_cancelsStream_replyDoesNotLandInNewSession() async {
        let store = MockChatSessionStore()
        let target = store.seed(key: Self.bookKey, title: "Target",
            messages: [ChatMessage(role: .user, content: "target only")],
            updatedAt: Date(timeIntervalSince1970: 5))
        let gated = SessionGatedProvider()
        gated.firstChunk = "leaking "
        gated.secondChunk = "into wrong session"
        let (vm, _) = makeSUT(store: store, provider: gated)
        await vm.loadSessions()
        // Start a fresh thread and send (parks mid-stream after the first chunk).
        await vm.newConversation()
        let send = Task { @MainActor in await vm.sendMessage("question on thread A") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }

        // Switch to Target while the stream is parked. This must cancel the stream.
        await vm.switchToSession(target)
        #expect(vm.activeSessionId == target)
        #expect(vm.messages.count == 1)
        #expect(vm.messages.first?.content == "target only")

        // Release the now-stale producer; its second chunk must NOT land in Target.
        await gated.releaseGate(callIndex: 0)
        await send.value

        #expect(vm.activeSessionId == target)
        #expect(vm.messages.count == 1, "the cancelled reply does not append to the switched-to session")
        #expect(vm.messages.first?.content == "target only")
        // Target's stored messages were not mutated by the stale reply.
        let targetStored = store.lastSavedMessages(for: target) ?? store.seededMessages(for: target)
        #expect(targetStored?.count == 1)
    }

    // MARK: - RACE: rapid B→C switch — the older B load is abandoned (transition token)

    @Test @MainActor func rapidSwitch_BthenC_olderLoadAbandoned() async {
        let store = MockChatSessionStore()
        let b = store.seed(key: Self.bookKey, title: "B",
            messages: [ChatMessage(role: .user, content: "B content")],
            updatedAt: Date(timeIntervalSince1970: 20))
        let c = store.seed(key: Self.bookKey, title: "C",
            messages: [ChatMessage(role: .user, content: "C content")],
            updatedAt: Date(timeIntervalSince1970: 30))
        // Gate B's fetch so we can fire the C switch before B resolves.
        await store.gateFetch(for: b)
        let (vm, _) = makeSUT(store: store)

        let switchB = Task { @MainActor in await vm.switchToSession(b) }
        // Wait until B's fetch is parked (inside the serialized lane).
        while await store.parkedFetchCount < 1 { await Task.yield() }

        // Fire C while B is parked. C's synchronous pre-lane bumps the transition
        // token (superseding B); C's body queues behind B in the lane. Don't await
        // it here — that would deadlock behind B's parked fetch. Release B, then drain
        // both: B's body resumes, fails its token/id re-check, and is abandoned; C wins.
        let switchC = Task { @MainActor in await vm.switchToSession(c) }
        await store.releaseFetch(for: b)
        _ = await switchB.value
        _ = await switchC.value

        #expect(vm.activeSessionId == c, "the newer C switch wins (serialized; C drains last)")
        #expect(vm.messages.first?.content == "C content")
    }

    // MARK: - RACE: cold open — send before loadSessions resolves → sent turn wins

    @Test @MainActor func coldOpen_sendBeforeLoadResolves_sentTurnWins_loadAbandoned() async {
        let store = MockChatSessionStore()
        let prior = store.seed(key: Self.bookKey, title: "Prior",
            messages: [ChatMessage(role: .user, content: "prior q"),
                       ChatMessage(role: .assistant, content: "prior a")],
            updatedAt: Date(timeIntervalSince1970: 40))
        _ = prior
        // Gate the summaries fetch so loadSessions parks before applying.
        await store.gateSummariesFetch()
        let (vm, _) = makeSUT(store: store)

        let load = Task { @MainActor in await vm.loadSessions() }
        while await store.parkedSummariesCount < 1 { await Task.yield() }

        // The user sends a first message BEFORE the load resolves. Fire it without
        // awaiting (its settled-turn save queues behind the parked load in the lane;
        // awaiting here would deadlock). The user message is appended synchronously
        // and `noteFirstTurnStartedIfNeeded` bumps the token — both abandon the load.
        let send = Task { @MainActor in await vm.sendMessage("brand new question") }
        while !vm.messages.contains(where: { $0.content == "brand new question" }) { await Task.yield() }

        // Release the parked load; it must ABANDON (messages non-empty + token bumped).
        await store.releaseSummariesFetch()
        _ = await send.value
        _ = await load.value

        #expect(vm.activeSessionId != prior, "the sent turn wins; the load is abandoned")
        #expect(vm.activeSessionId != nil, "the first turn lazily created its own session")
        #expect(vm.messages.contains { $0.content == "brand new question" })
        #expect(!vm.messages.contains { $0.content == "prior q" })
    }

    // MARK: - RACE (Gate-4 WI-3 High): transition seals the SETTLED snapshot, not the abandoned in-flight turn

    @Test @MainActor func transitionMidSend_sealsSettledSnapshot_noPartialPersisted() async {
        let store = MockChatSessionStore()
        let gated = SessionGatedProvider()
        gated.firstChunk = "answer 1"
        let (vm, _) = makeSUT(store: store, provider: gated)
        await vm.loadSessions()

        // Turn 1: send + let it settle (lazily creates the session).
        let t1 = Task { @MainActor in await vm.sendMessage("first question") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        await gated.releaseGate(callIndex: 0)
        await t1.value
        let sourceId = try! #require(vm.activeSessionId)
        #expect(store.lastSavedMessages(for: sourceId)?.count == 2)   // user1 + assistant1 settled

        // Turn 2: send, parks mid-stream (the assistant placeholder gets a partial chunk).
        gated.firstChunk = "partial 2"
        let t2 = Task { @MainActor in await vm.sendMessage("second question") }
        while vm.messages.count < 4 { await Task.yield() }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }

        // Transition while turn 2 is in flight — must persist ONLY the settled snapshot.
        await vm.newConversation()

        let stored = store.lastSavedMessages(for: sourceId)
        #expect(stored?.count == 2,
                "the abandoned in-flight turn is NOT persisted into the source session (settled snapshot only)")
        #expect(stored?.first?.content == "first question")
        #expect(stored?.contains { $0.content == "second question" } == false)

        await gated.releaseGate(callIndex: 1)   // cleanup
        await t2.value
    }

    @Test @MainActor func transitionDuringFirstTurnCreate_doesNotLeaveOrphanSession() async {
        let store = MockChatSessionStore()
        let gated = SessionGatedProvider()
        gated.firstChunk = "answer"
        let (vm, _) = makeSUT(store: store, provider: gated)
        await vm.loadSessions()

        // First turn: complete the stream so saveSettledTurn reaches createChatSession,
        // which we park so a transition can race the create.
        await store.gateCreate()
        let t1 = Task { @MainActor in await vm.sendMessage("first") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        await gated.releaseGate(callIndex: 0)                 // stream completes → create parks
        while await store.parkedCreateCount < 1 { await Task.yield() }

        // Transition while the first-turn create is parked. newConversation's
        // SYNCHRONOUS pre-lane bumps the token immediately (superseding the turn);
        // its body queues behind the parked create in the lane. Fire without awaiting
        // (awaiting would deadlock behind the parked create), let the sync bump run,
        // then release the create so saveSettledTurn resumes, sees the bumped token,
        // and rolls back the orphan.
        let newConv = Task { @MainActor in await vm.newConversation() }
        for _ in 0..<5 { await Task.yield() }                 // let the synchronous token bump run
        await store.releaseCreate()                           // the parked create returns
        _ = await newConv.value
        _ = await t1.value

        #expect(store.sessionRowCount == 0,
                "the abandoned first-turn create is rolled back — no orphan/duplicate session")
        #expect(vm.activeSessionId == nil)
        #expect(vm.messages.isEmpty)
    }

    @Test @MainActor func orphanCleanupFailure_leavesVMClean_retainsRow() async {
        // Gate-4 WI-3 r2 Medium: if the orphan-cleanup delete FAILS, the failure is
        // logged (not swallowed) and must not crash / corrupt the VM — the VM is in
        // the post-transition empty state; only a harmless abandoned row is retained.
        let store = MockChatSessionStore()
        store.failDelete = true
        let gated = SessionGatedProvider()
        gated.firstChunk = "answer"
        let (vm, _) = makeSUT(store: store, provider: gated)
        await vm.loadSessions()

        await store.gateCreate()
        let t1 = Task { @MainActor in await vm.sendMessage("first") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        await gated.releaseGate(callIndex: 0)
        while await store.parkedCreateCount < 1 { await Task.yield() }

        // Fire the transition without awaiting (its body queues behind the parked
        // create in the lane); let the synchronous token bump run, then release.
        let newConv = Task { @MainActor in await vm.newConversation() }
        for _ in 0..<5 { await Task.yield() }
        await store.releaseCreate()           // create returns; cleanup delete THROWS (logged)
        _ = await newConv.value
        _ = await t1.value

        #expect(store.sessionRowCount == 1, "a failed cleanup leaves the abandoned row (logged, not silently lost)")
        #expect(vm.activeSessionId == nil, "the VM is still in the clean post-transition empty state")
        #expect(vm.messages.isEmpty)
    }

    @Test @MainActor func transitionDuringExistingSessionUpdate_sealsFreshSnapshot_noStaleOverwrite() async {
        // Gate-4 WI-3 r4 High: a transition racing an existing-session settled-turn
        // UPDATE must seal the FRESH snapshot (promoted before the persistence await),
        // not the older one that would overwrite the just-settled turn (data loss).
        let store = MockChatSessionStore()
        let gated = SessionGatedProvider()
        gated.firstChunk = "a1"
        let (vm, _) = makeSUT(store: store, provider: gated)
        await vm.loadSessions()

        // Turn 1: settle (creates the session; settledMessages = [u1, a1]).
        let t1 = Task { @MainActor in await vm.sendMessage("q1") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        await gated.releaseGate(callIndex: 0)
        await t1.value
        let sid = try! #require(vm.activeSessionId)

        // Turn 2: gate the settled-turn UPDATE so it parks; the snapshot is promoted
        // before that parked await.
        gated.firstChunk = "a2"
        await store.gateUpdate()
        let t2 = Task { @MainActor in await vm.sendMessage("q2") }
        while vm.messages.count < 4 { await Task.yield() }
        await gated.releaseGate(callIndex: 1)                 // stream done → saveSettledTurn → update parks
        while await store.parkedUpdateCount < 1 { await Task.yield() }

        // Transition while the settled update is parked. Fire without awaiting (its
        // body queues behind the parked update in the lane; awaiting deadlocks). The
        // settled snapshot was promoted BEFORE the update await (r4 fix), so neither
        // the parked update nor the subsequent seal can lose turn 2. Release the
        // update, drain the lane, then assert the persisted snapshot is fresh.
        let newConv = Task { @MainActor in await vm.newConversation() }
        for _ in 0..<5 { await Task.yield() }
        await store.releaseUpdate()                           // parked update completes, then the seal
        _ = await newConv.value
        _ = await t2.value

        let sealed = store.lastSavedMessages(for: sid)
        #expect(sealed?.count == 4,
                "turn 2 is persisted (settled snapshot promoted before the await) — not dropped by a stale overwrite")
        #expect(sealed?.contains { $0.content == "q2" } == true)
    }

    // MARK: - RACE (Gate-4 structural): the serial lane — an unrelated delete during a
    // settled-turn save for the ACTIVE session does not corrupt the active session.

    @Test @MainActor func unrelatedDeleteDuringActiveSave_doesNotLoseActiveMessages() async {
        // While a settled-turn UPDATE for the ACTIVE session is in flight (gated),
        // delete an unrelated NON-active session. With the serial lane the delete
        // waits for the save to fully complete, so the two cannot interleave across
        // the await — the active session's just-settled messages are not lost.
        let store = MockChatSessionStore()
        let gated = SessionGatedProvider()
        gated.firstChunk = "a1"
        let (vm, _) = makeSUT(store: store, provider: gated)
        await vm.loadSessions()      // empty store → no active session

        // Turn 1: settle so the active session exists (create) + settledMessages set.
        let t1 = Task { @MainActor in await vm.sendMessage("active q1") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        await gated.releaseGate(callIndex: 0)
        await t1.value
        let active = try! #require(vm.activeSessionId)

        // Seed a SEPARATE non-active session AFTER the active one is established, so
        // it is never the active session and a fallback never targets it.
        let other = store.seed(key: Self.bookKey, title: "Other (non-active)",
            messages: [ChatMessage(role: .user, content: "other content")],
            updatedAt: Date(timeIntervalSince1970: 5))
        #expect(other != active)

        // Turn 2: gate the settled-turn UPDATE so the save parks mid-lane.
        gated.firstChunk = "a2"
        await store.gateUpdate()
        let t2 = Task { @MainActor in await vm.sendMessage("active q2") }
        while vm.messages.count < 4 { await Task.yield() }
        await gated.releaseGate(callIndex: 1)                 // stream done → saveSettledTurn → update parks
        while await store.parkedUpdateCount < 1 { await Task.yield() }

        // Delete the UNRELATED non-active session while the active save is parked.
        let del = Task { @MainActor in await vm.deleteSession(other) }
        // The delete must NOT have run yet — it is queued behind the parked save on
        // the lane (no interleave). Release the save so the lane drains in order.
        await store.releaseUpdate()
        await t2.value
        await del.value

        #expect(store.deletedIds.contains(other), "the unrelated session was deleted")
        #expect(vm.activeSessionId == active, "the active session is unchanged")
        // The active session keeps its 4-message settled turn — not clobbered by the
        // interleaved delete.
        let saved = store.lastSavedMessages(for: active)
        #expect(saved?.count == 4)
        #expect(saved?.contains { $0.content == "active q2" } == true)
        #expect(vm.messages.count == 4)
    }

    // MARK: - RACE (Gate-4 WI-3 r6 High): deleting a NON-active session must NOT
    // cancel the ACTIVE session's in-flight stream nor drop its settled-turn save.

    @Test @MainActor func nonActiveDeleteDuringActiveStream_doesNotCancelStream_norLoseTurn() async {
        // A non-active delete must not be treated as a transition against the active
        // send: if it cancelled the active stream (bumping `opCounter`), `runSend`
        // would skip `saveSettledTurn` (opId != opCounter) and the active session's
        // latest turn would never be persisted — a later seal would then write the
        // older snapshot. `deleteSession` only cancels/supersedes when the deleted
        // session IS the active one.
        let store = MockChatSessionStore()
        let gated = SessionGatedProvider()
        gated.firstChunk = "a1"
        let (vm, _) = makeSUT(store: store, provider: gated)
        await vm.loadSessions()      // empty store → no active session

        // Turn 1: settle so the active session exists + settledMessages set.
        let t1 = Task { @MainActor in await vm.sendMessage("active q1") }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }
        await gated.releaseGate(callIndex: 0)
        await t1.value
        let active = try! #require(vm.activeSessionId)
        #expect(store.lastSavedMessages(for: active)?.count == 2)

        // Seed a SEPARATE non-active session.
        let other = store.seed(key: Self.bookKey, title: "Other (non-active)",
            messages: [ChatMessage(role: .user, content: "other content")],
            updatedAt: Date(timeIntervalSince1970: 5))
        #expect(other != active)

        // Turn 2 on the ACTIVE session: parks mid-stream (gate 1 not yet released).
        gated.firstChunk = "a2"
        let t2 = Task { @MainActor in await vm.sendMessage("active q2") }
        while vm.messages.count < 4 { await Task.yield() }
        while vm.messages.last?.content.isEmpty ?? true { await Task.yield() }

        // Delete the UNRELATED non-active session while turn 2's stream is parked.
        // This must NOT cancel the active stream (no opCounter bump for a non-active
        // delete), so turn 2 still reaches its settled-turn save.
        await vm.deleteSession(other)
        #expect(store.deletedIds.contains(other), "the unrelated session was deleted")
        #expect(vm.activeSessionId == active, "a non-active delete leaves the active session unchanged")

        // Release turn 2's stream; it must COMPLETE and persist the settled turn.
        await gated.releaseGate(callIndex: 1)
        await t2.value

        let saved = store.lastSavedMessages(for: active)
        #expect(saved?.count == 4,
                "the active turn is saved — the non-active delete did not cancel its stream")
        #expect(saved?.contains { $0.content == "active q2" } == true)
    }

    // MARK: - RACE (Gate-4 structural): two concurrent transitions serialize to a
    // CLEAN single-session end state (no corruption). The deterministic
    // "later-wins" case is covered by `rapidSwitch_BthenC_olderLoadAbandoned`,
    // which orders the two transitions via a gated fetch.

    @Test @MainActor func concurrentTransitions_serialize_toCleanSingleSession() async {
        let store = MockChatSessionStore()
        let b = store.seed(key: Self.bookKey, title: "B",
            messages: [ChatMessage(role: .user, content: "B content")],
            updatedAt: Date(timeIntervalSince1970: 20))
        let c = store.seed(key: Self.bookKey, title: "C",
            messages: [ChatMessage(role: .user, content: "C content")],
            updatedAt: Date(timeIntervalSince1970: 30))
        let (vm, _) = makeSUT(store: store)
        await vm.loadSessions()       // loads C (most-recent non-empty)

        // `async let` gives NO ordering guarantee on which switch runs its
        // synchronous pre-lane (token bump) first, so which one "wins" is not
        // deterministic. The serial lane's guarantee is that the two bodies cannot
        // interleave — the end state is ONE cleanly-loaded session, never a mix.
        async let first: Void = vm.switchToSession(b)
        async let second: Void = vm.switchToSession(c)
        _ = await (first, second)

        #expect(vm.messages.count == 1, "no interleave corruption — exactly one session loaded")
        let landed = vm.activeSessionId
        #expect(landed == b || landed == c, "the end state is cleanly one of the two sessions")
        if landed == b { #expect(vm.messages.first?.content == "B content") }
        if landed == c { #expect(vm.messages.first?.content == "C content") }
    }
}
