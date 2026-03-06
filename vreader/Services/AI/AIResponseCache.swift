// Purpose: In-memory LRU cache for AI responses keyed by request parameters.
// Prevents redundant API calls for identical context+action combinations.
//
// Key decisions:
// - Actor-based for thread safety (Swift 6 strict concurrency).
// - LRU eviction using a doubly-linked list order tracked via array.
// - Max capacity configurable, defaults to 100 entries.
// - Cache key includes promptVersion so prompt changes invalidate stale entries.
// - clearAll() for consent revocation cleanup.
//
// @coordinates-with: AIService.swift, AITypes.swift

import Foundation

/// Thread-safe in-memory LRU cache for AI responses.
actor AIResponseCache {

    /// Maximum number of cached responses before eviction.
    let maxCapacity: Int

    /// Stored entries keyed by cache key.
    private var entries: [String: AIResponse] = [:]

    /// Access order for LRU eviction (most recently used at end).
    private var accessOrder: [String] = []

    init(maxCapacity: Int = 100) {
        self.maxCapacity = maxCapacity
    }

    /// Returns the cached response for the given key, or nil on miss.
    /// Moves the key to the most-recently-used position.
    func get(forKey key: String) -> AIResponse? {
        guard let response = entries[key] else { return nil }
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        return response
    }

    /// Stores a response in the cache, evicting the least-recently-used entry if at capacity.
    func set(_ response: AIResponse, forKey key: String) {
        // If key already exists, remove from order tracking
        if entries[key] != nil {
            accessOrder.removeAll { $0 == key }
        }

        entries[key] = response
        accessOrder.append(key)

        // Evict LRU entries if over capacity
        while entries.count > maxCapacity, let lruKey = accessOrder.first {
            accessOrder.removeFirst()
            entries.removeValue(forKey: lruKey)
        }
    }

    /// Removes all cached entries. Used when consent is revoked.
    func clearAll() {
        entries.removeAll()
        accessOrder.removeAll()
    }

    /// The current number of cached entries.
    var count: Int {
        entries.count
    }
}
