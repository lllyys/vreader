// Purpose: Feature #56 WI-12b — wraps a `TXTTextViewBridgeDelegate` and
// routes display-domain UTF-16 offsets the bridge reports back to
// source-domain offsets via `BilingualDisplaySegmentMap`, so the
// underlying VM (the receiver) keeps persisting positions in the
// document's source coordinates. When bilingual is off (identity map),
// the adapter is a transparent pass-through.
//
// Why an adapter? `TXTReaderViewModel` persists position changes from
// the bridge as document-global UTF-16 offsets and treats those values
// as source-domain. With bilingual interlinear ON, the bridge sees a
// rendered string whose offsets include synthetic translation runs —
// raw display offsets would corrupt the persisted position the next
// time the book opens (the translation cache may have changed).
//
// The adapter:
// - Routes `scrollPositionDidChange(topCharOffsetUTF16:)` via
//   `BilingualOffsetRouter.sourceOffset(forDisplayOffset:)`. A
//   display position inside a synthetic run resolves to the
//   nearest preceding source segment's last offset (sensible
//   "scroll near translation" fallback).
// - Routes `selectionDidChange(utf16Range:)` similarly. A selection
//   that starts inside a synthetic run is dropped (zero range), so
//   the VM doesn't try to highlight a translation block.
//
// Key decisions:
// - **Same `@MainActor` isolation as the delegate.** The wrapped
//   delegate is `@MainActor`; the adapter is too.
// - **Captures the segment map by value at construction.** Updates
//   require constructing a new adapter when the map changes — which
//   matches the SwiftUI rebuild pattern (the container rebuilds the
//   bridge when `chapterAttrString` rebuilds).
// - **Off-mode (identity) is byte-identical to today.** Identity-map
//   routing for the delegate is a literal pass-through.
//
// @coordinates-with: BilingualDisplaySegmentMap.swift,
//   BilingualOffsetRouter.swift, TXTTextViewBridge.swift,
//   TXTReaderViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

#if canImport(UIKit)
import Foundation
import UIKit

@MainActor
final class BilingualTXTBridgeDelegateAdapter: NSObject, TXTTextViewBridgeDelegate {

    private weak var wrapped: TXTTextViewBridgeDelegate?
    private let segmentMap: BilingualDisplaySegmentMap

    init(wrapping wrapped: TXTTextViewBridgeDelegate?,
         segmentMap: BilingualDisplaySegmentMap) {
        self.wrapped = wrapped
        self.segmentMap = segmentMap
    }

    func selectionDidChange(utf16Range: UTF16Range) {
        // Map start + end through the segment map. A range that starts
        // inside a synthetic run has no source-domain analogue — drop it
        // (zero-length range at the projected location) so the VM does
        // not try to highlight the translation block.
        guard let start = segmentMap.sourceOffset(forDisplayOffset: utf16Range.startUTF16) else {
            // Start in synthetic — drop the selection.
            return
        }
        // Codex Gate-4 L1: the *exclusive* selection end at
        // `endUTF16` may legitimately land at a synthetic-block start
        // (the position AFTER the last source character in the
        // preceding source segment). `sourceOffset(forDisplayOffset:)`
        // returns nil there because synthetic-segment offsets have no
        // source position. Use end-boundary semantics: if the end is
        // at `displayLength`, map to `sourceLength`; otherwise project
        // back to the end of the most recent source segment so the
        // selection preserves its end-point instead of collapsing.
        let endSource = Self.routeSelectionEnd(
            displayOffset: utf16Range.endUTF16, start: start, map: segmentMap
        )
        let routed = UTF16Range(startUTF16: start, endUTF16: endSource)
        wrapped?.selectionDidChange(utf16Range: routed)
    }

    /// Maps the *exclusive* end of a selection back to source. End at a
    /// synthetic-segment boundary → end of preceding source segment.
    /// End at `displayLength` → `sourceLength`. End inside a synthetic
    /// → end of nearest preceding source segment.
    static func routeSelectionEnd(
        displayOffset: Int, start: Int, map: BilingualDisplaySegmentMap
    ) -> Int {
        // At displayLength (selection extends to the rendered text's
        // end) — return sourceLength.
        if displayOffset >= map.displayLength { return map.sourceLength }
        // Interior point — try direct mapping.
        if let source = map.sourceOffset(forDisplayOffset: displayOffset) {
            return source
        }
        // Inside a synthetic — return the source upperBound of the
        // most recent preceding `.source` segment (boundary semantics).
        var lastSourceEnd = start
        for segment in map.segments {
            if case let .source(sourceRange, displayRange) = segment {
                if displayRange.lowerBound >= displayOffset { break }
                lastSourceEnd = sourceRange.upperBound
            }
        }
        return lastSourceEnd
    }

    func scrollPositionDidChange(topCharOffsetUTF16: Int) {
        // The "top visible character" might fall inside a synthetic run
        // (the visible top of the viewport is mid-translation). Walk
        // back through the segment map for the nearest preceding source
        // offset so the persisted position stays in source coordinates.
        let routed = BilingualTXTBridgeDelegateAdapter.routeDisplayPositionToSource(
            displayOffset: topCharOffsetUTF16, map: segmentMap
        )
        wrapped?.scrollPositionDidChange(topCharOffsetUTF16: routed)
    }

    /// Best-effort projection of a display offset to source: returns
    /// the source offset directly if the display offset is in a
    /// `.source` segment, otherwise returns the end of the most
    /// recent preceding `.source` segment (so "scrolled into a
    /// translation" persists as "scrolled to the end of the preceding
    /// source paragraph"). Identity map = byte-identical pass-through.
    static func routeDisplayPositionToSource(
        displayOffset: Int, map: BilingualDisplaySegmentMap
    ) -> Int {
        if let source = map.sourceOffset(forDisplayOffset: displayOffset) {
            return source
        }
        var lastSourceEnd = 0
        for segment in map.segments {
            if case let .source(sourceRange, displayRange) = segment {
                if displayRange.lowerBound > displayOffset { break }
                lastSourceEnd = sourceRange.upperBound
            }
        }
        return lastSourceEnd
    }
}
#endif
