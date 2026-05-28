// Purpose: Pure value type modeling the contiguous range of EPUB spine
// items (chapters) currently materialized in the continuous-scroll
// WKWebView document (feature #71 — EPUB scroll-mode continuous
// cross-chapter scroll, WI-1).
//
// Background: in scroll mode the EPUB reader stitches a window of adjacent
// chapters into ONE scrollable document and lazily extends / evicts that
// window as the user scrolls (design §2.3: "render current chapter + ±1
// chapter eagerly", with far-end eviction to bound WKWebView memory). This
// type holds the window's bookkeeping as pure integer-range arithmetic so
// the whole materialize / extend / evict policy is unit-testable without a
// WKWebView (the bridge wiring lands in WI-4+).
//
// Key decisions:
// - Non-empty invariant (Gate-2 round-1 finding [L1]): a valid window
//   always satisfies `0 <= lo <= anchor <= hi < spineCount`. A book with
//   `spineCount == 0` therefore has NO window — `initial(anchor:spineCount:)`
//   returns nil and the container guards the empty case. This avoids an
//   ambiguous "empty range" representation that the transition functions
//   would otherwise have to special-case everywhere.
// - `anchor` is the chapter the reader is currently reading; it is the
//   fixed point eviction trims around (the far end from the anchor is
//   trimmed first), so the user's current chapter is never evicted.
// - All transitions are pure (`func` returning a new value), value-type
//   `Equatable` — no shared mutable state, mirroring `EPUBChapterNavigationRouter`
//   and `EPUBProgressCalculator`.
//
// @coordinates-with: EPUBContinuousScrollCoordinator.swift (WI-4 consumer),
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-1)

import Foundation

/// The contiguous range of spine indices materialized in the continuous
/// scroll document, anchored on the chapter the reader is reading.
///
/// Invariant (maintained by every initializer / transition):
/// `0 <= lo <= anchor <= hi < spineCount`.
struct EPUBSpineWindow: Equatable {

    /// Lowest materialized spine index (inclusive).
    private(set) var lo: Int
    /// Highest materialized spine index (inclusive).
    private(set) var hi: Int
    /// The chapter the reader is currently reading. Eviction trims around
    /// this point so it is never dropped from the window.
    private(set) var anchor: Int

    /// Total spine items in the book. Kept so the transitions can clamp at
    /// the book edges without the caller re-passing it each time. Exposed
    /// (WI-8) so the coordinator can rebuild a fresh window around an
    /// out-of-window navigation target without re-threading the count.
    private(set) var spineCount: Int

    private init(lo: Int, hi: Int, anchor: Int, spineCount: Int) {
        self.lo = lo
        self.hi = hi
        self.anchor = anchor
        self.spineCount = spineCount
    }

    /// Builds the initial single-chapter window anchored on `anchor`.
    ///
    /// - Returns: `nil` when `spineCount <= 0` (an empty book has no
    ///   window). Otherwise a `lo == hi == anchor` window with `anchor`
    ///   clamped into `0..<spineCount`.
    static func initial(anchor: Int, spineCount: Int) -> EPUBSpineWindow? {
        guard spineCount > 0 else { return nil }
        let clampedAnchor = min(max(anchor, 0), spineCount - 1)
        return EPUBSpineWindow(
            lo: clampedAnchor,
            hi: clampedAnchor,
            anchor: clampedAnchor,
            spineCount: spineCount
        )
    }

    /// Whether the window can grow toward the end of the book.
    /// Number of materialized chapters in the window (`hi - lo + 1`, always ≥ 1).
    var span: Int { hi - lo + 1 }

    var canExtendForward: Bool { hi < spineCount - 1 }

    /// Whether the window can grow toward the start of the book.
    var canExtendBackward: Bool { lo > 0 }

    /// Whether the given spine index is currently materialized.
    func contains(_ index: Int) -> Bool { index >= lo && index <= hi }

    /// Grows the window forward by one chapter, or returns `self` unchanged
    /// when already at the last chapter.
    func extendForward() -> EPUBSpineWindow {
        guard canExtendForward else { return self }
        return EPUBSpineWindow(lo: lo, hi: hi + 1, anchor: anchor, spineCount: spineCount)
    }

    /// Grows the window backward by one chapter, or returns `self` unchanged
    /// when already at the first chapter.
    func extendBackward() -> EPUBSpineWindow {
        guard canExtendBackward else { return self }
        return EPUBSpineWindow(lo: lo - 1, hi: hi, anchor: anchor, spineCount: spineCount)
    }

    /// Trims the window down to at most `maxSpan` chapters, removing whole
    /// chapters from the end farther from the `anchor` first so the
    /// reader's current chapter is always retained.
    ///
    /// - Parameter maxSpan: the maximum number of chapters to keep
    ///   materialized (clamped to ≥ 1 — a window always keeps the anchor).
    func evictFarFromAnchor(maxSpan: Int) -> EPUBSpineWindow {
        let cap = max(maxSpan, 1)
        var newLo = lo
        var newHi = hi
        while (newHi - newLo + 1) > cap {
            // The window still spans more than one chapter (`cap >= 1` and
            // the guard holds), so at least one side is strictly past the
            // anchor and can be trimmed without dropping it. Trim the side
            // farther from the anchor first; ties trim `hi` (so a symmetric
            // window shrinks toward the start). Exactly one branch makes
            // progress each iteration → the loop always terminates.
            let distanceToLo = anchor - newLo
            let distanceToHi = newHi - anchor
            if newHi > anchor, distanceToHi >= distanceToLo || newLo >= anchor {
                newHi -= 1
            } else {
                // `newLo < anchor` here: the only remaining trimmable side.
                newLo += 1
            }
        }
        return EPUBSpineWindow(lo: newLo, hi: newHi, anchor: anchor, spineCount: spineCount)
    }

    /// Returns a window with the anchor moved to `newAnchor`, clamped into the
    /// current materialized `[lo, hi]` span. The materialized RANGE is unchanged
    /// — only which chapter `evictFarFromAnchor` treats as "keep" moves. Feature
    /// #71 WI-4: the continuous-scroll coordinator re-anchors to the reading
    /// chapter as the user scrolls so eviction trims chapters BEHIND the reader
    /// (far from the current position), not the one being read. Pure; re-anchor
    /// does not touch the DOM (no `lo`/`hi` change), so the coordinator may apply
    /// it without a JS eval.
    func reanchored(to newAnchor: Int) -> EPUBSpineWindow {
        let clamped = min(max(newAnchor, lo), hi)
        guard clamped != anchor else { return self }
        return EPUBSpineWindow(lo: lo, hi: hi, anchor: clamped, spineCount: spineCount)
    }
}
