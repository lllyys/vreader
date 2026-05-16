// Purpose: Feature #60 WI-7a — UI-presentation enum listing the four
// action buttons that appear in the new-selection `SelectionPopoverView`
// (WI-7b will render). One case per slot in the design bundle's
// `vreader-reader.jsx:475-491` toolbar: Note / Translate / Ask AI /
// Read. Ask AI is the accent slot (the design's `primary: true`
// button).
//
// Distinct from `SelectionPopoverAction` (WI-3): the action enum is
// the dispatch payload (consumed by the WI-7b handler that routes
// actions to highlight/note/translate/AI/TTS pipelines), while this
// type is the *visual layout* — it pins display order, labels, SF
// symbols, accessibility identifiers, and the accent slot identity
// against the design bundle.
//
// A regression that reorders / drops / adds a row, swaps the accent
// target, or renames an accessibility identifier fails the contract
// tests (`SelectionPopoverActionRowTests`) before any SwiftUI render
// path runs.
//
// @coordinates-with: SelectionPopoverAction.swift, NamedHighlightColor.swift

import Foundation

/// Visible action-button slot in the SelectionPopover toolbar.
/// Order matches the design bundle's `vreader-reader.jsx:475-491`
/// array exactly. `CaseIterable.allCases` returns the four cases in
/// declared order; consumer views render them via
/// `ForEach(SelectionPopoverActionRow.allCases)`.
enum SelectionPopoverActionRow: String, CaseIterable, Equatable {
    case note
    case translate
    case askAI
    case read

    /// Dispatch payload emitted when the row is tapped. Consumed by
    /// the WI-7b action router that bridges to the existing
    /// highlight/note/translate/AI/TTS pipelines.
    var dispatchAction: SelectionPopoverAction {
        switch self {
        case .note:      return .note
        case .translate: return .translate
        case .askAI:     return .askAI
        case .read:      return .read
        }
    }

    /// User-facing label. Short — the popover's bottom toolbar shows
    /// these in 10.5pt typography under the icon.
    var label: String {
        switch self {
        case .note:      return "Note"
        case .translate: return "Translate"
        case .askAI:     return "Ask AI"
        case .read:      return "Read"
        }
    }

    /// SF Symbol name rendered above the label. Matched to the design
    /// bundle's icon family: `note.text`, `character.book.closed`
    /// (translate analogue), `sparkles` (AI), `speaker.wave.2`
    /// (audio / read).
    var systemImage: String {
        switch self {
        case .note:      return "note.text"
        case .translate: return "character.book.closed"
        case .askAI:     return "sparkles"
        case .read:      return "speaker.wave.2"
        }
    }

    /// Whether the row uses the theme's `accentColor` as its
    /// background/foreground. Design renders Ask AI as the only
    /// accented action (`primary: true` in the JSX).
    var isAccent: Bool {
        self == .askAI
    }

    /// Stable accessibility identifier for XCUITest + verify-cron
    /// snapshots. Do not rename without updating every harness.
    var accessibilityIdentifier: String {
        switch self {
        case .note:      return "selectionPopoverNote"
        case .translate: return "selectionPopoverTranslate"
        case .askAI:     return "selectionPopoverAskAI"
        case .read:      return "selectionPopoverRead"
        }
    }
}
