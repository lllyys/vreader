// Bug #296 / GH #1304 — regression coverage for the annotations-row swipe
// decision seam extracted out of `NotesDeleteRow`.
//
// The bug was an arbitration defect (`.highPriorityGesture` starved the
// ScrollView pan); the structural fix is the gesture-modifier swap, which is
// not unit-observable. What IS unit-testable — and what this suite pins — is
// the pure decision the drag's `.onEnded` makes: a swipe only ever reveals or
// dismisses on a HORIZONTAL-dominant drag past the threshold, so a vertical
// scroll drag resolves to `.none` and never hijacks the row.

import Testing
import CoreGraphics
@testable import vreader

@Suite("NotesSwipeResolver")
struct NotesSwipeResolverTests {
    private let drawerWidth: CGFloat = 128  // matches NotesDeleteRow.drawerWidth

    // MARK: - Reveal

    @Test func leftDragBeyondThreshold_whenClosed_reveals() {
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: -(drawerWidth / 3) - 1, translationHeight: 2,
            isSwipeRevealed: false, drawerWidth: drawerWidth)
        #expect(outcome == .reveal)
    }

    @Test func leftDragBelowThreshold_whenClosed_isNone() {
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: -(drawerWidth / 3) + 1, translationHeight: 2,
            isSwipeRevealed: false, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    @Test func leftDragBeyondThreshold_whenAlreadyRevealed_isNone() {
        // Already open: another left drag should not re-reveal.
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: -(drawerWidth / 3) - 30, translationHeight: 1,
            isSwipeRevealed: true, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    // MARK: - Dismiss

    @Test func rightDragBeyondThreshold_whenRevealed_dismisses() {
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: (drawerWidth / 3) + 1, translationHeight: 2,
            isSwipeRevealed: true, drawerWidth: drawerWidth)
        #expect(outcome == .dismiss)
    }

    @Test func rightDragBeyondThreshold_whenClosed_isNone() {
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: (drawerWidth / 3) + 50, translationHeight: 2,
            isSwipeRevealed: false, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    // MARK: - Vertical-dominant (the scroll-starvation guard)

    @Test func verticalDominantDrag_isAlwaysNone() {
        // A vertical scroll: large downward height, tiny horizontal jitter.
        // Even with a leftward width past the threshold, height dominates →
        // the row must NOT treat it as a swipe (so the ScrollView keeps it).
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: -(drawerWidth / 3) - 5, translationHeight: 300,
            isSwipeRevealed: false, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    @Test func verticalDominantDrag_whenRevealed_doesNotDismiss() {
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: (drawerWidth / 3) + 5, translationHeight: -300,
            isSwipeRevealed: true, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    // MARK: - Boundaries

    @Test func exactNegativeThreshold_isNone() {
        // Strictly-less-than threshold → boundary itself does not reveal.
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: -(drawerWidth / 3), translationHeight: 0,
            isSwipeRevealed: false, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    @Test func exactPositiveThreshold_whenRevealed_isNone() {
        // Symmetric to the negative boundary: dismiss uses strict `>`, so the
        // exact positive threshold does not dismiss.
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: drawerWidth / 3, translationHeight: 0,
            isSwipeRevealed: true, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    @Test func zeroTranslation_isNone() {
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: 0, translationHeight: 0,
            isSwipeRevealed: false, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }

    @Test func equalMagnitude_notHorizontalDominant_isNone() {
        // |width| == |height| is NOT horizontal-dominant (strict >).
        let outcome = NotesSwipeResolver.outcome(
            translationWidth: -60, translationHeight: 60,
            isSwipeRevealed: false, drawerWidth: drawerWidth)
        #expect(outcome == .none)
    }
}
