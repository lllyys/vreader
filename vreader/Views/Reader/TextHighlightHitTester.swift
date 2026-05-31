// Purpose: Pure hit-test helper that maps a tap's character index in a
// UITextView to the highlight UUID painted at that location. Used by TXT/MD
// reader-bridge coordinators on tap to decide whether to fire
// `.readerHighlightTapped` (with the resolved UUID — feature #64's unified
// highlight-action popover observes it) or fall through to the existing
// `.readerContentTapped` chrome-toggle path.
//
// Kept separate from the bridge coordinator so the resolution logic is
// fully unit-testable without needing a live UITextView.
//
// @coordinates-with: TXTTextViewBridgeCoordinator.swift,
//   TextReaderUIState.swift, HighlightPopoverModifier.swift,
//   ReaderNotifications.swift

import Foundation

/// One persisted highlight's identity + character range in the active
/// text view. Threaded from `TextReaderUIState.persistedHighlightLookup`
/// through the TXT/MD bridge to the coordinator's hit-test.
struct PersistedHighlightLookupEntry: Sendable, Equatable {
    let id: UUID
    let range: NSRange
    /// Whether this highlight carries a non-empty note. Bug #295: when a tap
    /// is ambiguous between overlapping highlights, the noted one is preferred
    /// so a tap never opens an empty editor over a note that was right there.
    let hasNote: Bool

    init(id: UUID, range: NSRange, hasNote: Bool = false) {
        self.id = id
        self.range = range
        self.hasNote = hasNote
    }
}

enum TextHighlightHitTester {
    /// Returns the lookup entry whose range contains `charIndex`. When
    /// multiple ranges overlap (e.g., a highlight inside a longer highlight),
    /// the topmost (most recently added) entry wins — EXCEPT that a noted
    /// highlight is preferred over a note-less one (Bug #295): tapping an
    /// overlap that includes a noted highlight opens that note rather than an
    /// empty editor over a color-only highlight on top. When no candidate is
    /// noted (or only one covers the index), the topmost wins as before, so a
    /// genuine color-only highlight still shows its "Add a note…" state.
    ///
    /// Returns nil when no entry covers the index.
    static func hitTest(
        charIndex: Int,
        in lookup: [PersistedHighlightLookupEntry]
    ) -> PersistedHighlightLookupEntry? {
        // Iterate in reverse so the last-added (visually topmost) range is seen
        // first. `NSLocationInRange` excludes the upper bound, matching
        // UITextView's character-index semantics where the index immediately
        // after the range is "outside" the highlight.
        var topmostCovering: PersistedHighlightLookupEntry?
        for entry in lookup.reversed() {
            guard entry.range.length > 0 else { continue }
            guard NSLocationInRange(charIndex, entry.range) else { continue }
            // The topmost noted candidate wins outright (Bug #295).
            if entry.hasNote { return entry }
            // Otherwise remember the topmost covering entry as the fallback.
            if topmostCovering == nil { topmostCovering = entry }
        }
        return topmostCovering
    }
}
