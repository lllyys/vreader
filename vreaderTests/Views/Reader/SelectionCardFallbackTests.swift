// Purpose: Bug #350 — pins the debounced selection-finalized card
// fallback: a settled non-empty selection posts exactly once; the
// editMenu fast path and the fallback dedup in BOTH orders; a collapsed
// selection clears the dedup so re-selecting posts again; a superseded
// change never posts.

import Foundation
import Testing
@testable import vreader

@Suite("SelectionCardFallback (bug #350)")
@MainActor
struct SelectionCardFallbackTests {

    private func makeFallback() -> SelectionCardFallback {
        SelectionCardFallback(debounce: 0.05)
    }

    @Test func settledSelectionPostsExactlyOnce() async throws {
        let fallback = makeFallback()
        var posts: [NSRange] = []
        let range = NSRange(location: 10, length: 4)
        fallback.selectionChanged(range: range) { posts.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts == [range])
        // The same settled range never double-posts.
        fallback.selectionChanged(range: range) { posts.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts == [range])
    }

    @Test func supersededChangeNeverPosts() async throws {
        let fallback = makeFallback()
        var posts: [NSRange] = []
        fallback.selectionChanged(range: NSRange(location: 0, length: 2)) { posts.append($0) }
        // A newer change lands inside the debounce window.
        fallback.selectionChanged(range: NSRange(location: 0, length: 9)) { posts.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts == [NSRange(location: 0, length: 9)])
    }

    @Test func menuPathFirstSuppressesTheFallback() async throws {
        let fallback = makeFallback()
        var posts: [NSRange] = []
        let range = NSRange(location: 5, length: 3)
        // UIKit requested the menu first (the fast path posted).
        #expect(fallback.shouldMenuPathPost(range: range))
        fallback.recordMenuPathPost(range: range)
        // The debounced fallback for the same range must NOT double-post.
        fallback.selectionChanged(range: range) { posts.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts.isEmpty)
    }

    @Test func fallbackFirstSuppressesTheMenuPath() async throws {
        let fallback = makeFallback()
        var posts: [NSRange] = []
        let range = NSRange(location: 5, length: 3)
        fallback.selectionChanged(range: range) { posts.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts == [range])
        // UIKit's late menu request for the same range must skip.
        #expect(!fallback.shouldMenuPathPost(range: range))
        // A DIFFERENT range still posts via the menu path.
        #expect(fallback.shouldMenuPathPost(range: NSRange(location: 9, length: 2)))
    }

    @Test func collapseClearsTheDedupSoReselectionPosts() async throws {
        let fallback = makeFallback()
        var posts: [NSRange] = []
        let range = NSRange(location: 10, length: 4)
        fallback.selectionChanged(range: range) { posts.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts.count == 1)
        // Selection collapses (card dismissed / tap elsewhere)…
        fallback.selectionChanged(range: NSRange(location: 12, length: 0)) { posts.append($0) }
        // …then the user selects the SAME word again — must post again.
        fallback.selectionChanged(range: range) { posts.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts == [range, range])
    }

    @Test func cancelDropsThePendingPost() async throws {
        let fallback = makeFallback()
        var posts = 0
        fallback.selectionChanged(range: NSRange(location: 0, length: 5)) { _ in posts += 1 }
        fallback.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(posts == 0)
    }
}
