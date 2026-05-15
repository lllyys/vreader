// Purpose: UI-domain enum naming the four highlight colors offered in
// Feature #60's SelectionPopover (WI-3 foundational types). Strictly
// additive over the existing raw-`String` `Highlight.color` schema —
// storage continues to be raw `String` per `Highlight.swift`,
// `HighlightRecord.swift`, backup DTOs, and ExportedAnnotation. This
// type is the *display/picker* domain. Hex stops are pinned to the
// committed design bundle (`dev-docs/designs/vreader-fidelity-v1/`).
//
// Key decisions:
// - `rawValue` is the semantic name ("yellow"/"pink"/"green"/"blue")
//   so `Codable` round-trips emit a stable string and Swift-driven
//   filtering by name reads naturally. Hex is derived, not stored.
// - `from(storageString:)` returns `nil` for any unknown input — no
//   silent coercion to `.yellow`. The caller decides the fallback.
//   This pin protects the storage boundary: a legacy hex value or a
//   user-defined custom color from a future feature MUST remain
//   recognizable as "not in this picker" so callers can branch.
// - Sendable + Codable + CaseIterable conformances are explicit so
//   adding a non-Sendable associated value later breaks the build.
//
// @coordinates-with: SelectionPopoverAction.swift, Highlight.swift
//   (storage boundary), HighlightRecord.swift, BackupSectionDTOs.swift,
//   ExportedAnnotation.swift

import Foundation

enum NamedHighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case pink
    case green
    case blue

    /// Hex stops pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx`
    /// `SelectionPopover` `colorMap`. Drift here breaks the visual
    /// contract against the committed design.
    var hex: String {
        switch self {
        case .yellow: return "#f0d25a"
        case .pink:   return "#e88ca0"
        case .green:  return "#8cc88c"
        case .blue:   return "#8cb4e8"
        }
    }

    /// Best-effort decoder from the raw storage string used by
    /// `Highlight.color`. Case-sensitive and no whitespace trimming —
    /// the storage schema has always been the lowercased semantic name
    /// (default `"yellow"`), so tolerating drift here would hide bugs.
    /// Returns `nil` for any value not in the named picker (legacy hex,
    /// empty string, future user-defined colors). The caller decides
    /// whether to fall back to a default or surface the raw value.
    static func from(storageString: String) -> NamedHighlightColor? {
        NamedHighlightColor(rawValue: storageString)
    }
}
