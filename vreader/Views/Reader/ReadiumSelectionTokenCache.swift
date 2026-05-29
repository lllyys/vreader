// Purpose: Feature #42 Phase 1 WI-8 (new-highlight slice) — single-entry
// token→Readium-`Selection` cache that round-trips a live Readium text selection
// through the designed `SelectionPopoverView` pipeline.
//
// **Why this exists** (mirror of the legacy `EPUBSelectionTokenCache`): the
// SelectionPopover pipeline carries a `TextSelectionInfo` (UTF-16 offsets) end-
// to-end, but a Readium `Selection` anchors by a `Locator` text-quote that
// `TextSelectionInfo` cannot represent. So the Readium host stashes the full
// `Selection` here under a freshly minted `UUID`, posts only that token
// (`SelectionPopoverRequestPayload.requestToken`), and resolves it back when the
// popover's action notification returns the token.
//
// **Single-entry by design**: the popover is a modal sheet — at most one
// selection is ever pending. `store` replaces any prior entry (a new selection
// supersedes an abandoned one); `resolve` is identity-checked by token and
// consumes on hit, so a replayed or stale notification cannot double-fire.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumEPUBHost+Highlights.swift,
//   SelectionPopoverPresenter.swift (SelectionPopoverRequestPayload)

#if canImport(UIKit)
import Foundation
import ReadiumNavigator

/// Single-entry `UUID`→Readium `Selection` cache for the Readium EPUB host's
/// SelectionPopover round-trip (WI-8 new-highlight).
struct ReadiumSelectionTokenCache {

    private var entry: (token: UUID, selection: Selection)?

    init() {}

    /// `true` when no selection is pending.
    var isEmpty: Bool { entry == nil }

    /// Store `selection`, replacing any prior pending entry, and return the token
    /// to post on `.readerSelectionPopoverRequested`. `token` is injectable
    /// purely so tests can pin a deterministic value; production takes `UUID()`.
    mutating func store(_ selection: Selection, token: UUID = UUID()) -> UUID {
        entry = (token, selection)
        return token
    }

    /// Resolve and consume the selection for `token`. Returns `nil` — without
    /// mutating — on any miss (nil token, mismatched token, or no entry). On a
    /// hit the entry is cleared so the same notification delivered twice cannot
    /// create two highlights.
    mutating func resolve(token: UUID?) -> Selection? {
        guard let token, let entry, entry.token == token else { return nil }
        let selection = entry.selection
        self.entry = nil
        return selection
    }

    /// Drop any pending entry without resolving it.
    mutating func clear() {
        entry = nil
    }
}
#endif
