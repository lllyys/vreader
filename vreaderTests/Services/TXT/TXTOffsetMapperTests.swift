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
}
