// Purpose: Feature #64 WI-2 — `HighlightPopoverPresenter`, the pure
// parse/build + anchored-card-vs-bottom-sheet decision boundary for the
// unified cross-format highlight-action popover.
//
// A stateless enum (a namespace of pure `static` functions) so the mapping
// and the form decision are unit-testable with no UIKit / SwiftUI /
// persistence dependency. The stateful presentation machinery
// (`HighlightPopoverModifier`, `UIKitHighlightPopoverPresenter`) is added in
// WI-4 / WI-5 and lives alongside this type.
//
// The callout-vs-sheet decision table was lifted verbatim from feature #55's
// `NotePreviewPresenter` when this type was introduced; a parity test fenced
// the equivalence through the WI-6..9 migration. Feature #64 WI-10 deleted
// `NotePreviewPresenter` (and the parity test with it) — this is now the
// single presenter.
//
// Key decisions:
// - `content(for:sourceRect:chapter:)` is the single place a
//   `HighlightRecord` becomes a `HighlightPopoverContent` — keeps the field
//   mapping in one tested spot rather than scattered across the per-format
//   containers. `HighlightPopoverViewModel` delegates its mapping here.
// - `form(...)` is a pure decision table: VoiceOver running, OR a long note
//   (more lines than `cardMaxNoteLines`), OR a zero `sourceRect` (Foliate,
//   no anchor) → `.sheet`; otherwise the anchored `.card`.
// - `resolvedForm(...)` folds in the one runtime fact `form(...)` cannot
//   know — whether a host `UIView` is available to anchor a card.
//
// @coordinates-with: HighlightPopoverContent.swift,
//   HighlightPopoverMode.swift (HighlightPopoverForm),
//   HighlightPopoverViewModel.swift, HighlightRecord.swift

import Foundation
import CoreGraphics

/// Pure parse/build + form-decision boundary for the unified
/// highlight-action popover.
enum HighlightPopoverPresenter {

    /// The note line count at or below which the anchored card is still
    /// used. Past this, the note is long enough to want the roomier sheet.
    /// Matches the design note ("> ~6 lines" → sheet fallback).
    static let cardMaxNoteLines = 6

    /// Builds the popover content for a tapped highlight. Pure — the single
    /// `HighlightRecord` → `HighlightPopoverContent` mapping point.
    /// `chapter` is the optional chapter / location string for the meta row,
    /// supplied by the per-format container.
    static func content(
        for record: HighlightRecord,
        sourceRect: CGRect,
        chapter: String?
    ) -> HighlightPopoverContent {
        HighlightPopoverContent(
            id: record.highlightId,
            note: record.note,
            highlightedText: record.selectedText,
            colorName: record.color,
            createdAt: record.createdAt,
            chapter: chapter,
            sourceRect: sourceRect,
            anchor: record.anchor
        )
    }

    /// Pure decision: anchored card vs bottom sheet. The sheet is chosen
    /// when VoiceOver is running, when the note is longer than
    /// `cardMaxNoteLines`, or when there is no anchor rect (`sourceRect ==
    /// .zero`, the Foliate path). Otherwise the anchored card.
    static func form(
        for content: HighlightPopoverContent,
        isVoiceOverRunning: Bool,
        noteLineCount: Int
    ) -> HighlightPopoverForm {
        if isVoiceOverRunning { return .sheet }
        if content.sourceRect == .zero { return .sheet }
        if noteLineCount > cardMaxNoteLines { return .sheet }
        return .card
    }

    /// The form to actually present, folding in one runtime fact `form(...)`
    /// cannot know: whether a host `UIView` is available to anchor a card.
    /// `form(...)` may choose `.card`, but if `hasHostView` is `false` (the
    /// container's content view is not yet attached, or the container passes
    /// no host provider) the card has nowhere to anchor — so it degrades to
    /// `.sheet`. Pure, so the host-fallback path is unit-tested without a
    /// SwiftUI render.
    static func resolvedForm(
        for content: HighlightPopoverContent,
        isVoiceOverRunning: Bool,
        noteLineCount: Int,
        hasHostView: Bool
    ) -> HighlightPopoverForm {
        let base = form(
            for: content,
            isVoiceOverRunning: isVoiceOverRunning,
            noteLineCount: noteLineCount
        )
        if base == .card && !hasHostView { return .sheet }
        return base
    }
}
