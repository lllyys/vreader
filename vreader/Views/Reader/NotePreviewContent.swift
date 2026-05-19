// Purpose: Feature #55 WI-1 — `NotePreviewContent`, the value type a
// note-preview surface (`NoteCallout` / `NotePreviewSheet`) renders.
//
// Derived from the tapped `HighlightRecord` by `NotePreviewPresenter`. A
// value type so it can drive a SwiftUI presentation without holding the
// SwiftData `@Model` across the actor boundary — mirrors how `HighlightRecord`
// itself decouples reader UI from `Highlight`.
//
// Key decisions:
// - `note: String?` — `nil` OR an all-whitespace string both mean the
//   empty/no-note state. `isEmpty` trims so a color-only highlight (no note)
//   and a note cleared to "   " render the same designed empty state.
// - `sourceRect` carries the tap anchor (view-local, from `ReaderHighlightTapEvent`).
//   `.zero` means "no anchor" (the Foliate path) — `NotePreviewPresenter.form`
//   reads it to fall back to the bottom-sheet form.
// - `Sendable` — `CGRect`/`UUID`/`Date`/`String` are all `Sendable`, so the
//   struct crosses concurrency boundaries cleanly.
//
// @coordinates-with: NotePreviewPresenter.swift, NotePreviewViewModel.swift,
//   HighlightRecord.swift, ReaderNotifications.swift (ReaderHighlightTapEvent)

import Foundation
import CoreGraphics

/// The data a note-preview surface renders, derived from a tapped highlight.
struct NotePreviewContent: Identifiable, Equatable, Sendable {
    /// Identity — equals the tapped highlight's `highlightId`.
    let id: UUID
    /// The note body. `nil` or all-whitespace ⇒ the empty/no-note state.
    let note: String?
    /// The highlighted passage — rendered as the 1-line italic excerpt.
    let highlightedText: String
    /// The stored highlight color name (raw `HighlightRecord.color`).
    let colorName: String
    /// Creation date — rendered as the "· <date>" meta.
    let createdAt: Date
    /// Anchor rect for the callout, in the reader content view's coordinate
    /// space. `.zero` ⇒ no anchor available (Foliate) ⇒ sheet fallback.
    let sourceRect: CGRect

    /// True when there is no note body to show — drives the empty/no-note
    /// state. Trims whitespace so a `nil` note and a `"   "` note are equal.
    var isEmpty: Bool {
        (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
