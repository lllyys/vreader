// Purpose: One-shot intent holder used by `EPUBReaderContainerView` to
// remember "after the next chapter's pagination is ready, jump to the
// LAST page". This is the missing link between
// `EPUBReaderViewModel.navigatePrevious()` — which lands on page 0 of
// the previous chapter — and design §2.2's requirement that a left-tap
// from the first page of chapter N go to the LAST page of chapter N-1.
//
// Why a separate type: `onPaginationReady` fires after the chapter has
// loaded and `setupPagination(...)` has computed `totalPages`. The
// container's `@State` is the natural carrier, but a free-floating
// `@State var pendingLandOnLastPage: Bool` is too easy to read in the
// wrong order (clear before consume). Wrapping the intent in a tiny
// `@MainActor` reference type gives us a fail-safe API:
//   - `armWantsLastPage()` — set the intent.
//   - `consume(totalPages:)` — resolve to a page index AND clear the
//     intent atomically. Returns nil when pagination is not yet ready
//     (totalPages <= 0), keeping the intent armed for the next callback.
//   - `clear()` — drop the intent without resolving (used when a
//     subsequent forward navigation supersedes the pending wrap).
//
// Key decisions:
// - Reference type (`final class`) so the container can pass it through
//   the bridge callback without `@State` value-semantics copying.
// - `@MainActor` because the only callers are SwiftUI view code and the
//   bridge's `@MainActor` callback closures — no cross-actor races.
// - `consume(totalPages:)` is the only legitimate way to clear an armed
//   intent in the successful path. A test asserts `clear()` is also
//   available for explicit-cancel cases.
//
// Design source: dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md §2.2
//
// @coordinates-with: EPUBChapterNavigationRouter.swift,
//                    EPUBReaderContainerView.swift

import Foundation

/// One-shot intent: "land on the LAST page of the next-loaded chapter".
@MainActor
final class EPUBChapterWrapPendingTarget {

    private(set) var wantsLastPage: Bool = false

    init() {}

    /// Mark the intent so the next `consume(totalPages:)` call resolves.
    func armWantsLastPage() {
        wantsLastPage = true
    }

    /// Resolve the armed intent against the now-known `totalPages` for
    /// the new chapter. Returns the zero-based last-page index and
    /// clears the intent. Returns `nil` when:
    /// - the intent is not armed (no caller asked to wrap-and-jump), or
    /// - `totalPages <= 0` (pagination not yet computed — the intent
    ///   stays armed so a subsequent callback with a valid totalPages
    ///   can resolve it).
    func consume(totalPages: Int) -> Int? {
        guard wantsLastPage else { return nil }
        guard totalPages > 0 else { return nil }
        wantsLastPage = false
        return totalPages - 1
    }

    /// Drop the intent without resolving — used when a later command
    /// supersedes the pending wrap (e.g. the user navigated forward
    /// before the previous chapter's pagination became ready).
    func clear() {
        wantsLastPage = false
    }

    /// Round-2 audit fix [Medium]: dedicated entry point called by the
    /// container's non-wrap chapter navigation paths
    /// (`.readerNavigateToLocator` from TOC / search / annotation jump,
    /// `handleProgressSeek` from the bottom scrubber). Functionally
    /// identical to `clear()` today but distinguishes the call-site
    /// intent: "a non-wrap chapter navigation is starting; any pending
    /// backward-wrap intent must NOT bleed into this chapter's
    /// `onPaginationReady`." Keeping the entry point separate makes
    /// future grep-for-callers (regression checks, audits) precise.
    func cancelBecauseUnrelatedNavigationStarted() {
        wantsLastPage = false
    }
}
