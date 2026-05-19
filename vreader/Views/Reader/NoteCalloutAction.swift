// Purpose: Feature #55 WI-4 — UI-presentation enum listing the handoff-row
// action buttons in `NoteCalloutView`.
//
// The committed design bundle's `CalloutAction` row
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-note-preview.jsx`)
// depicts three actions — Edit / Share / Open-in-panel. v1 of feature #55
// ships ONLY two:
//   - **Edit** is omitted — the editor surface it opens is not a committed
//     buildable design; per rule 51 it is a `BLOCKED: needs-design` slice
//     (issue #914, plan §2.8). v1 is read-only preview.
//   - **Delete** is NOT added — it was never in the design's `CalloutAction`
//     row; adding it would be self-designed UI (plan §2.7.2, round-2 finding).
//
// Rendering a depicted 3-button row with 2 of its buttons is *narrower* than
// the design, which rule 51 permits — it is not an invented surface.
//
// Distinct from any dispatch enum: this type is the *visual layout* — it pins
// display order, labels, SF symbols, and accessibility identifiers against the
// design bundle. A regression that adds Edit/Delete to v1, reorders, or
// renames an accessibility identifier fails `NoteCalloutViewTests` before any
// SwiftUI render runs.
//
// @coordinates-with: NoteCalloutView.swift, NotePreviewContent.swift

import Foundation

/// A handoff-row action button in the v1 `NoteCalloutView`. Order matches the
/// depicted-and-shipped subset of the design's `CalloutAction` row.
enum NoteCalloutAction: String, CaseIterable, Equatable {
    /// Share the note — wired to the existing reader share path.
    case share
    /// Open the Annotations panel (Highlights tab) — posts `.readerOpenNotes`.
    case openInPanel

    /// The user-facing button label.
    var label: String {
        switch self {
        case .share:       return "Share"
        case .openInPanel: return "Open in panel"
        }
    }

    /// SF Symbol for the button glyph.
    var systemImage: String {
        switch self {
        case .share:       return "square.and.arrow.up"
        case .openInPanel: return "highlighter"
        }
    }

    /// Stable accessibility identifier — used by XCUITest verification.
    var accessibilityIdentifier: String {
        switch self {
        case .share:       return "noteCalloutShare"
        case .openInPanel: return "noteCalloutOpenInPanel"
        }
    }
}
