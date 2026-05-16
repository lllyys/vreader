// Purpose: Feature #60 WI-7c5b — single-entry token→event cache that
// lets the EPUB reader round-trip a long-press selection through the
// SelectionPopover pipeline.
//
// **Why this exists**: TXT / MD / chunked anchor a selection by
// UTF-16 offsets, which `TextSelectionInfo` carries end-to-end. EPUB
// anchors by a DOM-path `EPUBSerializedRange` inside
// `ReaderSelectionEvent.anchor` — a shape `TextSelectionInfo` cannot
// represent. So the EPUB container stashes the full
// `ReaderSelectionEvent` here under a freshly minted `UUID`, posts
// only that token (WI-7c5a's `SelectionPopoverRequestPayload.requestToken`),
// and resolves the event back when the popover's action notification
// returns the token.
//
// **Single-entry by design**: the SelectionPopover is a modal sheet —
// at most one selection is ever pending. `store` replaces any prior
// entry (a new long-press supersedes an abandoned one), so the cache
// is inherently memory-bounded. `resolve` is identity-checked by
// token and consumes on hit, so a replayed or stale notification
// cannot double-fire or mis-resolve onto a different selection.
//
// @coordinates-with: EPUBReaderContainerView.swift,
//   SelectionPopoverPresenter.swift (SelectionPopoverRequestPayload),
//   ReaderNotifications.swift (ReaderSelectionEvent)

#if canImport(UIKit)
import Foundation

/// Single-entry `UUID`→`ReaderSelectionEvent` cache for the EPUB
/// SelectionPopover round-trip (WI-7c5b).
struct EPUBSelectionTokenCache {

    private var entry: (token: UUID, event: ReaderSelectionEvent)?

    init() {}

    /// `true` when no selection is pending.
    var isEmpty: Bool { entry == nil }

    /// Store `event`, replacing any prior pending entry, and return
    /// the token to post on `.readerSelectionPopoverRequested`.
    ///
    /// `token` is injectable purely so tests can pin a deterministic
    /// value; production always takes the `UUID()` default.
    mutating func store(_ event: ReaderSelectionEvent, token: UUID = UUID()) -> UUID {
        entry = (token, event)
        return token
    }

    /// Resolve and consume the event for `token`.
    ///
    /// Returns `nil` — without mutating — on any miss: a `nil` token
    /// (a TXT/MD producer's tokenless action arriving while an EPUB
    /// reader happens to be cached), a token that doesn't match the
    /// pending entry (stale / replayed notification), or no pending
    /// entry at all. On a hit the entry is cleared so the same
    /// notification delivered twice cannot create two highlights.
    mutating func resolve(token: UUID?) -> ReaderSelectionEvent? {
        guard let token, let entry, entry.token == token else { return nil }
        let event = entry.event
        self.entry = nil
        return event
    }

    /// Drop any pending entry without resolving it.
    mutating func clear() {
        entry = nil
    }
}
#endif
