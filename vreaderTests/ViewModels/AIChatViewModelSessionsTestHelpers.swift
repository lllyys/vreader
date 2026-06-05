// Purpose: Test doubles for Feature #88 WI-3 session-lifecycle tests — an
// in-memory `ChatSessionPersisting` mock (with gateable fetches so the race
// guards are deterministically pinnable) and a session-scoped gated streaming
// provider (a copy of the #87 gated pattern, used only by the session tests so
// it doesn't depend on the `private` doubles in AIChatViewModelTests.swift).
//
// @coordinates-with: AIChatViewModelSessionsTests.swift, ChatSessionPersisting.swift

import Foundation
@testable import vreader

// MARK: - MockChatSessionStore

/// In-memory `ChatSessionPersisting` mock. Records call counts + last writes and
/// supports GATING the `fetchChatSession` (per id) and `fetchChatSessionSummaries`
/// calls so a test can park a load/switch fetch and fire a superseding transition
/// before it resolves (the transition-token + cold-open race tests).
///
/// `@unchecked Sendable`: all mutable state is touched only on the @MainActor VM's
/// hop or the test's @MainActor context; the actor-style `async` methods serialize
/// through the awaits. The gate is a `Sendable` actor.
final class MockChatSessionStore: ChatSessionPersisting, @unchecked Sendable {

    struct Stored {
        var record: ChatSessionRecord
        var renamedTitle: String?
    }

    private var sessions: [UUID: Stored] = [:]
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var fetchSummariesCallCount = 0
    private(set) var deletedIds: [UUID] = []

    // Gating: a parked continuation per gated fetch.
    private let gate = FetchGate()

    // MARK: Seeding (test setup, synchronous)

    @discardableResult
    func seed(key: String, title: String, messages: [ChatMessage], updatedAt: Date) -> UUID {
        let id = UUID()
        let record = ChatSessionRecord(
            sessionId: id, bookFingerprintKey: key, title: title,
            messages: messages, createdAt: updatedAt, updatedAt: updatedAt)
        sessions[id] = Stored(record: record)
        return id
    }

    func seededMessages(for id: UUID) -> [ChatMessage]? { sessions[id]?.record.messages }
    func lastSavedMessages(for id: UUID) -> [ChatMessage]? { sessions[id]?.record.messages }
    func lastSavedTitle(for id: UUID) -> String? { sessions[id]?.record.title }
    func lastRenamedTitle(for id: UUID) -> String? { sessions[id]?.renamedTitle }

    // MARK: Gating controls

    // Arming is `async` + awaited at the call site BEFORE launching the raced task
    // (Gate-4 WI-3 r3 Medium): a fire-and-forget `Task { arm }` could land AFTER the
    // raced op reached `waitIfArmed`, missing the gate → a nondeterministic hang.
    func gateFetch(for id: UUID) async { await gate.arm(.session(id)) }
    func gateSummariesFetch() async { await gate.arm(.summaries) }
    var parkedFetchCount: Int { get async { await gate.parkedCount(.sessionAny) } }
    var parkedSummariesCount: Int { get async { await gate.parkedCount(.summaries) } }
    func releaseFetch(for id: UUID) async { await gate.release(.session(id)) }
    func releaseSummariesFetch() async { await gate.release(.summaries) }
    func gateCreate() async { await gate.arm(.create) }
    func releaseCreate() async { await gate.release(.create) }
    var parkedCreateCount: Int { get async { await gate.parkedCount(.create) } }
    func gateUpdate() async { await gate.arm(.update) }
    func releaseUpdate() async { await gate.release(.update) }
    var parkedUpdateCount: Int { get async { await gate.parkedCount(.update) } }
    var sessionRowCount: Int { sessions.count }

    // MARK: ChatSessionPersisting

    func createChatSession(
        bookFingerprintKey: String, title: String, messages: [ChatMessage]
    ) async throws -> ChatSessionRecord {
        createCallCount += 1
        await gate.waitIfArmed(.create)
        let id = UUID()
        let now = Date()
        let record = ChatSessionRecord(
            sessionId: id, bookFingerprintKey: bookFingerprintKey, title: title,
            messages: messages, createdAt: now, updatedAt: now)
        sessions[id] = Stored(record: record)
        return record
    }

    func fetchChatSessionSummaries(forBookWithKey key: String) async throws -> [ChatSessionSummary] {
        fetchSummariesCallCount += 1
        await gate.waitIfArmed(.summaries)
        return sessions.values
            .map { $0.record }
            .filter { $0.bookFingerprintKey == key }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { rec in
                ChatSessionSummary(
                    id: rec.sessionId, title: rec.title,
                    snippet: rec.messages.last?.content ?? "",
                    updatedAt: rec.updatedAt, messageCount: rec.messages.count)
            }
    }

    func fetchChatSession(sessionId: UUID) async throws -> ChatSessionRecord? {
        await gate.waitIfArmed(.session(sessionId))
        return sessions[sessionId]?.record
    }

