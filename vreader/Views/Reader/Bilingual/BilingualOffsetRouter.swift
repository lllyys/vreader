// Purpose: Feature #56 WI-12b — the TXT/MD source↔display offset router.
// Wraps `BilingualDisplaySegmentMap` lookups with helpers tuned for the
// TXT/MD container's call sites (selection / search nav / persisted-
// highlight hit-test / TTS auto-scroll). Pure functions — no I/O, no
// state — so the off-path (identity map) is provably byte-identical to
// today's code (gates the R-TXT-offsets risk in the plan).
//
// Key decisions:
// - **`displayOffset(forSourceOffset:)`** is non-failing: out-of-range
//   inputs clamp per `BilingualDisplaySegmentMap.displayOffset(...)`.
//   This is the right failure mode for scroll-restore: a saved
//   position past the end of the source maps to the end of the
//   display, not nil.
// - **`sourceOffset(forDisplayOffset:)`** is nullable: a tap inside a
//   synthetic translation run has no source position. The TXT/MD
//   selection/highlight call sites already accept "no resolved source
//   position" (drop the event) — the router preserves that semantic
//   instead of clamping to a wrong source index.
// - **`displayRange(forSourceRange:)`** uses the map's source-offset
//   projection for both bounds. An empty source range maps to an empty
//   display range; an out-of-range upper bound clamps via the map's
//   built-in past-end semantics.
// - **`isSynthetic(displayOffset:)`** is the seam selection logic uses
//   to reject a tap on a translation run without walking the whole map.
//
// @coordinates-with: BilingualDisplaySegmentMap.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Foundation

/// Pure source↔display offset router for the TXT/MD container's
/// bilingual offset-routing seam. The identity-map fast path is
/// branchless — `BilingualDisplaySegmentMap.identity(...)`'s single
/// segment is a 1:1 pass-through.
enum BilingualOffsetRouter {

    /// Maps a source UTF-16 offset into the display. Clamps a past-end
    /// source offset to the display length (suitable for scroll
    /// restore — "place the cursor at the end of the rendered text").
    static func displayOffset(forSourceOffset sourceOffset: Int,
                              map: BilingualDisplaySegmentMap) -> Int {
        map.displayOffset(forSourceOffset: sourceOffset)
    }

    /// Maps a display UTF-16 offset back to source. Returns `nil` if
    /// the display offset falls inside a synthetic translation run
    /// (selection-on-translation has no source position, per design
    /// §2.4) or is out of bounds.
    static func sourceOffset(forDisplayOffset displayOffset: Int,
                             map: BilingualDisplaySegmentMap) -> Int? {
        map.sourceOffset(forDisplayOffset: displayOffset)
    }

    /// Maps a half-open source UTF-16 range into the display as an
    /// `NSRange` (the unit `UITextView`/`UITextRange` work in). The
    /// resulting display range is the union of every `.source` segment's
    /// display projection of the segment's source slice intersected
    /// with `sourceRange` — so a source range entirely inside one
    /// segment maps to that segment's contiguous display slice, and
    /// a range that spans multiple source segments (across an
    /// intervening synthetic block) yields the spanning display range
    /// (synthetic display content INCLUDED, because a highlight that
    /// covers two source paragraphs visually crosses the translation
    /// run between them — that's the natural UITextView behavior). An
    /// empty source range maps to an empty display range at the
    /// projected location; an out-of-range source range clamps via
    /// the map's `displayOffset(forSourceOffset:)`.
    static func displayRange(forSourceRange sourceRange: Range<Int>,
                             map: BilingualDisplaySegmentMap) -> NSRange {
        guard !sourceRange.isEmpty else {
            let start = map.displayOffset(forSourceOffset: sourceRange.lowerBound)
            return NSRange(location: start, length: 0)
        }
        // Walk segments and collect the display projection of every
        // `.source` segment whose sourceRange overlaps `sourceRange`.
        var displayLo: Int? = nil
        var displayHi: Int? = nil
        for segment in map.segments {
            guard case let .source(segSource, segDisplay) = segment else { continue }
            // Intersect [segSource.lo, segSource.hi) with [sourceRange.lo, sourceRange.hi).
            let interLo = max(segSource.lowerBound, sourceRange.lowerBound)
            let interHi = min(segSource.upperBound, sourceRange.upperBound)
            guard interLo < interHi else { continue }
            let dLo = segDisplay.lowerBound + (interLo - segSource.lowerBound)
            let dHi = segDisplay.lowerBound + (interHi - segSource.lowerBound)
            displayLo = min(displayLo ?? dLo, dLo)
            displayHi = max(displayHi ?? dHi, dHi)
        }
        guard let lo = displayLo, let hi = displayHi else {
            // No `.source` segment overlaps the requested range — clamp.
            let start = map.displayOffset(forSourceOffset: sourceRange.lowerBound)
            return NSRange(location: start, length: 0)
        }
        return NSRange(location: lo, length: hi - lo)
    }

    /// Maps an `NSRange` of source UTF-16 offsets into the display. A
    /// length-zero `NSRange` maps to a length-zero `NSRange` in display
    /// space at the projected location.
    static func displayNSRange(forSourceNSRange sourceRange: NSRange,
                               map: BilingualDisplaySegmentMap) -> NSRange {
        guard sourceRange.location != NSNotFound else { return sourceRange }
        let lower = sourceRange.location
        let upper = sourceRange.location + sourceRange.length
        return displayRange(forSourceRange: lower..<upper, map: map)
    }

    /// `true` when the display offset falls inside a synthetic
    /// translation run. The seam selection / hit-test code uses to
    /// reject a tap on a translation block.
    static func isSynthetic(displayOffset: Int,
                            map: BilingualDisplaySegmentMap) -> Bool {
        // `sourceOffset(forDisplayOffset:)` returns nil for both
        // synthetic AND out-of-range; we want only synthetic here.
        guard displayOffset >= 0, displayOffset < map.displayLength else { return false }
        return map.sourceOffset(forDisplayOffset: displayOffset) == nil
    }
}
