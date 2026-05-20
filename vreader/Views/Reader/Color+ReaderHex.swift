// Purpose: Shared `Color(readerHexString:)` for the reader's
// design-bundle-driven views.
//
// The committed design bundles specify surface colors as `#RRGGBB` hex
// literals. Multiple reader popover views each independently parsed those
// into `Color`; per the codebase convention ("lift to a shared helper when a
// third call site appears") the parser lives here once. Current callers are
// `SelectionPopoverView` (the feature #60 selection popover) and the
// feature #64 unified highlight-action popover's `HighlightActionCardSubviews`.
// (Feature #64 WI-10: the original feature-#55 callers `NoteCalloutView` /
// `NotePreviewSheetView` were deleted with the rest of the #55 note-preview
// surface.)
//
// @coordinates-with: SelectionPopoverView.swift, HighlightActionCardSubviews.swift

#if canImport(UIKit)
import SwiftUI

extension Color {
    /// Parses a hex string `#RRGGBB` (or `#RRGGBBAA` with alpha) into a
    /// SwiftUI `Color`. Returns `nil` for malformed input — callers decide
    /// their fallback. Tolerates a leading `#` and surrounding whitespace.
    init?(readerHexString hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6 || trimmed.count == 8,
              let value = UInt32(trimmed, radix: 16) else {
            return nil
        }
        let r, g, b, a: UInt32
        if trimmed.count == 6 {
            r = (value >> 16) & 0xff
            g = (value >> 8) & 0xff
            b = value & 0xff
            a = 0xff
        } else {
            r = (value >> 24) & 0xff
            g = (value >> 16) & 0xff
            b = (value >> 8) & 0xff
            a = value & 0xff
        }
        self = Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}
#endif
