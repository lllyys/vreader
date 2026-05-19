// Purpose: Shared `Color(hexString:)` for the reader's design-bundle-driven
// views.
//
// The committed design bundles specify surface colors as `#RRGGBB` hex
// literals. `SelectionPopoverView`, `NoteCalloutView`, and
// `NotePreviewSheetView` each independently parsed those into `Color`. Per the
// codebase convention ("lift to a shared helper when a third call site
// appears" — the comment in `NoteCalloutView`), the third call site (WI-5's
// `NotePreviewSheetView`) crosses that threshold, so the parser lives here
// once.
//
// @coordinates-with: SelectionPopoverView.swift, NoteCalloutView.swift,
//   NotePreviewSheetView.swift

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
