// Purpose: Feature #60 WI-7c5b — pins the `EPUBSelectionTokenCache`
// contract: a single-entry token→event cache that round-trips an
// EPUB long-press selection through the SelectionPopover pipeline.
//
// The cache is the pure-logic core of WI-7c5b's EPUB producer /
// consumer swap. The SwiftUI `.onReceive` wiring + the producer
// closure on `EPUBReaderContainerView` are integration / device-
// verify territory (Gate 5a); the identity-by-token logic that
// guards against stale / replayed / cross-format notifications is
// what this file exhaustively pins.

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("Feature #60 WI-7c5b — EPUBSelectionTokenCache")
@MainActor
struct EPUBSelectionTokenCacheTests {

    private func makeEvent(_ text: String = "the rapidity of the infection") -> ReaderSelectionEvent {
        ReaderSelectionEvent(
            selectedText: text,
            anchor: .epub(
                href: "ch1.xhtml",
                cfi: "",
                serializedRange: EPUBSerializedRange(
                    startContainerPath: "/html/body/p[1]",
                    startOffset: 0,
                    endContainerPath: "/html/body/p[1]",
                    endOffset: text.utf16.count
                )
            ),
            sourceRect: CGRect(x: 10, y: 20, width: 100, height: 24)
        )
    }

    // MARK: - Empty state

    @Test("A fresh cache is empty")
    func freshCacheIsEmpty() {
        let cache = EPUBSelectionTokenCache()
        #expect(cache.isEmpty)
    }

    @Test("store makes the cache non-empty and returns the supplied token")
    func storeFillsCache() {
        var cache = EPUBSelectionTokenCache()
        let token = UUID()
        let returned = cache.store(makeEvent(), token: token)
        #expect(returned == token)
        #expect(!cache.isEmpty)
    }

    @Test("store with the default token returns a usable non-nil UUID")
    func storeDefaultTokenIsUsable() {
        var cache = EPUBSelectionTokenCache()
        let token = cache.store(makeEvent())
        // The production path takes the UUID() default — resolve must
        // round-trip whatever store handed back.
        #expect(cache.resolve(token: token)?.selectedText == "the rapidity of the infection")
    }

    // MARK: - Resolve happy path

    @Test("resolve with the matching token returns the stored event")
    func resolveMatchingTokenReturnsEvent() {
        var cache = EPUBSelectionTokenCache()
        let token = cache.store(makeEvent("World"))
        let event = cache.resolve(token: token)
        #expect(event?.selectedText == "World")
    }

    @Test("resolve consumes the entry — a second resolve with the same token misses")
    func resolveConsumesEntry() {
        var cache = EPUBSelectionTokenCache()
        let token = cache.store(makeEvent())
        _ = cache.resolve(token: token)
        // A notification delivered twice must not create two highlights.
        #expect(cache.resolve(token: token) == nil)
        #expect(cache.isEmpty)
    }

    // MARK: - Resolve miss paths

    @Test("resolve with a nil token misses (tokenless TXT/MD action)")
    func resolveNilTokenMisses() {
        var cache = EPUBSelectionTokenCache()
        _ = cache.store(makeEvent())
        // A TXT/MD producer posts no token; if such an action arrives
        // while an EPUB selection is cached, it must not be resolved.
        #expect(cache.resolve(token: nil) == nil)
        // The miss must NOT consume the pending EPUB entry.
        #expect(!cache.isEmpty)
    }

    @Test("resolve with a non-matching token misses and does not consume")
    func resolveWrongTokenMisses() {
        var cache = EPUBSelectionTokenCache()
        _ = cache.store(makeEvent())
        let staleToken = UUID()
        #expect(cache.resolve(token: staleToken) == nil)
        #expect(!cache.isEmpty)
    }

    @Test("resolve on an empty cache misses")
    func resolveEmptyCacheMisses() {
        var cache = EPUBSelectionTokenCache()
        #expect(cache.resolve(token: UUID()) == nil)
    }

    // MARK: - Replace-on-new-selection

    @Test("store twice replaces — the first token can no longer resolve")
    func storeReplacesPriorEntry() {
        // A second long-press supersedes an abandoned popover. The
        // first selection's token becomes stale; only the second
        // resolves. This is also why the cache stays memory-bounded.
        var cache = EPUBSelectionTokenCache()
        let firstToken = cache.store(makeEvent("first"))
        let secondToken = cache.store(makeEvent("second"))

        #expect(cache.resolve(token: firstToken) == nil,
                "The superseded selection's token must be stale after a new store.")
        // Re-store because the failed resolve above didn't consume —
        // but the entry IS the second one; resolve it.
        #expect(cache.resolve(token: secondToken)?.selectedText == "second")
    }

    @Test("same-text selections at different DOM anchors get distinct tokens")
    func sameTextDifferentAnchorsDistinctTokens() {
        // Codex plan-v10 round 1: identity-by-token (not by text) is
        // the whole point. Two selections of identical text at
        // different DOM ranges must be distinguishable.
        var cache = EPUBSelectionTokenCache()
        let firstToken = cache.store(makeEvent("Pierre"))
        let secondToken = cache.store(makeEvent("Pierre"))
        #expect(firstToken != secondToken)
        // Only the live (second) entry resolves.
        #expect(cache.resolve(token: secondToken)?.selectedText == "Pierre")
    }

    // MARK: - Clear

    @Test("clear empties the cache without resolving")
    func clearEmpties() {
        var cache = EPUBSelectionTokenCache()
        let token = cache.store(makeEvent())
        cache.clear()
        #expect(cache.isEmpty)
        #expect(cache.resolve(token: token) == nil)
    }
}
#endif
