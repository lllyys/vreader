// Purpose: Feature #56 WI-12 — the TXT/MD source↔display offset map
// for bilingual interlinear mode. Records ordered ranges of the
// rendered display text, each tagged as either `.source` (a slice of
// the source text appearing verbatim in the display) or `.synthetic`
// (a translation block injected between source paragraphs). Pure
// value type — every offset path in the TXT/MD container routes
// through this map so persisted-highlight ranges, search-highlight
// nav, selection callbacks, and TTS auto-scroll work identically
// whether bilingual is on (interleaved display) or off (identity
// pass-through).
//
// Key decisions:
// - **Half-open ranges throughout** (`Range<Int>`). The codebase's
//   highlight + TTS code paths use half-open UTF-16 ranges, so the
//   map matches their convention.
// - **Source offsets are UTF-16 units.** `NSAttributedString` and
//   the TXT/MD persisted-highlight system all key on UTF-16, and the
//   `Locator.charOffsetUTF16` value is the same unit (`50-codebase-conventions.md` §2).
// - **An out-of-range display offset returns nil**, not a clamp. Hit
//   tests must decide whether to ignore the event; clamping would
//   silently round to a wrong source position. `displayOffset(forSourceOffset:)`,
//   on the other hand, clamps because callers usually use it to
//   project a saved scroll position into the rendered layout — a
//   slight clamp is the right failure mode there.
// - **An `.synthetic` display offset has no source position** —
//   `sourceOffset(forDisplayOffset:)` returns nil. Hit tests on a
//   translation run produce no selection; that's the silent-source-
//   fallback semantics (plan Decision 2).
// - **`identity(sourceLength:)` builds a 1:1 pass-through.** This is
//   the bilingual-off path's segment map and is intended to be the
//   only branchless seam through the offset-routing in the TXT/MD
//   container.
//
// @coordinates-with: BilingualTextRenderer.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12)

import Foundation

/// Maps display UTF-16 offsets in a bilingual-rendered TXT/MD reader
/// back to the source text's UTF-16 offsets (and vice versa).
struct BilingualDisplaySegmentMap: Sendable, Equatable {

    /// One segment of the display text — either a slice of the source
    /// (selection/highlight/TTS land here) or a synthetic translation
    /// run (no source position, hit tests no-op).
    enum Segment: Sendable, Equatable {
        case source(sourceRange: Range<Int>, displayRange: Range<Int>)
        case synthetic(displayRange: Range<Int>)

        /// The display range this segment occupies — used during binary
        /// search to find the segment a display offset lands in.
        var displayRange: Range<Int> {
            switch self {
            case .source(_, let range): return range
            case .synthetic(let range): return range
            }
        }
    }

    /// Total UTF-16 length of the source text this map covers.
    let sourceLength: Int

    /// Ordered list of display segments. The display ranges concatenate
    /// without gap or overlap; the source ranges of `.source` segments
    /// concatenate (also without overlap, in the source's reading
    /// order) but may not cover the full source length when synthetic
    /// runs interleave them.
    let segments: [Segment]

    /// Total UTF-16 length of the display text — the sum of every
    /// segment's `displayRange.count`. Computed once at init for
    /// fast access during render/seek work.
    let displayLength: Int

    init(sourceLength: Int, segments: [Segment]) {
        self.sourceLength = max(0, sourceLength)
        self.segments = segments
        self.displayLength = segments.last?.displayRange.upperBound ?? 0
    }

    /// Identity map — `displayLength == sourceLength`, a single
    /// `.source` segment covering everything. The bilingual-off path
    /// uses this so every offset call is a pass-through.
    static func identity(sourceLength: Int) -> BilingualDisplaySegmentMap {
        let length = max(0, sourceLength)
        guard length > 0 else {
            return BilingualDisplaySegmentMap(sourceLength: 0, segments: [])
        }
        return BilingualDisplaySegmentMap(
            sourceLength: length,
            segments: [.source(sourceRange: 0..<length, displayRange: 0..<length)]
        )
    }

    /// Maps a display UTF-16 offset back to its source UTF-16 offset.
    /// Returns `nil` if the display offset is out of bounds, negative,
    /// or falls inside a synthetic translation run.
    func sourceOffset(forDisplayOffset displayOffset: Int) -> Int? {
        guard displayOffset >= 0, displayOffset < displayLength else { return nil }
        guard let segment = segment(containingDisplayOffset: displayOffset) else { return nil }
        switch segment {
        case .source(let sourceRange, let displayRange):
            let intoSegment = displayOffset - displayRange.lowerBound
            return sourceRange.lowerBound + intoSegment
        case .synthetic:
            return nil
        }
    }

    /// Maps a source UTF-16 offset to its display UTF-16 offset. Clamps
    /// out-of-range source offsets to `0` (negative) or `displayLength`
    /// (past end) so a saved scroll position past the source length
    /// still lands somewhere sensible.
    func displayOffset(forSourceOffset sourceOffset: Int) -> Int {
        guard sourceOffset > 0 else { return 0 }
        // Past-end clamp: only when there is no source segment whose
        // upper bound is exactly `sourceOffset` (a selection end-point
        // at the last paragraph's last char should land right after
        // the paragraph in display, NOT past the trailing synthetic
        // run).
        for segment in segments {
            if case let .source(sourceRange, displayRange) = segment,
               sourceRange.contains(sourceOffset) {
                let intoSegment = sourceOffset - sourceRange.lowerBound
                return displayRange.lowerBound + intoSegment
            }
        }
        // Source offset lands at the boundary between two source
        // segments (right after the end of one). Find the source
        // segment whose upper bound is the offset and return the
        // position right after its display range — this is the
        // selection end-point semantics.
        for segment in segments {
            if case let .source(sourceRange, displayRange) = segment,
               sourceRange.upperBound == sourceOffset {
                return displayRange.upperBound
            }
        }
        // No source segment matches — saved offset past the source
        // length, or out-of-coverage. Clamp to display end.
        return displayLength
    }

    // MARK: - Private

    /// Linear search for the segment containing a display offset.
    /// Segment counts are small in practice (paragraphs per chapter
    /// rarely exceeds a few hundred); the linear walk is faster than
    /// a binary search at that scale and keeps the implementation
    /// branchless.
    private func segment(containingDisplayOffset offset: Int) -> Segment? {
        for segment in segments where segment.displayRange.contains(offset) {
            return segment
        }
        return nil
    }
}
