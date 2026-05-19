// Purpose: Feature #64 WI-1 — `HighlightPopoverAction`, the single enum the
// unified highlight-action popover view emits. One value per user-tappable
// affordance in the popover. Consumed by `HighlightPopoverModifier` (WI-4),
// which routes each action to the highlight-mutation / clipboard / share /
// delete pipelines.
//
// Mirrors feature #60's `SelectionPopoverAction` — a single-enum action
// surface in place of a fragmented N-closure surface (the superseded #64
// plan's round-1 audit, finding F9, flagged a 10-closure surface as too
// fragmented; this enum is the corrected design).
//
// Key decisions:
// - Local-dispatch only. Intentionally NOT `Codable` — the popover's
//   action chain lives entirely on the main actor; serializing it would
//   invite a persistence/bridge schema commitment we don't need.
// - `Equatable` + `Sendable` make the type easy to assert against in tests
//   and safe to carry across `MainActor`-isolated callback boundaries.
// - `.changeColor` carries `NamedHighlightColor` so the routing handler sees
//   the chosen color directly without re-decoding the raw storage string.
// - `requestDelete` and `confirmDelete` are distinct: `requestDelete` enters
//   the `confirmingDelete` mode (showing the inline confirm sub-state),
//   `confirmDelete` is the user's confirmation that actually deletes.
//
// @coordinates-with: NamedHighlightColor.swift, HighlightActionCardView.swift,
//   HighlightPopoverModifier.swift

import Foundation

/// The action the unified highlight-action popover view emits — one value per
/// user-tappable affordance.
enum HighlightPopoverAction: Equatable, Sendable {
    /// User tapped one of the 4 color circles.
    case changeColor(NamedHighlightColor)
    /// User tapped the note region (or the "Add a note…" CTA) — enter editing.
    case beginEdit
    /// User tapped Save in the inline editor — persist the given draft.
    case saveNote(String)
    /// User tapped Cancel in the inline editor — discard the draft, return to
    /// the reading mode.
    case cancelEdit
    /// User tapped Copy — copy the excerpt to the pasteboard.
    case copy
    /// User tapped Share — open the system share sheet.
    case share
    /// User tapped Delete — enter the `confirmingDelete` sub-state.
    case requestDelete
    /// User confirmed deletion in the confirm sub-state — actually delete.
    case confirmDelete
}
