// Purpose: Payload shape emitted by Feature #60's SelectionPopover
// (WI-3 foundational types). One enum value per user-tappable button
// in the popover: 4 named highlight colors + note + translate +
// askAI + read. Consumed by the WI-7 handler that routes the action
// to the existing highlight/note/translate/AI/TTS pipelines.
//
// Key decisions:
// - Local-dispatch only. Intentionally NOT `Codable` — serialized
//   payloads would invite a persistence schema commitment we don't
//   need for the in-view callback chain, and would force every future
//   action to be bridge-stable. The reader bridge contracts already
//   own their own serialized shapes; SelectionPopoverAction is the
//   UI-level handoff that lives entirely on the main actor.
// - `Equatable` + `Sendable` make the type easy to assert against in
//   tests and safe to carry across `MainActor`-isolated callback
//   boundaries.
// - `.highlight` carries `NamedHighlightColor` so the WI-7 routing
//   handler sees the chosen color directly without re-decoding.
//
// @coordinates-with: NamedHighlightColor.swift, SelectionPopover view
//   (WI-4), tap-action router (WI-7)

import Foundation

enum SelectionPopoverAction: Equatable, Sendable {
    case highlight(NamedHighlightColor)
    case note
    case translate
    case askAI
    case read
}
