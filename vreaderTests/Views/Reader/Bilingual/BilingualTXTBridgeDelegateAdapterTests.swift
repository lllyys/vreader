// Purpose: Feature #56 WI-12b — pin the bilingual TXT bridge delegate
// adapter. Identity map = byte-identical pass-through (the off-path
// regression guard). Synthetic-skip semantics for selection / scroll.
//
// @coordinates-with: BilingualTXTBridgeDelegateAdapter.swift,
//   BilingualDisplaySegmentMap.swift, TXTTextViewBridge.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #56 WI-12b — BilingualTXTBridgeDelegateAdapter")
@MainActor
struct BilingualTXTBridgeDelegateAdapterTests {

    // MARK: - identity map: byte-identical pass-through

    @Test("identity: selectionDidChange forwards verbatim")
    func identitySelectionForwards() {
        let recorder = RecordingDelegate()
        let adapter = BilingualTXTBridgeDelegateAdapter(
            wrapping: recorder,
            segmentMap: BilingualDisplaySegmentMap.identity(sourceLength: 100)
        )
        adapter.selectionDidChange(utf16Range: UTF16Range(startUTF16: 10, endUTF16: 25))
        #expect(recorder.lastSelection?.startUTF16 == 10)
        #expect(recorder.lastSelection?.endUTF16 == 25)
    }

    @Test("identity: scrollPositionDidChange forwards verbatim")
    func identityScrollForwards() {
        let recorder = RecordingDelegate()
        let adapter = BilingualTXTBridgeDelegateAdapter(
            wrapping: recorder,
            segmentMap: BilingualDisplaySegmentMap.identity(sourceLength: 100)
        )
        adapter.scrollPositionDidChange(topCharOffsetUTF16: 42)
        #expect(recorder.lastScroll == 42)
    }

    // MARK: - non-identity map: synthetic-skip semantics

    @Test("synthetic selection start is dropped")
    func syntheticSelectionDropped() {
        let recorder = RecordingDelegate()
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let adapter = BilingualTXTBridgeDelegateAdapter(wrapping: recorder, segmentMap: map)
        // Selection 4..<5 starts in the synthetic range → dropped.
        adapter.selectionDidChange(utf16Range: UTF16Range(startUTF16: 4, endUTF16: 5))
        #expect(recorder.lastSelection == nil)
    }

    @Test("non-synthetic selection routes to source")
    func nonSyntheticSelectionRoutes() {
        let recorder = RecordingDelegate()
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let adapter = BilingualTXTBridgeDelegateAdapter(wrapping: recorder, segmentMap: map)
        // Selection 6..<8 (display) → source 3..<5.
        adapter.selectionDidChange(utf16Range: UTF16Range(startUTF16: 6, endUTF16: 8))
        #expect(recorder.lastSelection?.startUTF16 == 3)
        #expect(recorder.lastSelection?.endUTF16 == 5)
    }

    @Test("scroll-into-synthetic projects to end of preceding source")
    func scrollIntoSynthetic() {
        let recorder = RecordingDelegate()
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let adapter = BilingualTXTBridgeDelegateAdapter(wrapping: recorder, segmentMap: map)
        // Display offset 4 falls in the synthetic → projects to end of
        // the preceding source segment (source upper bound 3).
        adapter.scrollPositionDidChange(topCharOffsetUTF16: 4)
        #expect(recorder.lastScroll == 3)
    }

    @Test("selection ending exactly at synthetic boundary preserves end-point")
    func selectionEndAtSyntheticBoundary() {
        let recorder = RecordingDelegate()
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let adapter = BilingualTXTBridgeDelegateAdapter(wrapping: recorder, segmentMap: map)
        // Selection 0..<3 (display) ends exactly at the synthetic block
        // start. Source end-point should preserve to 3 (source end of
        // the preceding source segment), NOT collapse to a caret.
        adapter.selectionDidChange(utf16Range: UTF16Range(startUTF16: 0, endUTF16: 3))
        #expect(recorder.lastSelection?.startUTF16 == 0)
        #expect(recorder.lastSelection?.endUTF16 == 3)
    }

    @Test("selection ending at displayLength maps to sourceLength")
    func selectionEndAtDisplayLength() {
        let recorder = RecordingDelegate()
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        let adapter = BilingualTXTBridgeDelegateAdapter(wrapping: recorder, segmentMap: map)
        // Selection 6..<9 (display, the last source segment in full).
        adapter.selectionDidChange(utf16Range: UTF16Range(startUTF16: 6, endUTF16: 9))
        #expect(recorder.lastSelection?.startUTF16 == 3)
        #expect(recorder.lastSelection?.endUTF16 == 6)
    }

    @Test("scroll past last source clamps to last source end")
    func scrollPastLastSource() {
        let recorder = RecordingDelegate()
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 3, segments: segments)
        let adapter = BilingualTXTBridgeDelegateAdapter(wrapping: recorder, segmentMap: map)
        // Display 5 lands in the trailing synthetic — should map to 3
        // (end of last source).
        adapter.scrollPositionDidChange(topCharOffsetUTF16: 5)
        #expect(recorder.lastScroll == 3)
    }

    // MARK: - test double

    @MainActor
    private final class RecordingDelegate: NSObject, TXTTextViewBridgeDelegate {
        var lastSelection: UTF16Range?
        var lastScroll: Int?

        func selectionDidChange(utf16Range: UTF16Range) {
            lastSelection = utf16Range
        }

        func scrollPositionDidChange(topCharOffsetUTF16: Int) {
            lastScroll = topCharOffsetUTF16
        }
    }
}
