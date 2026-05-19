// Bug #154 / GH #443 — regression guard for the search-nav highlight nonce.
//
// The bug: a search-tap to a location the reader is ALREADY at re-sets
// `uiState.highlightRange` to a value it already holds. `@Observable` treats
// that as a no-op write, so the SwiftUI body never re-evaluates and the
// bridge's `updateUIView` never runs — the temporary yellow highlight is
// never re-painted. Even if the body DID re-evaluate, a repeat-nav within the
// 3 s auto-clear window finds the bridge coordinator's `currentHighlightRange`
// still equal to the incoming range, so the range-diff alone reports "no
// change" and the 3 s timer is never re-armed from the second tap.
//
// The fix: `TextReaderUIState.highlightNonce` is bumped on every navigate
// event. The bridge folds a nonce change into its highlight-change detection
// (`TXTTextViewBridge.highlightShouldReapply`) so a repeat-nav re-applies the
// highlight and re-arms the auto-clear timer even when the NSRange is byte-for
// -byte identical.

import Testing
import Foundation
@testable import vreader

@Suite("TXT Bridge Highlight Nonce (Bug #154 / GH #443)")
struct TXTBridgeHighlightNonceTests {

    /// A genuine range change re-applies regardless of the nonce.
    @Test func reappliesWhenRangeChanged() {
        #expect(
            TXTTextViewBridge.highlightShouldReapply(rangeChanged: true, nonceChanged: false)
        )
    }

    /// THE BUG #154 CASE. The range is byte-for-byte identical (repeat-nav to
    /// an already-current target) — yet a nonce change MUST still trigger a
    /// re-apply so the temporary highlight re-paints and the 3 s auto-clear
    /// timer re-arms from this navigate event.
    @Test func reappliesWhenOnlyNonceChanged() {
        #expect(
            TXTTextViewBridge.highlightShouldReapply(rangeChanged: false, nonceChanged: true),
            "a repeat-nav to the same target changes only the nonce, not the range — the bridge must still re-apply the highlight (bug #154 / GH #443)"
        )
    }

    /// Neither the range nor the nonce changed — a config/font-only
    /// `updateUIView` pass. No re-apply, so the timer is left alone and the
    /// already-painted highlight is not disturbed.
    @Test func doesNotReapplyWhenNothingChanged() {
        #expect(
            !TXTTextViewBridge.highlightShouldReapply(rangeChanged: false, nonceChanged: false)
        )
    }

    /// Both changed — re-apply (range change subsumes the nonce change).
    @Test func reappliesWhenBothChanged() {
        #expect(
            TXTTextViewBridge.highlightShouldReapply(rangeChanged: true, nonceChanged: true)
        )
    }
}
