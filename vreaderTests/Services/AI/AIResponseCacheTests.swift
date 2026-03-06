// Purpose: Tests for AIResponseCache — store/retrieve, LRU eviction,
// clear all, thread safety via concurrent access.

import Testing
import Foundation
@testable import vreader

@Suite("AIResponseCache")
struct AIResponseCacheTests {

    // MARK: - Helpers

    private func makeResponse(
        content: String = "test response",
        actionType: AIActionType = .summarize,
        promptVersion: String = "v1"
    ) -> AIResponse {
        AIResponse(
            content: content,
            actionType: actionType,
            promptVersion: promptVersion,
            createdAt: Date()
        )
    }

    // MARK: - Store and Retrieve

    @Test func storeAndRetrieveByKey() async {
        let cache = AIResponseCache(maxCapacity: 10)
        let response = makeResponse(content: "Hello AI")
        await cache.set(response, forKey: "key1")

        let result = await cache.get(forKey: "key1")
        #expect(result != nil)
        #expect(result?.content == "Hello AI")
    }

    @Test func cacheMissReturnsNil() async {
        let cache = AIResponseCache(maxCapacity: 10)
        let result = await cache.get(forKey: "nonexistent")
        #expect(result == nil)
    }

    // MARK: - Overwrite

    @Test func setOverwritesExistingKey() async {
        let cache = AIResponseCache(maxCapacity: 10)
        let first = makeResponse(content: "first")
        let second = makeResponse(content: "second")

        await cache.set(first, forKey: "key1")
        await cache.set(second, forKey: "key1")

        let result = await cache.get(forKey: "key1")
        #expect(result?.content == "second")
        let count = await cache.count
        #expect(count == 1)
    }

    // MARK: - LRU Eviction

    @Test func evictsLeastRecentlyUsedAtCapacity() async {
        let cache = AIResponseCache(maxCapacity: 3)

        await cache.set(makeResponse(content: "a"), forKey: "key-a")
        await cache.set(makeResponse(content: "b"), forKey: "key-b")
        await cache.set(makeResponse(content: "c"), forKey: "key-c")

        // Cache is full (3/3). Adding a 4th should evict "key-a" (LRU).
        await cache.set(makeResponse(content: "d"), forKey: "key-d")

        let evicted = await cache.get(forKey: "key-a")
        #expect(evicted == nil, "key-a should have been evicted as LRU")

        let kept = await cache.get(forKey: "key-b")
        #expect(kept?.content == "b")

        let count = await cache.count
        #expect(count == 3)
    }

    @Test func accessPromotesEntryInLRUOrder() async {
        let cache = AIResponseCache(maxCapacity: 3)

        await cache.set(makeResponse(content: "a"), forKey: "key-a")
        await cache.set(makeResponse(content: "b"), forKey: "key-b")
        await cache.set(makeResponse(content: "c"), forKey: "key-c")

        // Access key-a to promote it
        _ = await cache.get(forKey: "key-a")

        // Now key-b is LRU. Adding key-d should evict key-b.
        await cache.set(makeResponse(content: "d"), forKey: "key-d")

        let evicted = await cache.get(forKey: "key-b")
        #expect(evicted == nil, "key-b should have been evicted as LRU")

        let promoted = await cache.get(forKey: "key-a")
        #expect(promoted?.content == "a", "key-a should be retained after access")
    }

    // MARK: - Clear All

    @Test func clearAllRemovesEverything() async {
        let cache = AIResponseCache(maxCapacity: 10)
        await cache.set(makeResponse(content: "a"), forKey: "key-a")
        await cache.set(makeResponse(content: "b"), forKey: "key-b")

        await cache.clearAll()

        let count = await cache.count
        #expect(count == 0)
        #expect(await cache.get(forKey: "key-a") == nil)
        #expect(await cache.get(forKey: "key-b") == nil)
    }

    // MARK: - Edge Cases

    @Test func emptyKeyWorks() async {
        let cache = AIResponseCache(maxCapacity: 10)
        await cache.set(makeResponse(content: "empty-key"), forKey: "")
        let result = await cache.get(forKey: "")
        #expect(result?.content == "empty-key")
    }

    @Test func capacityOfOneEvictsImmediately() async {
        let cache = AIResponseCache(maxCapacity: 1)
        await cache.set(makeResponse(content: "first"), forKey: "a")
        await cache.set(makeResponse(content: "second"), forKey: "b")

        #expect(await cache.get(forKey: "a") == nil)
        #expect(await cache.get(forKey: "b")?.content == "second")
        #expect(await cache.count == 1)
    }

    @Test func unicodeKeys() async {
        let cache = AIResponseCache(maxCapacity: 10)
        await cache.set(makeResponse(content: "cjk"), forKey: "测试键")
        let result = await cache.get(forKey: "测试键")
        #expect(result?.content == "cjk")
    }

    // MARK: - Thread Safety

    @Test func concurrentReadWriteDoesNotCrash() async {
        let cache = AIResponseCache(maxCapacity: 50)

        await withTaskGroup(of: Void.self) { group in
            // 20 concurrent writers
            for i in 0..<20 {
                group.addTask {
                    await cache.set(
                        AIResponse(
                            content: "content-\(i)",
                            actionType: .summarize,
                            promptVersion: "v1",
                            createdAt: Date()
                        ),
                        forKey: "key-\(i)"
                    )
                }
            }
            // 20 concurrent readers
            for i in 0..<20 {
                group.addTask {
                    _ = await cache.get(forKey: "key-\(i)")
                }
            }
        }

        // If we get here without crashing, thread safety works
        let count = await cache.count
        #expect(count <= 50)
        #expect(count > 0)
    }

    // MARK: - Different Action Types as Cache Keys

    @Test func differentActionTypesDifferentKeys() async {
        let cache = AIResponseCache(maxCapacity: 10)
        let summarize = makeResponse(content: "summary", actionType: .summarize)
        let explain = makeResponse(content: "explanation", actionType: .explain)

        await cache.set(summarize, forKey: "book:loc:summarize:v1")
        await cache.set(explain, forKey: "book:loc:explain:v1")

        #expect(await cache.get(forKey: "book:loc:summarize:v1")?.content == "summary")
        #expect(await cache.get(forKey: "book:loc:explain:v1")?.content == "explanation")
        #expect(await cache.count == 2)
    }
}
