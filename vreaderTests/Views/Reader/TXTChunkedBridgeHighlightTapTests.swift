// Purpose: Tests for `TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap`
// (Feature #53 WI-3 / GH #596). Verifies the tap-point → chunk-local char-index →
// global char-index → highlight-UUID pipeline produces correct
// `ReaderHighlightTapEvent`s against a real `HighlightableTextView` fixture
// when the persisted lookup is keyed against document-global UTF-16 ranges.
//
// @coordinates-with: TXTChunkedReaderBridge.swift, HighlightableTextView.swift,
//   TextHighlightHitTester.swift, TXTTextViewBridge.swift (sister non-chunked path)

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@MainActor
private func makeChunkFixture(text: String) -> UITextView {
    let tv = UITextView()
    tv.isEditable = false
    tv.isSelectable = true
    tv.attributedText = NSAttributedString(
        string: text,
        attributes: [.font: UIFont.systemFont(ofSize: 16)]
    )
    tv.frame = CGRect(x: 0, y: 0, width: 800, height: 200)
    tv.textContainer.lineFragmentPadding = 0
    tv.textContainerInset = .zero
    tv.layoutManager.ensureLayout(for: tv.textContainer)
    return tv
}

@Suite("TXTChunkedBridgeHighlightTap")
struct TXTChunkedBridgeHighlightTapTests {

