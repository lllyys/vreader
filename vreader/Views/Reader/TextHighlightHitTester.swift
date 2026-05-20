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

    init(id: UUID, range: NSRange) {
        self.id = id
        self.range = range
    }
}

enum TextHighlightHitTester {
    /// Returns the lookup entry whose range contains `charIndex`. When
    /// multiple ranges overlap (e.g., a highlight inside a longer
    /// highlight), the most recently added entry wins — matches the
    /// "topmost render order" rule documented in the plan's Risks section.
    ///
    /// Returns nil when no entry covers the index.
    static func hitTest(
        charIndex: Int,
        in lookup: [PersistedHighlightLookupEntry]
    ) -> PersistedHighlightLookupEntry? {
        // Iterate in reverse so the last-added (visually topmost) range
        // wins on overlap. `NSLocationInRange` excludes the upper bound,
        // matching UITextView's character-index semantics where the
        // index immediately after the range is "outside" the highlight.
        for entry in lookup.reversed() {
            guard entry.range.length > 0 else { continue }
            if NSLocationInRange(charIndex, entry.range) { return entry }
        }
        return nil
    }
}
