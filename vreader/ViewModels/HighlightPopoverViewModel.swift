// Purpose: Feature #64 WI-1 — `HighlightPopoverViewModel`, the view model
// behind the unified cross-format highlight-action popover. Consumes a
// `.readerHighlightTapped` event, looks the tapped highlight up via
// `HighlightLookup`, and publishes the `HighlightPopoverContent` the popover
// surfaces (`HighlightActionCard` / `HighlightActionSheet`) render.
//
// Supersedes feature #55's `NotePreviewViewModel` (deleted in WI-10).
//
// Key decisions:
// - `@Observable @MainActor` — the codebase convention for reader-side view
//   models (`NotePreviewViewModel`, `HighlightListViewModel`, `LibraryViewModel`).
// - Persistence is the `HighlightLookup` boundary protocol, not a concrete
//   actor, so the view model is unit-testable with a mock.
// - `handleTap` is `async` and crosses the `PersistenceActor` boundary. Two
//   rapid taps can have their lookups finish out of order. A monotonic
//   `latestTapToken` guards this: `handleTap` captures the token before the
//   `await` and publishes `presented` only if the captured token is still the
//   latest afterward — so the newest tap always wins, and an older slow
//   lookup is silently discarded. `dismiss()` bumps the token too, so a
//   lookup that was in flight when the user dismissed cannot resurrect a card.
//   This is the same out-of-order guard feature #55's `NotePreviewViewModel`
//   established.
// - A deleted-race (the highlight was removed between paint and tap) resolves
//   to `nil` and is a no-op — `presented` stays clear.
// - `refreshPresented(with:)` rebuilds `presented` from a mutated record
//   after a successful recolor / note-save, preserving the original tap's
//   `sourceRect` and `chapter` so the popover stays anchored in place.
//
// @coordinates-with: HighlightLookup.swift, HighlightPopoverContent.swift,
//   HighlightPopoverModifier.swift, ReaderNotifications.swift
//   (ReaderHighlightTapEvent)

import Foundation
import OSLog

/// View model for the unified cross-format highlight-action popover.
@Observable
@MainActor
final class HighlightPopoverViewModel {

    /// The popover content currently presented, or `nil` when nothing is
    /// shown. A popover surface observes this to mount/dismiss itself.
    private(set) var presented: HighlightPopoverContent?

    /// Feature #1121: the sub-mode the popover should OPEN in for the pending
    /// `presented` — `.editing` when the resolving tap carried `openInEditMode`
    /// (the Edit-handoff auto-open), else `.reading`. The modifier passes this to
    /// `router.present(_:initialMode:)`, fixing the lost-flag pipeline gap.
    private(set) var presentedInitialMode: HighlightPopoverMode = .reading

    private let persistence: any HighlightLookup
    /// The book this reader resolves highlights against. Feature #1121: the
    /// modifier reads it to ignore an edit-request targeting a different book
    /// (a same-book multi-window guard; cross-book is already a lookup no-op).
    let bookFingerprintKey: String
    private let log = Logger(subsystem: "com.vreader.app", category: "HighlightPopover")

    /// Monotonic tap token. Incremented on every `handleTap` and every
    /// `dismiss`. A `handleTap` publishes its result only if the token it
    /// captured before its `await` is still the latest — guards out-of-order
    /// async lookups so the newest tap always wins.
    private var latestTapToken: UInt64 = 0

    init(persistence: any HighlightLookup, bookFingerprintKey: String) {
        self.persistence = persistence
        self.bookFingerprintKey = bookFingerprintKey
    }

    /// Handles a `.readerHighlightTapped` event: looks up the tapped highlight
    /// and publishes its popover content. `chapter` is the optional chapter /
    /// location string for the meta row, supplied by the per-format container.
    /// Out-of-order safe — only the newest tap's result is published.
    func handleTap(_ event: ReaderHighlightTapEvent, chapter: String?) async {
        latestTapToken &+= 1
        let myToken = latestTapToken
        // Feature #1121: carry the open-in-edit intent so the modifier presents
        // the resolved content in `.editing` (a normal tap leaves it `.reading`).
        presentedInitialMode = event.openInEditMode ? .editing : .reading

        let record: HighlightRecord?
        do {
            record = try await persistence.highlight(
                withID: event.highlightID, forBookWithKey: bookFingerprintKey
            )
        } catch {
            log.error("highlight lookup failed: \(String(describing: error), privacy: .public)")
            // A failed lookup behaves like a not-found: only clear if this is
            // still the latest tap, so it cannot wipe a newer tap's result.
            if myToken == latestTapToken { presented = nil }
            return
        }

        // A newer tap (or a dismiss) superseded this one — discard the result.
        guard myToken == latestTapToken else { return }

        guard let record else {
            // Deleted-race: the highlight was removed between paint and tap.
            presented = nil
            return
        }
        presented = HighlightPopoverPresenter.content(
            for: record, sourceRect: event.sourceRect, chapter: chapter
        )
    }

    /// Dismisses the popover. Bumps the tap token so a lookup that is still in
    /// flight cannot resurrect a card after the user dismissed.
    func dismiss() {
        latestTapToken &+= 1
        presented = nil
    }

    /// Rebuilds `presented` from a mutated record after a `.success` outcome
    /// (color / note change), preserving the same `sourceRect` and `chapter`
    /// so the popover stays anchored. A no-op when nothing is presented or the
    /// mutated record is for a different highlight than the one on screen.
    func refreshPresented(with record: HighlightRecord) {
        guard let current = presented, current.id == record.highlightId else { return }
        presented = HighlightPopoverPresenter.content(
            for: record, sourceRect: current.sourceRect, chapter: current.chapter
        )
    }
}
