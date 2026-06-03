// Purpose: Which of the reader's own annotation kinds the AI Chat tab folds
// into the book context — Notes / Highlights / Bookmarks. Drives the Chat
// context-bar sources chip + sources popover (Feature #86 WI-2+ / WI-4).
//
// Key decisions:
// - Notes + Highlights default ON, Bookmarks default OFF (the #1455 design).
// - `activeCount` is the chip's green count badge; `allOff` collapses the chip
//   to a muted "Off" and means none of the user's marks leave the device.
// - A pure value type so the assembler + tests stay UI-free.
//
// @coordinates-with: ChatAnnotationContext.swift, ChatContextBar.swift (WI-4),
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/chat-ai-scope-sources.md`

import Foundation

/// The reader-annotation kinds folded into the Chat AI context. Feature #86 WI-2+.
struct ChatSourceSelection: Sendable, Equatable {
    /// Standalone notes + notes attached to highlights. Default ON.
    var notes: Bool
    /// Text highlights. Default ON.
    var highlights: Bool
    /// Bookmarks. Default OFF.
    var bookmarks: Bool

    init(notes: Bool = true, highlights: Bool = true, bookmarks: Bool = false) {
        self.notes = notes
        self.highlights = highlights
        self.bookmarks = bookmarks
    }

    /// The design default: Notes + Highlights on, Bookmarks off.
    static var `default`: ChatSourceSelection { ChatSourceSelection() }

    /// The number of toggled-on kinds — the green count badge on the chip.
    var activeCount: Int {
        (notes ? 1 : 0) + (highlights ? 1 : 0) + (bookmarks ? 1 : 0)
    }

    /// True when no kind is selected — the chip reads "Sources · Off" and none
    /// of the user's marks are sent to the model.
    var allOff: Bool { activeCount == 0 }
}
