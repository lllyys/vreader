// Purpose: Feature #42 Phase 1 WI-8 (new-highlight slice) — unit tests for the
// single-entry `ReadiumSelectionTokenCache` (store/resolve/clear identity +
// consume-on-hit), the Readium counterpart of `EPUBSelectionTokenCacheTests`.
//
// The cache is generic over the stored value; production specializes it to
// `<Selection>` (whose initializer is `internal`, so it can't be built in tests).
// These tests exercise the token round-trip with a `String` stand-in — the
// round-trip logic is value-type-agnostic, so a stand-in fully covers it.
//
// @coordinates-with vreader/Views/Reader/ReadiumSelectionTokenCache.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReadiumSelectionTokenCache (WI-8 new-highlight)")
struct ReadiumSelectionTokenCacheTests {

    @Test func storeReturnsTokenAndResolves() {
        var cache = ReadiumSelectionTokenCache<String>()
        #expect(cache.isEmpty)
        let token = cache.store("phrase")
        #expect(!cache.isEmpty)
        let resolved = cache.resolve(token: token)
        #expect(resolved == "phrase")
        // Consumed on hit — a replayed notification can't double-fire.
        #expect(cache.isEmpty)
        #expect(cache.resolve(token: token) == nil)
    }

    @Test func resolveNilTokenMisses() {
        var cache = ReadiumSelectionTokenCache<String>()
        _ = cache.store("x")
        #expect(cache.resolve(token: nil) == nil)
        // Miss must NOT consume the pending entry.
        #expect(!cache.isEmpty)
    }

    @Test func resolveMismatchedTokenMisses() {
        var cache = ReadiumSelectionTokenCache<String>()
        _ = cache.store("x", token: UUID())
        #expect(cache.resolve(token: UUID()) == nil)
        #expect(!cache.isEmpty)
    }

    @Test func storeReplacesPriorEntry() {
        var cache = ReadiumSelectionTokenCache<String>()
        let first = cache.store("first")
        let second = cache.store("second")
        // The superseded token no longer resolves.
        #expect(cache.resolve(token: first) == nil)
        #expect(cache.resolve(token: second) == "second")
    }

    @Test func clearDropsEntry() {
        var cache = ReadiumSelectionTokenCache<String>()
        let token = cache.store("x")
        cache.clear()
        #expect(cache.isEmpty)
        #expect(cache.resolve(token: token) == nil)
    }
}
