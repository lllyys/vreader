// Purpose: Bug #296 / GH #1304 — the pure swipe-decision seam for
// `NotesDeleteRow`. Extracted so the reveal/dismiss/none decision is
// unit-testable independently of SwiftUI gesture arbitration.
//
// The row's custom left-swipe drawer is a `DragGesture` (SwiftUI
// `.swipeActions` needs a `List`, which the design rejects). The decision of
// what a finished drag means lives here: a swipe only reveals or dismisses on
// a HORIZONTAL-dominant drag past a third of the drawer width — a vertical
// drag (a scroll) resolves to `.none`, so the row never claims it.
//
// @coordinates-with: NotesDeleteRow.swift

#if canImport(UIKit)
import CoreGraphics

/// What a finished row drag resolves to.
enum NotesSwipeOutcome {
    case reveal
    case dismiss
    case none
}

enum NotesSwipeResolver {
    /// Resolve a finished drag's translation into a swipe outcome.
    ///
    /// - Only a horizontal-dominant drag (`|width| > |height|`, strict) can
    ///   reveal or dismiss; a vertical-dominant drag (a scroll) is `.none`.
    /// - Reveal requires a leftward drag past `-drawerWidth/3` while closed.
    /// - Dismiss requires a rightward drag past `drawerWidth/3` while open.
    static func outcome(
        translationWidth: CGFloat,
        translationHeight: CGFloat,
        isSwipeRevealed: Bool,
        drawerWidth: CGFloat
    ) -> NotesSwipeOutcome {
        let horizontalDominant = abs(translationWidth) > abs(translationHeight)
        guard horizontalDominant else { return .none }

        let threshold = drawerWidth / 3
        if translationWidth < -threshold, !isSwipeRevealed { return .reveal }
        if translationWidth > threshold, isSwipeRevealed { return .dismiss }
        return .none
    }
}
#endif
