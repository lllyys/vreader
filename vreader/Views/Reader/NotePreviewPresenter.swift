// Purpose: Feature #55 WI-1 — `NotePreviewPresenter`, the pure parse/build +
// callout-vs-sheet decision boundary for the tap-on-annotated-text note
// preview, and `NotePreviewForm`, the two presentation forms.
//
// `NotePreviewPresenter` is a stateless enum (a namespace of pure `static`
// functions) so the mapping and the form decision are unit-testable with no
// UIKit / SwiftUI / persistence dependency. The stateful presentation
// machinery (`NotePreviewModifier`, `UIKitNotePreviewPresenter`) is added in
// WI-5 and lives alongside this type.
//
// Key decisions:
// - `content(for:sourceRect:)` is the single place a `HighlightRecord`
//   becomes a `NotePreviewContent` — keeps the field mapping in one tested
//   spot rather than scattered across the per-format containers.
// - `form(...)` is a pure decision table: VoiceOver running, OR a long note
//   (more lines than `calloutMaxLines`), OR a zero `sourceRect` (Foliate, no
//   anchor) → `.sheet`; otherwise the anchored `.callout`. Pure so the
//   decision is exhaustively unit-tested (plan §5, R-3).
//
// @coordinates-with: NotePreviewContent.swift, NotePreviewViewModel.swift,
//   HighlightRecord.swift

import Foundation
import CoreGraphics

/// The two forms a note preview can take.
enum NotePreviewForm: Equatable, Sendable {
    /// An anchored card with a pointer notch, floating by the tapped passage.
    case callout
    /// A bottom-anchored short sheet — used for long notes, the VoiceOver
    /// path, and Foliate (no `sourceRect` to anchor a callout to).
    case sheet
}

/// Pure parse/build + form-decision boundary for the note preview.
enum NotePreviewPresenter {

    /// The note line count at or below which the anchored callout is still
    /// used. Past this, the note is long enough to want the roomier sheet.
    /// Matches the design note ("> ~6 lines" → sheet fallback).
    static let calloutMaxLines = 6

    /// Builds the preview content for a tapped highlight. Pure — the single
    /// `HighlightRecord` → `NotePreviewContent` mapping point.
    static func content(for record: HighlightRecord, sourceRect: CGRect) -> NotePreviewContent {
        NotePreviewContent(
            id: record.highlightId,
            note: record.note,
            highlightedText: record.selectedText,
            colorName: record.color,
            createdAt: record.createdAt,
            sourceRect: sourceRect
        )
    }

    /// Pure decision: anchored callout vs bottom sheet. The sheet is chosen
    /// when VoiceOver is running, when the note is longer than
    /// `calloutMaxLines`, or when there is no anchor rect (`sourceRect ==
    /// .zero`, the Foliate path). Otherwise the anchored callout.
    static func form(
        for content: NotePreviewContent,
        isVoiceOverRunning: Bool,
        noteLineCount: Int
    ) -> NotePreviewForm {
        if isVoiceOverRunning { return .sheet }
        if content.sourceRect == .zero { return .sheet }
        if noteLineCount > calloutMaxLines { return .sheet }
        return .callout
    }
}
