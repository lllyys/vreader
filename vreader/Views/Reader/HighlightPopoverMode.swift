// Purpose: Feature #64 WI-1 — the unified highlight-action popover's
// interaction-mode enum, presentation-form enum, and mutation-outcome enum.
//
// `HighlightPopoverMode`    — the card's interaction sub-state.
// `HighlightPopoverForm`    — anchored card vs bottom sheet (the two
//                             presentation realizations in the committed
//                             design `vreader-highlight-popover.jsx`).
// `HighlightMutationOutcome` — the typed result of a popover-initiated
//                             persistence mutation, so the presenter can
//                             distinguish "record deleted between tap and
//                             save → dismiss" from "generic save failure →
//                             keep the popover open, no local mutation".
//                             A bare `Bool` cannot make that distinction;
//                             `PersistenceActor` throws a distinct
//                             `PersistenceError.recordNotFound`.
//
// Key decisions:
// - All three are simple value enums — `Equatable` + `Sendable` so they cross
//   `MainActor` callback boundaries and are trivially assertable in tests.
// - `HighlightMutationOutcome.success` carries the mutated `HighlightRecord`
//   so the presenter rebuilds the card's local state (new color in the
//   swatch/ring/excerpt-bar; a saved note flips editing→reading) without a
//   re-fetch.
//
// @coordinates-with: HighlightCoordinator.swift, HighlightPopoverModifier.swift,
//   HighlightActionCardView.swift, HighlightRecord.swift

import Foundation

/// The unified highlight-action popover card's interaction mode.
enum HighlightPopoverMode: Equatable, Sendable {
    /// Default — the note region shows the note body (or the empty CTA), the
    /// action row shows Copy / Share / Delete.
    case reading
    /// The inline note editor is open — a textarea + Cancel / Save.
    case editing
    /// The delete-confirmation sub-state — the action row is replaced by an
    /// inline Cancel / Confirm-delete pair.
    case confirmingDelete
}

/// The popover's presentation realization. Both are depicted in the committed
/// design: an anchored card with a pointer notch, and a bottom sheet.
enum HighlightPopoverForm: Equatable, Sendable {
    /// The anchored `HighlightActionCard` — pinned to the tapped passage.
    case card
    /// The bottom `HighlightActionSheet` — used for VoiceOver, long notes,
    /// and the no-anchor Foliate path.
    case sheet
}

/// Result of a popover-initiated highlight mutation (recolor / note edit).
/// Lets the presenter distinguish "record gone → dismiss" from
/// "save failed → stay open, no local mutation".
enum HighlightMutationOutcome: Equatable, Sendable {
    /// The mutation persisted. Carries the mutated record so the presenter
    /// rebuilds the card's local state without a re-fetch.
    case success(HighlightRecord)
    /// The highlight was deleted between the tap and the save (a concurrent-
    /// deletion race). The popover dismisses — there is nothing to act on.
    case notFound
    /// A generic persistence error. The popover stays open, no local
    /// mutation; the user can retry.
    case failed
}