    @Test @MainActor
    func resolveChunkedHighlightTap_emptyLookup_returnsNil() {
        let tv = makeChunkFixture(text: "hello world")
        let result = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: CGPoint(x: 10, y: 5),
            in: tv,
            chunkIndex: 0,
            chunkStartOffsets: [0],
            lookup: []
        )
        #expect(result == nil)
    }

    @Test @MainActor
    func resolveChunkedHighlightTap_chunk0_pointInsideRange_returnsEvent() {
        // Chunk 0 starts at global offset 0; chunk-local range [6, 11) is "world"
        // and global range [6, 11) is the same. Tap inside should hit.
        let tv = makeChunkFixture(text: "hello world")
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 6, length: 5)
        )]
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        let tapPoint = CGPoint(x: charRect.midX, y: charRect.midY)

        let result = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: tapPoint,
            in: tv,
            chunkIndex: 0,
            chunkStartOffsets: [0],
            lookup: lookup
        )
        #expect(result?.highlightID == id)
        #expect(result?.sourceRect != .zero)
    }

    @Test @MainActor
    func resolveChunkedHighlightTap_chunk2_addsChunkStartOffset() {
        // Chunk 2 starts at global offset 100. Its local text is "hello world".
        // The persisted highlight is at GLOBAL range [106, 111) (= chunk-local
        // [6, 11) once 100 is subtracted). A tap inside the rendered "world"
        // span should hit, proving the chunk-offset addition.
        let tv = makeChunkFixture(text: "hello world")
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 106, length: 5)
        )]
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        let tapPoint = CGPoint(x: charRect.midX, y: charRect.midY)

        let result = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: tapPoint,
            in: tv,
            chunkIndex: 2,
            chunkStartOffsets: [0, 50, 100],
            lookup: lookup
        )
        #expect(result?.highlightID == id)
    }

    @Test @MainActor
    func resolveChunkedHighlightTap_pointOutsideAllRanges_returnsNil() {
        // Persisted range covers only "hello" (global [0, 5)). Tap over "world".
        let tv = makeChunkFixture(text: "hello world")
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 0, length: 5)
        )]
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        let tapPoint = CGPoint(x: charRect.midX, y: charRect.midY)

        let result = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: tapPoint,
            in: tv,
            chunkIndex: 0,
            chunkStartOffsets: [0],
            lookup: lookup
        )
        #expect(result == nil)
    }

    @Test @MainActor
    func resolveChunkedHighlightTap_chunkIndexOutOfBounds_returnsNil() {
        // Defensive: if a tap arrives for a cell whose chunkIndex exceeds
        // the offsets array length, we must NOT crash. Returns nil cleanly.
        let tv = makeChunkFixture(text: "hello")
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 0, length: 5)
        )]
        let result = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: CGPoint(x: 5, y: 5),
            in: tv,
            chunkIndex: 99,
            chunkStartOffsets: [0, 10, 20],
            lookup: lookup
        )
        #expect(result == nil)
    }

    @Test @MainActor
    func resolveChunkedHighlightTap_returnsNonZeroSourceRect_forVisibleSpan() {
        // Acceptance: sourceRect must be non-zero so the presenter has
        // somewhere to anchor the menu.
        let tv = makeChunkFixture(text: "hello world")
        let id = UUID()
        // Chunk 1 starts at global offset 50; local "hello" range = global [50, 55).
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 50, length: 5)
        )]
        let tapPoint = CGPoint(x: 5, y: 5)
        guard let event = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: tapPoint,
            in: tv,
            chunkIndex: 1,
            chunkStartOffsets: [0, 50],
            lookup: lookup
        ) else {
            Issue.record("Expected a hit for tap over 'hello' in chunk 1")
            return
        }
        #expect(event.sourceRect.width > 0)
        #expect(event.sourceRect.height > 0)
    }

    @Test @MainActor
    func resolveChunkedHighlightTap_globalRangeStraddlesChunks_localSliceUsedForSourceRect() {
        // Edge case: a persisted highlight at GLOBAL range [48, 56) spans
        // the boundary between chunk 0 (offsets[0]=0, length 50) and chunk 1
        // (offsets[1]=50). When the user taps inside the chunk-1 portion
        // (global 50–55 → local 0–5 of "hello world"), the resolver must:
        // (a) return the highlight's UUID, and
        // (b) clip the sourceRect to the chunk-1 portion (local [0, 6))
        //     so the popover anchors above the visible slice in this cell,
        //     not above the missing pre-50 slice from chunk 0.
        let tv = makeChunkFixture(text: "hello world")
        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 48, length: 8)  // global [48, 56)
        )]
        let lm = tv.layoutManager
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: 2, length: 1),
            actualCharacterRange: nil
        )
        let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
        let tapPoint = CGPoint(x: charRect.midX, y: charRect.midY)

        let result = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: tapPoint,
            in: tv,
            chunkIndex: 1,
            chunkStartOffsets: [0, 50],
            lookup: lookup
        )
        #expect(result?.highlightID == id)
        // Non-zero size proves clipping produced a valid local range.
        #expect((result?.sourceRect.width ?? 0) > 0)
    }

    /// Per Bug #203 (GH #743): the pure-point overload must return the rect
    /// in the textView's local coordinate space — NOT the textView's
    /// window-space. The gesture-based wrapper converts to tableView-local
    /// before calling the presenter; the pure-point helper's contract is
    /// just "view-local relative to the passed textView." If this helper
    /// re-introduces a `convert(_, to: nil)` call, the gesture wrapper's
    /// subsequent `textView.convert(_, to: tableView)` would double-apply
    /// the window→view delta and the menu would land off-screen.
    @Test @MainActor
    func resolveChunkedHighlightTap_pureOverload_returnsViewLocalRect_notWindowSpace() {
        let tv = makeChunkFixture(text: "hello world")
        // Embed in a window at non-zero origin so the two spaces differ.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        tv.frame = CGRect(x: 50, y: 100, width: 700, height: 200)
        window.addSubview(tv)

        let id = UUID()
        let lookup = [PersistedHighlightLookupEntry(
            id: id, range: NSRange(location: 0, length: 5)  // "hello"
        )]
        let tapPoint = CGPoint(x: 5, y: 5)
        guard let event = TXTChunkedReaderBridge.Coordinator.resolveChunkedHighlightTap(
            tapPointInCell: tapPoint,
            in: tv,
            chunkIndex: 0,
            chunkStartOffsets: [0],
            lookup: lookup
        ) else {
            Issue.record("Expected a hit for tap over 'hello'")
            return
        }

        #expect(event.sourceRect.origin.x < 50,
                "sourceRect.x should be textView-local; got \(event.sourceRect.origin.x) — likely still window-space (offset by 50)")
        #expect(event.sourceRect.origin.y < 100,
                "sourceRect.y should be textView-local; got \(event.sourceRect.origin.y) — likely still window-space (offset by 100)")
    }
}
#endif
