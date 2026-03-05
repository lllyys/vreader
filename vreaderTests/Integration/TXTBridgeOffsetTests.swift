// Purpose: Integration tests for end-to-end offset round-trip validation.
// Tests selection -> Locator -> restore -> selection round-trip using
// TXTOffsetMapper + LocatorFactory + LocatorRestorer pipeline.

import Testing
import Foundation
@testable import vreader

@Suite("TXTBridgeOffset Integration")
struct TXTBridgeOffsetTests {

    // MARK: - Test Fixtures

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    // MARK: - Selection -> Locator -> NSRange round-trip

    @Test func roundTripASCIISelection() {
        let text = "The quick brown fox jumps over the lazy dog"
        // Simulate user selecting "brown" — NSRange(10, 5)
        let nsRange = NSRange(location: 10, length: 5)

        // Step 1: Convert selection to UTF-16 range
        let utf16Range = TXTOffsetMapper.selectionToUTF16Range(nsRange: nsRange, text: text)
        #expect(utf16Range != nil)

        // Step 2: Create Locator from UTF-16 range
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.fingerprint,
            charRangeStartUTF16: utf16Range!.startUTF16,
            charRangeEndUTF16: utf16Range!.endUTF16,
            sourceText: text
        )
        #expect(locator != nil)
        #expect(locator?.textQuote == "brown")

        // Step 3: Restore NSRange from Locator
        let restored = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: locator!.charRangeStartUTF16!,
            endUTF16: locator!.charRangeEndUTF16!,
            text: text
        )
        #expect(restored != nil)
        #expect(restored?.location == nsRange.location)
        #expect(restored?.length == nsRange.length)
    }

    @Test func roundTripEmojiSelection() {
        let text = "Start 🌍🌎🌏 End"
        // Select all three globes
        let nsText = text as NSString
        // "Start " = 6 chars, each globe = 2 UTF-16 units
        let nsRange = NSRange(location: 6, length: 6)

        let utf16Range = TXTOffsetMapper.selectionToUTF16Range(nsRange: nsRange, text: text)
        #expect(utf16Range != nil)

        let locator = LocatorFactory.txtRange(
            fingerprint: Self.fingerprint,
            charRangeStartUTF16: utf16Range!.startUTF16,
            charRangeEndUTF16: utf16Range!.endUTF16,
            sourceText: text
        )
        #expect(locator != nil)

        let restored = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: locator!.charRangeStartUTF16!,
            endUTF16: locator!.charRangeEndUTF16!,
            text: text
        )
        #expect(restored?.location == nsRange.location)
        #expect(restored?.length == nsRange.length)

        // Verify the selected text matches
        let selectedText = nsText.substring(with: restored!)
        #expect(selectedText == "🌍🌎🌏")
    }

    @Test func roundTripCJKSelection() {
        let text = "这是一段中文测试文本，用于验证偏移量的正确性。"
        // Select "中文测试" — chars at indices 4..7, each 1 UTF-16 unit
        let nsRange = NSRange(location: 4, length: 4)

        let utf16Range = TXTOffsetMapper.selectionToUTF16Range(nsRange: nsRange, text: text)
        #expect(utf16Range != nil)

        let locator = LocatorFactory.txtRange(
            fingerprint: Self.fingerprint,
            charRangeStartUTF16: utf16Range!.startUTF16,
            charRangeEndUTF16: utf16Range!.endUTF16,
            sourceText: text
        )
        #expect(locator != nil)
        #expect(locator?.textQuote == "中文测试")

        let restored = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: locator!.charRangeStartUTF16!,
            endUTF16: locator!.charRangeEndUTF16!,
            text: text
        )
        #expect(restored?.location == nsRange.location)
        #expect(restored?.length == nsRange.length)
    }

    // MARK: - Position (cursor) -> Locator -> offset round-trip

    @Test func roundTripCursorPosition() {
        let text = "Hello 🌍 World"
        let cursorOffset = 8 // After the globe emoji (UTF-16 offset)

        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.fingerprint,
            charOffsetUTF16: cursorOffset,
            sourceText: text
        )
        #expect(locator != nil)
        #expect(locator?.charOffsetUTF16 == cursorOffset)

        // The offset should be exactly preserved
        #expect(locator!.charOffsetUTF16 == cursorOffset)
    }

    // MARK: - Edge cases

    @Test func roundTripAtDocumentStart() {
        let text = "Hello, World!"
        let nsRange = NSRange(location: 0, length: 5) // "Hello"

        let utf16Range = TXTOffsetMapper.selectionToUTF16Range(nsRange: nsRange, text: text)
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.fingerprint,
            charRangeStartUTF16: utf16Range!.startUTF16,
            charRangeEndUTF16: utf16Range!.endUTF16,
            sourceText: text
        )

        let restored = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: locator!.charRangeStartUTF16!,
            endUTF16: locator!.charRangeEndUTF16!,
            text: text
        )
        #expect(restored?.location == 0)
        #expect(restored?.length == 5)
    }

    @Test func roundTripAtDocumentEnd() {
        let text = "Hello, World!"
        let nsText = text as NSString
        let nsRange = NSRange(location: nsText.length - 6, length: 6) // "orld!"

        let utf16Range = TXTOffsetMapper.selectionToUTF16Range(nsRange: nsRange, text: text)
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.fingerprint,
            charRangeStartUTF16: utf16Range!.startUTF16,
            charRangeEndUTF16: utf16Range!.endUTF16,
            sourceText: text
        )

        let restored = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: locator!.charRangeStartUTF16!,
            endUTF16: locator!.charRangeEndUTF16!,
            text: text
        )
        #expect(restored?.location == nsRange.location)
        #expect(restored?.length == nsRange.length)
    }

    @Test func roundTripWithCombiningCharacters() {
        // "é" can be e + combining accent (2 code points, 2 UTF-16 units)
        let text = "caf\u{0065}\u{0301}" // "café" with combining accent
        let nsText = text as NSString
        // "e\u{0301}" is at indices 3..4 in NSString (2 UTF-16 units)
        let nsRange = NSRange(location: 3, length: 2)

        let utf16Range = TXTOffsetMapper.selectionToUTF16Range(nsRange: nsRange, text: text)
        #expect(utf16Range != nil)

        let restored = TXTOffsetMapper.utf16RangeToNSRange(
            startUTF16: utf16Range!.startUTF16,
            endUTF16: utf16Range!.endUTF16,
            text: text
        )
        #expect(restored?.location == nsRange.location)
        #expect(restored?.length == nsRange.length)

        let selectedText = nsText.substring(with: restored!)
        #expect(selectedText == "e\u{0301}")
    }
}
