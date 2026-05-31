// Purpose: Shared protocol for format-specific highlight rendering (Phase R4a).
// Each format (TXT/MD, EPUB, PDF) implements this to apply/remove/restore highlights
// through its native rendering mechanism.
//
// Key decisions:
// - Protocol is @MainActor because all visual operations must happen on the main thread.
// - AnyObject constraint allows reference semantics (renderers hold mutable state).
// - Three operations cover the full highlight lifecycle:
//   apply = newly created, remove = deleted from panel, restore = bulk load on open.
//
// @coordinates-with: TextHighlightRenderer.swift, EPUBHighlightRenderer.swift,
//   PDFHighlightRenderer.swift, HighlightCoordinator.swift

import Foundation

/// Format-agnostic contract for visual highlight operations.
///
/// Each format adapter translates these calls into its native mechanism:
/// - TXT/MD: NSRange mutation on TextReaderUIState
/// - EPUB: CSS Highlight API JS injection
/// - PDF: PDFAnnotation creation/removal
@MainActor
protocol HighlightRenderer: AnyObject {
    /// Visually apply a newly created or persisted highlight.
    func apply(record: HighlightRecord)

    /// Visually remove a highlight by its ID (e.g., deletion from annotations panel).
    func remove(id: UUID)

    /// Restore all saved highlights (e.g., on file/page open).
    ///
    /// `forHref` carries the chapter context as an immutable input —
    /// EPUB renderer needs it to filter records to the page being
    /// restored. Threading it through the call (instead of reading
    /// shared mutable state on the renderer) keeps two concurrent
    /// restores for different chapters from cross-wiring (bug #103
    /// follow-up). Pass `nil` for renderers that don't filter by
    /// chapter (TXT, PDF).
    ///
    /// Optional `using` evaluator routes the produced JS to a specific
    /// destination (e.g., the page-ready WKWebView's evaluateJavaScript)
    /// without mutating the renderer's persistent `onInjectJS` callback —
    /// avoids the bug #103 race where a highlight created mid-restore
    /// would have its JS misrouted to the restore-only callback.
    /// Nil falls back to the renderer's normal delivery path.
    func restore(
        records: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    )

    /// Refresh note-presence metadata after a note edit, WITHOUT repainting
    /// the highlight (the note text is never drawn on the page). Bug #295:
    /// only the TXT/MD text renderer keeps a note-presence (`hasNote`) lookup
    /// used to bias ambiguous taps toward the noted highlight, so only it
    /// overrides this. The default is a no-op — calling the visual `restore`
    /// here would, on PDF, duplicate annotations (PDF restore appends).
    func refreshNoteMetadata(records: [HighlightRecord])
}

extension HighlightRenderer {
    /// Convenience: existing call sites that don't need explicit routing
    /// (e.g., `handleRemoval`'s re-render) keep working unchanged. The
    /// renderer's mutable `currentHref` (where applicable) is consulted
    /// in this path.
    func restore(records: [HighlightRecord]) {
        restore(records: records, forHref: nil, using: nil)
    }

    /// Default: no metadata-only lookup to refresh (EPUB/PDF/Foliate). Text
    /// renderers override this.
    func refreshNoteMetadata(records: [HighlightRecord]) {}
}

/// A `HighlightRenderer` whose restore is scoped to a current chapter href.
///
/// Feature #64 WI-3: only the EPUB renderer filters highlights by chapter on
/// restore. `HighlightCoordinator.changeColor` captures the chapter context
/// through this protocol — not via a concrete `EPUBHighlightRenderer` cast —
/// so the href-capture race fix (R1-4) is testable with a fake conformer
/// instead of the real WKWebView-bound renderer.
@MainActor
protocol ChapterScopedHighlightRenderer: HighlightRenderer {
    /// The href of the chapter currently rendered. `changeColor` reads this
    /// BEFORE its persistence `await` so a racing chapter-nav cannot redirect
    /// the post-mutation repaint to the wrong chapter.
    var currentChapterHref: String? { get }
}