    func updateChatSession(
        sessionId: UUID, messages: [ChatMessage], title: String?
    ) async throws -> ChatSessionRecord {
        updateCallCount += 1
        await gate.waitIfArmed(.update)
        guard var stored = sessions[sessionId] else {
            throw PersistenceError.recordNotFound("ChatSession \(sessionId)")
        }
        let r = stored.record
        let newRecord = ChatSessionRecord(
            sessionId: r.sessionId, bookFingerprintKey: r.bookFingerprintKey,
            title: title ?? r.title, messages: messages,
            createdAt: r.createdAt, updatedAt: Date())
        stored.record = newRecord
        sessions[sessionId] = stored
        return newRecord
    }

    func renameChatSession(sessionId: UUID, title: String) async throws {
        guard var stored = sessions[sessionId] else {
            throw PersistenceError.recordNotFound("ChatSession \(sessionId)")
        }
        stored.renamedTitle = title
        let r = stored.record
        stored.record = ChatSessionRecord(
            sessionId: r.sessionId, bookFingerprintKey: r.bookFingerprintKey,
            title: title, messages: r.messages, createdAt: r.createdAt, updatedAt: Date())
        sessions[sessionId] = stored
    }

    /// When true, `deleteChatSession` throws — used to pin the orphan-cleanup
    /// failure path (Gate-4 WI-3 r2 Medium): a delete failure must not crash / must
    /// leave the VM in a clean state, with the abandoned row retained (logged).
    var failDelete = false

    func deleteChatSession(sessionId: UUID) async throws {
        if failDelete { throw PersistenceError.recordNotFound("forced delete failure") }
        deletedIds.append(sessionId)
        sessions[sessionId] = nil
    }
}

/// Actor backing the mock's gateable fetches. A gate "key" is either the
/// summaries fetch or a specific session id. `waitIfArmed` parks until released.
private actor FetchGate {
    enum Key: Hashable { case summaries; case session(UUID); case sessionAny; case create; case update }

    private var armed: Set<Key> = []
    private var parked: [Key: [CheckedContinuation<Void, Never>]] = [:]
    private var parkedCounts: [Key: Int] = [:]

    func arm(_ key: Key) { armed.insert(key) }

    func parkedCount(_ key: Key) -> Int {
        if key == .sessionAny {
            return parkedCounts.reduce(0) { acc, kv in
                if case .session = kv.key { return acc + kv.value }
                return acc
            }
        }
        return parkedCounts[key] ?? 0
    }

    func waitIfArmed(_ key: Key) async {
        guard armed.contains(key) else { return }
        armed.remove(key)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            parked[key, default: []].append(cont)
            parkedCounts[key, default: 0] += 1
        }
    }

    func release(_ key: Key) {
        guard var conts = parked[key], !conts.isEmpty else { return }
        let cont = conts.removeFirst()
        parked[key] = conts
        parkedCounts[key, default: 0] -= 1
        cont.resume()
    }
}

// MARK: - SessionGatedProvider

/// A streaming provider whose stream yields ONE chunk immediately, then parks on a
/// per-call gate until `releaseGate(callIndex:)` — a session-test-local copy of the
/// #87 GatedChatAIProvider (that one is `private` to AIChatViewModelTests.swift).
final class SessionGatedProvider: AIProvider, @unchecked Sendable {
    let providerName = "SessionGated"
    var firstChunk = "partial "
    var secondChunk = "rest"

    private let registry = SessionGateRegistry()
    var streamRequestCallCount: Int { get async { await registry.callCount } }
    func releaseGate(callIndex index: Int) async { await registry.release(callIndex: index) }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse { throw AIError.invalidResponse }

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        let registry = self.registry
        let first = firstChunk
        let second = secondChunk
        return AsyncThrowingStream { continuation in
            Task {
                let (_, gate) = await registry.registerCall()
                continuation.yield(AIStreamChunk(text: first, isComplete: false))
                await gate.waitForRelease()
                continuation.yield(AIStreamChunk(text: second, isComplete: true))
                continuation.finish()
            }
        }
    }
}

private actor SessionStreamGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released: Bool
    init(preReleased: Bool = false) { released = preReleased }
    func release() {
        if let continuation { self.continuation = nil; continuation.resume() }
        else { released = true }
    }
    func waitForRelease() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if released { released = false; cont.resume() } else { continuation = cont }
        }
    }
}

private actor SessionGateRegistry {
    private var gates: [Int: SessionStreamGate] = [:]
    private var pendingReleases: Set<Int> = []
    private(set) var callCount = 0
    func registerCall() -> (index: Int, gate: SessionStreamGate) {
        let index = callCount
        callCount += 1
        let gate = SessionStreamGate(preReleased: pendingReleases.remove(index) != nil)
        gates[index] = gate
        return (index, gate)
    }
    func release(callIndex index: Int) async {
        if let gate = gates[index] { await gate.release() }
        else { pendingReleases.insert(index) }
    }
}
