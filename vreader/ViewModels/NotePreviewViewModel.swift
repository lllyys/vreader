// Purpose: Feature #55 WI-3 — `NotePreviewViewModel`, the view model behind
// the tap-on-annotated-text note preview. Consumes a `.readerHighlightTapped`
// event, looks the tapped highlight up via `HighlightLookup`, and publishes
// the `NotePreviewContent` a preview surface (`NoteCallout` / `NotePreviewSheet`)
// renders.
//
// Key decisions:
// - `@Observable @MainActor` — the codebase convention for reader-side view
//   models (`HighlightListViewModel`, `LibraryViewModel`).
// - Persistence is the `HighlightLookup` boundary protocol, not a concrete
//   actor, so the view model is unit-testable with a mock.
// - `handleTap` is `async` and crosses the `PersistenceActor` boundary. Two
//   rapid taps can have their lookups finish out of order. A monotonic
//   `latestTapToken` guards this: `handleTap` captures the token before the
//   `await` and publishes `presented` only if the captured token is still the
//   latest afterward — so the newest tap always wins, and an older slow
//   lookup is silently discarded. `dismiss()` bumps the token too, so a
//   lookup that was in flight when the user dismissed cannot resurrect a card.
// - A deleted-race (the highlight was removed between paint and tap) resolves
//   to `nil` and is a no-op — `presented` stays clear.
//
// @coordinates-with: HighlightLookup.swift, NotePreviewContent.swift,
//   NotePreviewPresenter.swift, ReaderNotifications.swift (ReaderHighlightTapEvent)

import Foundation
import OSLog

/// View model for the tap-on-annotated-text note preview.
@Observable
@MainActor
final class NotePreviewViewModel {

    /// The note-preview content currently presented, or `nil` when nothing is
    /// shown. A preview surface observes this to mount/dismiss itself.
    private(set) var presented: NotePreviewContent?

    private let persistence: any HighlightLookup
    private let bookFingerprintKey: String
    private let log = Logger(subsystem: "com.vreader.app", category: "NotePreview")

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
    /// and publishes its note-preview content. Out-of-order safe — only the
    /// newest tap's result is published.
    func handleTap(_ event: ReaderHighlightTapEvent) async {
        latestTapToken &+= 1
        let myToken = latestTapToken

        let record: HighlightRecord?
        do {
            record = try await persistence.highlight(
                withID: event.highlightID, forBookWithKey: bookFingerprintKey
            )
        } catch {
            log.error("highlight lookup failed: \(String(describing: error), privacy: .public)")
            // A failed lookup behaves like a not-found: only clear if this is
            // still the latest tap, so it can't wipe a newer tap's result.
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
        presented = NotePreviewPresenter.content(for: record, sourceRect: event.sourceRect)
    }

    /// Dismisses the preview. Bumps the tap token so a lookup that is still in
    /// flight cannot resurrect a card after the user dismissed.
    func dismiss() {
        latestTapToken &+= 1
        presented = nil
    }
}
