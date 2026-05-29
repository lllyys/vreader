// Purpose: Feature #42 Phase 1 WI-8 (new-highlight slice) — single-entry
// token→value cache that round-trips a live Readium text selection through the
// designed `SelectionPopoverView` pipeline.
//
// **Why this exists** (mirror of the legacy `EPUBSelectionTokenCache`): the
// SelectionPopover pipeline carries a `TextSelectionInfo` (UTF-16 offsets) end-
// to-end, but a Readium `Selection` anchors by a `Locator` text-quote that
// `TextSelectionInfo` cannot represent. So the Readium host stashes the full
// `Selection` here under a freshly minted `UUID`, posts only that token
// (`SelectionPopoverRequestPayload.requestToken`), and resolves it back when the
// popover's action notification returns the token.
//
// **Generic over the stored value** so the token round-trip is unit-testable
// without constructing a Readium `Selection` (whose initializer is `internal`).
// Production specializes it to `ReadiumSelectionTokenCache<Selection>`; tests use
// a stand-in value type. The cache holds no Readium types itself, so it needs no
// `ReadiumNavigator` import or UIKit gate.
//
// **Single-entry by design**: the popover is a modal sheet — at most one
// selection is ever pending. `store` replaces any prior entry (a new selection
// supersedes an abandoned one); `resolve` is identity-checked by token and
// consumes on hit, so a replayed or stale notification cannot double-fire.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumEPUBHost+Highlights.swift,
//   SelectionPopoverPresenter.swift (SelectionPopoverRequestPayload)

import Foundation

/// Single-entry `UUID`→`Value` cache for the Readium EPUB host's
/// SelectionPopover round-trip (WI-8 new-highlight). Production stores the live
/// Readium `Selection`; the generic parameter keeps the round-trip testable.
struct ReadiumSelectionTokenCache<Value> {

    private var entry: (token: UUID, value: Value)?

    init() {}

    /// `true` when no value is pending.
    var isEmpty: Bool { entry == nil }

    /// Store `value`, replacing any prior pending entry, and return the token to
    /// post on `.readerSelectionPopoverRequested`. `token` is injectable purely so
    /// tests can pin a deterministic value; production takes `UUID()`.
    mutating func store(_ value: Value, token: UUID = UUID()) -> UUID {
        entry = (token, value)
        return token
    }

    /// Resolve and consume the value for `token`. Returns `nil` — without
    /// mutating — on any miss (nil token, mismatched token, or no entry). On a
    /// hit the entry is cleared so the same notification delivered twice cannot
    /// create two highlights.
    mutating func resolve(token: UUID?) -> Value? {
        guard let token, let entry, entry.token == token else { return nil }
        let value = entry.value
        self.entry = nil
        return value
    }

    /// Drop any pending entry without resolving it.
    mutating func clear() {
        entry = nil
    }
}
