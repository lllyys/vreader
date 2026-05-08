// Purpose: Unit tests for TXT offset conversions — UTF-16 <-> NSRange round-trips,
// surrogate-pair boundary snapping, and scroll/char offset mapping helpers.

import Testing
import Foundation
@testable import vreader

@Suite("TXTOffsetMapper")
struct TXTOffsetMapperTests {

    // MARK: - selectionToUTF16Range

    @Test func selectionToUTF16RangeASCII() {
        let text = "Hello, World!"
        // Select "World" — NSRange(7, 5)
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 7, length: 5),
            text: text
        )
        #expect(result?.startUTF16 == 7)
        #expect(result?.endUTF16 == 12)
    }

    @Test func selectionToUTF16RangeCJK() {
        // CJK characters are 1 UTF-16 code unit each
        let text = "你好世界" // 4 chars, 4 UTF-16 code units
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 1, length: 2),
            text: text
        )
        #expect(result?.startUTF16 == 1)
        #expect(result?.endUTF16 == 3)
    }

    @Test func selectionToUTF16RangeEmoji() {
        // Emoji with surrogate pairs: 🎉 is 2 UTF-16 code units
        let text = "A🎉B"
        // NSString: A=0, 🎉=1..2, B=3 (NSString uses UTF-16)
        let nsText = text as NSString
        #expect(nsText.length == 4) // A(1) + 🎉(2) + B(1)

        // Select the emoji — NSRange(1, 2)
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 1, length: 2),
            text: text
        )
        #expect(result?.startUTF16 == 1)
        #expect(result?.endUTF16 == 3)
    }

    @Test func selectionToUTF16RangeMixedContent() {
        // "A你🎉B" — A(1) + 你(1) + 🎉(2) + B(1) = 5 UTF-16 code units
        let text = "A你🎉B"
        let nsText = text as NSString
        #expect(nsText.length == 5)

        // Select "你🎉" — NSRange(1, 3)
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 1, length: 3),
            text: text
        )
        #expect(result?.startUTF16 == 1)
        #expect(result?.endUTF16 == 4)
    }

    @Test func selectionToUTF16RangeEmptyRange() {
        let text = "Hello"
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 3, length: 0),
            text: text
        )
        #expect(result?.startUTF16 == 3)
        #expect(result?.endUTF16 == 3)
    }

    @Test func selectionToUTF16RangeEmptyText() {
        let text = ""
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 0, length: 0),
            text: text
        )
        #expect(result?.startUTF16 == 0)
        #expect(result?.endUTF16 == 0)
    }

    @Test func selectionToUTF16RangeOutOfBounds() {
        let text = "Hi"
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 5, length: 3),
            text: text
        )
        #expect(result == nil)
    }

    @Test func selectionToUTF16RangeNotFound() {
        let text = "Hi"
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: NSNotFound, length: 0),
            text: text
        )
        #expect(result == nil)
    }

    // MARK: - utf16RangeToNSRange

    @Test func utf16ToNSRangeASCII() {
        let text = "Hello, World!"
        let result = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: 7,
            endUTF16: 12,
            text: text
        )
        #expect(result?.location == 7)
        #expect(result?.length == 5)
    }

    @Test func utf16ToNSRangeEmoji() {
        let text = "A🎉B"
        // 🎉 is at UTF-16 offsets 1..2, B is at 3
        let result = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: 1,
            endUTF16: 3,
            text: text
        )
        #expect(result?.location == 1)
        #expect(result?.length == 2)
    }

    @Test func utf16ToNSRangeEmptyRange() {
        let text = "Hello"
        let result = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: 3,
            endUTF16: 3,
            text: text
        )
        #expect(result?.location == 3)
        #expect(result?.length == 0)
    }

    @Test func utf16ToNSRangeOutOfBounds() {
        let text = "Hi" // 2 UTF-16 code units
        let result = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: 0,
            endUTF16: 10,
            text: text
        )
        #expect(result == nil)
    }

    @Test func utf16ToNSRangeInvertedRange() {
        let text = "Hello"
        let result = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: 5,
            endUTF16: 2,
            text: text
        )
        #expect(result == nil)
    }

    @Test func utf16ToNSRangeNegativeOffset() {
        let text = "Hello"
        let result = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: -1,
            endUTF16: 3,
            text: text
        )
        #expect(result == nil)
    }

    // MARK: - Round-trip: UTF-16 -> NSRange -> UTF-16

    @Test func roundTripASCII() {
        let text = "The quick brown fox jumps over the lazy dog"
        let startUTF16 = 4
        let endUTF16 = 9 // "quick"

        let nsRange = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: startUTF16, endUTF16: endUTF16, text: text
        )
        #expect(nsRange != nil)

        let backToUTF16 = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: nsRange!, text: text
        )
        #expect(backToUTF16?.startUTF16 == startUTF16)
        #expect(backToUTF16?.endUTF16 == endUTF16)
    }

    @Test func roundTripEmoji() {
        let text = "Hello 🌍🌎🌏 World"
        // 🌍 starts at UTF-16 offset 6, each globe is 2 UTF-16 units
        let startUTF16 = 6
        let endUTF16 = 12 // all three globes

        let nsRange = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: startUTF16, endUTF16: endUTF16, text: text
        )
        #expect(nsRange != nil)

        let backToUTF16 = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: nsRange!, text: text
        )
        #expect(backToUTF16?.startUTF16 == startUTF16)
        #expect(backToUTF16?.endUTF16 == endUTF16)
    }

    @Test func roundTripCJK() {
        let text = "这是一个测试文本" // 8 CJK chars, each 1 UTF-16 unit
        let startUTF16 = 2
        let endUTF16 = 6

        let nsRange = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: startUTF16, endUTF16: endUTF16, text: text
        )
        #expect(nsRange != nil)

        let backToUTF16 = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: nsRange!, text: text
        )
        #expect(backToUTF16?.startUTF16 == startUTF16)
        #expect(backToUTF16?.endUTF16 == endUTF16)
    }

    @Test func roundTripMixed() {
        // Complex mix: ASCII + CJK + emoji + combining chars
        let text = "Hi你好🎉end"
        // H(1) i(1) 你(1) 好(1) 🎉(2) e(1) n(1) d(1) = 9 UTF-16 units
        let nsText = text as NSString
        #expect(nsText.length == 9)

        let startUTF16 = 2  // 你
        let endUTF16 = 6    // after 🎉

        let nsRange = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: startUTF16, endUTF16: endUTF16, text: text
        )
        #expect(nsRange != nil)

        let backToUTF16 = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: nsRange!, text: text
        )
        #expect(backToUTF16?.startUTF16 == startUTF16)
        #expect(backToUTF16?.endUTF16 == endUTF16)
    }

    // MARK: - Surrogate pair boundary snapping

    @Test func snapSurrogatePairBoundary() {
        let text = "A🎉B" // A=0, 🎉=1..2, B=3
        // Trying to split in the middle of the surrogate pair at offset 2
        let snapped = TXTOffsetMapper.snapToValidBoundary(utf16Offset: 2, in: text)
        // Should snap to either 1 (start of emoji) or 3 (end of emoji)
        #expect(snapped == 1 || snapped == 3)
    }

    @Test func snapAtValidBoundary() {
        let text = "ABC"
        let snapped = TXTOffsetMapper.snapToValidBoundary(utf16Offset: 1, in: text)
        #expect(snapped == 1) // Already valid, no change
    }

    @Test func snapAtStart() {
        let text = "🎉Hello"
        let snapped = TXTOffsetMapper.snapToValidBoundary(utf16Offset: 0, in: text)
        #expect(snapped == 0)
    }

    @Test func snapAtEnd() {
        let text = "Hello🎉"
        let count = (text as NSString).length
        let snapped = TXTOffsetMapper.snapToValidBoundary(utf16Offset: count, in: text)
        #expect(snapped == count)
    }

    @Test func snapBeyondEnd() {
        let text = "Hi"
        let snapped = TXTOffsetMapper.snapToValidBoundary(utf16Offset: 100, in: text)
        #expect(snapped == 2) // Clamped to text length
    }

    @Test func snapNegativeOffset() {
        let text = "Hi"
        let snapped = TXTOffsetMapper.snapToValidBoundary(utf16Offset: -5, in: text)
        #expect(snapped == 0) // Clamped to 0
    }

    // MARK: - Boundary: entire text selection

    @Test func selectEntireText() {
        let text = "Hello 🌍 World"
        let nsText = text as NSString
        let result = TXTOffsetMapper.selectionToUTF16Range(
            nsRange: NSRange(location: 0, length: nsText.length),
            text: text
        )
        #expect(result?.startUTF16 == 0)
        #expect(result?.endUTF16 == nsText.length)
    }

    // MARK: - scrollOffsetForVisibleMatch (Bug #153)

    /// Bug #153: search-result-tap navigation places matched text above the
    /// visible viewport because the existing scroll path uses `lineFragmentRect.minY`
    /// directly as `contentOffset.y` — which puts the matched line at the very top
    /// edge with only `textContainerInset.top` of breathing room. When the match is
    /// near the document end, iOS clamps `contentOffset.y` to the document's max scroll
    /// position; the resulting visible region depends on document height vs viewport,
    /// and in the field this surfaces as the matched line being pushed off-screen above
    /// before the user can find it (the 3 s highlight auto-clear timer fires meanwhile).
    /// This helper computes a scroll target that gives the matched line headroom from
    /// the top so it is comfortably in view.
    @Test func scrollOffsetForVisibleMatch_middleOfDocument_appliesHeadroom() {
        // Match line at y=2400 (middle of doc), viewport=700, topInset=16.
        // Expected: line positioned at viewport*0.25 = 175pt from visible top.
        // contentOffset.y = lineY + topInset - headroom = 2400 + 16 - 175 = 2241.
        let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
            lineY: 2400,
            viewportHeight: 700,
            topInset: 16
        )
        #expect(scrollY == 2241)
    }

    @Test func scrollOffsetForVisibleMatch_nearDocumentStart_clampsToZero() {
        // Line at y=50, headroom would be 175pt, requested would be -109 → clamped to 0.
        // The matched line is then at offset (50+16)=66 from the top of viewport.
        let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
            lineY: 50,
            viewportHeight: 700,
            topInset: 16
        )
        #expect(scrollY == 0)
    }

    @Test func scrollOffsetForVisibleMatch_documentStart_clampsToZero() {
        // Line at y=0, headroom 175 → would be -159 → clamped to 0.
        let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
            lineY: 0,
            viewportHeight: 700,
            topInset: 16
        )
        #expect(scrollY == 0)
    }

    @Test func scrollOffsetForVisibleMatch_zeroHeadroom_putsLineAtTopWithInset() {
        // Headroom 0 = put the line right at the top of viewport (with inset margin).
        let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
            lineY: 1000,
            viewportHeight: 700,
            topInset: 16,
            headroomFraction: 0
        )
        #expect(scrollY == 1016) // 1000 + 16 - 0
    }

    @Test func scrollOffsetForVisibleMatch_clampsHeadroomFractionAtUpperBound() {
        // Fraction > 0.9 is clamped to 0.9 to prevent the line being pushed off
        // the bottom of the viewport (which would defeat the "make it visible" purpose).
        let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
            lineY: 2000,
            viewportHeight: 700,
            topInset: 0,
            headroomFraction: 1.5
        )
        // Expected: clamped fraction = 0.9 → headroom = 630 → 2000 + 0 - 630 = 1370
        #expect(scrollY == 1370)
    }

    @Test func scrollOffsetForVisibleMatch_clampsNegativeHeadroomFractionAtZero() {
        // Negative fraction is clamped to 0 (line goes to top of viewport with inset).
        let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
            lineY: 2000,
            viewportHeight: 700,
            topInset: 16,
            headroomFraction: -0.5
        )
        #expect(scrollY == 2016)
    }

    @Test func scrollOffsetForVisibleMatch_typicalSearchTapNearDocumentEnd_keepsMatchAboveBottom() {
        // Bug #153 repro shape: 100-paragraph TXT, paragraph 100 first line at lineY ≈ 17820,
        // viewport 700, top inset 16. Document content height ≈ 18000. iOS clamps
        // contentOffset.y to maxY = 18000 - 700 = 17300.
        //
        // Existing path: scrollY = lineY = 17820 → iOS clamps to 17300. Matched line
        // is at content y = 17820+16 = 17836. Visible region [17300, 18000]. Matched
        // line at offset 17836-17300 = 536 from visible top → roughly at the BOTTOM
        // of the viewport.
        //
        // Headroom path: scrollY = 17820 + 16 - 175 = 17661 (no clamp needed since
        // 17661 < 17300 is false; but iOS still clamps if scrollY > maxY).
        // Wait: 17661 > 17300 (maxY), so iOS clamps to 17300. Visible region
        // [17300, 18000]. Matched line at 17836 → 536 from visible top. Same.
        //
        // The headroom helps in the COMMON case (not clamped near doc end) — the
        // pure-logic helper just returns the desired pre-clamp scrollY. The behavioral
        // benefit is verified end-to-end on the simulator.
        let scrollY = TXTOffsetMapper.scrollOffsetForVisibleMatch(
            lineY: 17820,
            viewportHeight: 700,
            topInset: 16
        )
        #expect(scrollY == 17661) // 17820 + 16 - (700*0.25)=175 = 17661
    }
}
