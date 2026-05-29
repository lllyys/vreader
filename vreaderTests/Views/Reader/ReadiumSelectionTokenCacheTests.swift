// Purpose: Feature #42 Phase 1 WI-8 (new-highlight slice) — unit tests for the
// single-entry `ReadiumSelectionTokenCache` (store/resolve/clear identity +
// consume-on-hit), the Readium counterpart of `EPUBSelectionTokenCacheTests`.
//
// @coordinates-with vreader/Views/Reader/ReadiumSelectionTokenCache.swift

#if canImport(UIKit)
import Testing
import Foundation
import ReadiumShared
import ReadiumNavigator
@testable import vreader

@MainActor
@Suite("ReadiumSelectionTokenCache (WI-8 new-highlight)")
struct ReadiumSelectionTokenCacheTests {

    private func selection(highlight: String) -> Selection {
        Selection(
            locator: ReadiumShared.Locator(
                href: RelativeURL(path: "OEBPS/ch1.xhtml")!,
                mediaType: .xhtml,
                locations: .init(progression: 0.5),
                text: .init(highlight: highlight)
            ),
            frame: .zero
        )
    }

    @Test func storeReturnsTokenAndResolves() {
        var cache = ReadiumSelectionTokenCache()
        #expect(cache.isEmpty)
        let token = cache.store(selection(highlight: "phrase"))
        #expect(!cache.isEmpty)
        let resolved = cache.resolve(token: token)
        #expect(resolved?.locator.text.highlight == "phrase")
        // Consumed on hit — a replayed notification can't double-fire.
        #expect(cache.isEmpty)
        #expect(cache.resolve(token: token) == nil)
    }

    @Test func resolveNilTokenMisses() {
        var cache = ReadiumSelectionTokenCache()
        _ = cache.store(selection(highlight: "x"))
        #expect(cache.resolve(token: nil) == nil)
        // Miss must NOT consume the pending entry.
        #expect(!cache.isEmpty)
    }

    @Test func resolveMismatchedTokenMisses() {
        var cache = ReadiumSelectionTokenCache()
        _ = cache.store(selection(highlight: "x"), token: UUID())
        #expect(cache.resolve(token: UUID()) == nil)
        #expect(!cache.isEmpty)
    }

    @Test func storeReplacesPriorEntry() {
        var cache = ReadiumSelectionTokenCache()
        let first = cache.store(selection(highlight: "first"))
        let second = cache.store(selection(highlight: "second"))
        // The superseded token no longer resolves.
        #expect(cache.resolve(token: first) == nil)
        #expect(cache.resolve(token: second)?.locator.text.highlight == "second")
    }

    @Test func clearDropsEntry() {
        var cache = ReadiumSelectionTokenCache()
        let token = cache.store(selection(highlight: "x"))
        cache.clear()
        #expect(cache.isEmpty)
        #expect(cache.resolve(token: token) == nil)
    }
}
#endif
