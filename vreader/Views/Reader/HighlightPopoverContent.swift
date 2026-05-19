// Purpose: Feature #64 WI-1 — `HighlightPopoverContent`, the value type the
// unified cross-format highlight-action popover renders.
//
// Derived from the tapped `HighlightRecord` by `HighlightPopoverPresenter`
// (WI-2). A value type so it drives a SwiftUI presentation without holding
// the SwiftData `@Model` across the actor boundary — mirrors how
// `HighlightRecord` itself decouples reader UI from `Highlight`.
//
// Supersedes feature #55's `NotePreviewContent` (deleted in WI-10). Adds two
// fields over `NotePreviewContent`:
// - `chapter` — an optional chapter/location string for the meta row; `nil`
//   for formats without a chapter context.
// - `anchor` — the tapped highlight's `AnnotationAnchor`, carried so the
//   Foliate (AZW3/MOBI) recolor/delete path can recover the CFI without a
//   second persistence lookup.
//
// Key decisions:
// - `note: String?` — `nil` OR an all-whitespace string both mean the
//   empty/no-note state. `isEmpty` trims so a color-only highlight and a
//   note cleared to "   " render the same designed empty state.
// - `sourceRect` carries the tap anchor (view-local, from
//   `ReaderHighlightTapEvent`). `.zero` means "no anchor" (the Foliate path)
//   — `HighlightPopoverPresenter.form` reads it to fall back to the sheet.
// - `Sendable` — `CGRect`/`UUID`/`Date`/`String`/`AnnotationAnchor` are all
//   `Sendable`, so the struct crosses concurrency boundaries cleanly.
//
// @coordinates-with: HighlightPopoverPresenter.swift,
//   HighlightPopoverViewModel.swift, HighlightRecord.swift,
//   AnnotationAnchor.swift, ReaderNotifications.swift (ReaderHighlightTapEvent)

import Foundation
import CoreGraphics

/// The data the unified highlight-action popover renders, derived from a
/// tapped highlight.
struct HighlightPopoverContent: Identifiable, Equatable, Sendable {
    /// Identity — equals the tapped highlight's `highlightId`.
    let id: UUID
    /// The note body. `nil` or all-whitespace ⇒ the empty/no-note state.
    let note: String?
    /// The highlighted passage — rendered as the italic excerpt strip.
    let highlightedText: String
    /// The stored highlight color name (raw `HighlightRecord.color`).
    let colorName: String
    /// Creation date — rendered as part of the "· <date>" meta.
    let createdAt: Date
    /// Optional chapter / location string for the meta row. `nil` for formats
    /// without a chapter context.
    let chapter: String?
    /// Anchor rect for the popover, in the reader content view's coordinate
    /// space. `.zero` ⇒ no anchor available (Foliate) ⇒ sheet fallback.
    let sourceRect: CGRect
    /// The tapped highlight's format-specific anchor, carried so the Foliate
    /// recolor/delete path can recover the CFI. `nil` for legacy highlights.
    let anchor: AnnotationAnchor?

    /// True when there is no note body to show — drives the empty/no-note
    /// state. Trims whitespace so a `nil` note and a `"   "` note are equal.
    var isEmpty: Bool {
        (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
