package com.vreader.app.reader

import com.vreader.app.reader.paged.TxtPageIndex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * feature #137 WI-9 — the pure TTS-follow decision for paged mode: given the currently-spoken SOURCE
 * offset, the pager's current page, and the published page index, decide which page (if any) the pager
 * should auto-advance to so the spoken sentence stays visible. The follow fires when the NARRATION's page
 * differs from the shown page (the target is the SPOKEN page, whichever direction the narration moved),
 * and never before the index publishes (null index / no follow). It does NOT itself distinguish a user
 * swipe from narration progress — the HOST effect achieves "don't fight the user's swipe" by keying ONLY
 * on the narration signal (tts.phase + tts.charStart), NOT on the page offset, so a user swipe (which
 * changes the page, not charStart) never re-invokes this helper; the follow re-tracks only when the
 * narration next advances to a new sentence.
 *
 * This mirrors the scroll body's `isSourceChunkInViewport`-then-`animateScrollToItem` guard, at page
 * granularity via `TxtPageIndex.pageContaining`. Pure / JVM-testable; the connected test drives the same
 * helper through the live effect + a simulated spoken offset.
 */
class PagedTtsFollowTest {

    /** A 5-page index: pages start at 0, 100, 200, 300, 400; doc end 500 (each page ~100 chars). */
    private fun index() = TxtPageIndex(intArrayOf(0, 100, 200, 300, 400), docEndExclusive = 500)

    @Test fun noIndex_returnsNull() {
        assertNull("no follow before phase-1 publishes an index", pagedTtsFollowTarget(spokenOffset = 250, currentPage = 0, index = null))
    }

    @Test fun negativeSpokenOffset_returnsNull() {
        // A negative offset is never a real position (the caller gates on tts.phase==speaking, so the
        // helper only rejects negatives — offset 0 is the valid first-sentence position, covered below).
        assertNull("negative spoken offset does not follow", pagedTtsFollowTarget(spokenOffset = -1, currentPage = 2, index = index()))
    }

    @Test fun zeroOffsetOnFirstSentence_followsBackToPageZero() {
        // Offset 0 IS a real position (the first sentence). If the pager is not on page 0, the narration
        // starting/rewinding to the top follows back to page 0 (Gate-4 R1 Low — 0 is not "idle").
        assertEquals(0, pagedTtsFollowTarget(spokenOffset = 0, currentPage = 3, index = index()))
        // Already on page 0 → no redundant jump.
        assertNull(pagedTtsFollowTarget(spokenOffset = 0, currentPage = 0, index = index()))
    }

    @Test fun spokenOnCurrentPage_returnsNull_noRedundantJump() {
        // The narration is on the page already shown → no jump (never re-jump a page the narration is on).
        assertNull("spoken text on the current page → no follow", pagedTtsFollowTarget(spokenOffset = 150, currentPage = 1, index = index()))
    }

    @Test fun spokenAheadOfCurrentPage_advances() {
        // Narration moved onto page 2 (offset 250) while the pager shows page 0 → advance to page 2.
        assertEquals(2, pagedTtsFollowTarget(spokenOffset = 250, currentPage = 0, index = index()))
    }

    @Test fun narrationRewound_movesBackToTheSpokenPage() {
        // The narration itself rewound (previous()/seek) to page 1 while the pager shows page 4 → the
        // follow lands on the SPOKEN page (page 1). This is narration-driven, NOT a user-swipe reaction:
        // the host effect only re-invokes this on a charStart change (a real narration move), so a user
        // swipe to page 4 while the narration is on page 1 does NOT re-fire and does NOT yank back.
        assertEquals(1, pagedTtsFollowTarget(spokenOffset = 120, currentPage = 4, index = index()))
    }

    @Test fun spokenAtPageBoundaryStart_landsOnThatPage() {
        // Exactly at page 3's start (offset 300) → page 3 (pageContaining is start-inclusive).
        assertEquals(3, pagedTtsFollowTarget(spokenOffset = 300, currentPage = 0, index = index()))
    }

    @Test fun spokenPastDocEnd_clampsToLastPage() {
        assertEquals(4, pagedTtsFollowTarget(spokenOffset = 9_999, currentPage = 0, index = index()))
    }

    @Test fun emptyIndex_returnsNull() {
        // A degenerate/empty index has no pages → nothing to follow to.
        assertNull(pagedTtsFollowTarget(spokenOffset = 10, currentPage = 0, index = TxtPageIndex.degenerate()))
    }
}
