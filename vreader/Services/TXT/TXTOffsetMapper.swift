// Purpose: Pure logic for UTF-16 offset conversions in TXT documents.
// Handles NSRange <-> canonical UTF-16 offset mapping, surrogate-pair boundary
// snapping, and scroll/character offset conversions via TextKit layout APIs.
//
// Key decisions:
// - All offsets are UTF-16 code units, matching NSString/UITextView semantics.
// - Surrogate-pair boundary snapping always rounds to the start of the pair.
// - NSRange uses UTF-16 units (same as NSString.length), so conversion is identity
//   for well-formed ranges; the main job is validation and boundary snapping.
//
// @coordinates-with Locator.swift, LocatorFactory.swift, TXTTextViewBridge.swift

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Result of converting an NSRange selection to canonical UTF-16 offsets.
struct UTF16Range: Sendable {
    let startUTF16: Int
    let endUTF16: Int
}

/// Pure helper for offset conversions between UITextView's NSRange and
/// the canonical UTF-16 offsets stored in Locator.
enum TXTOffsetMapper {

    // MARK: - NSRange <-> UTF-16

    /// Converts an NSRange (from UITextView selection) to canonical UTF-16 start/end offsets.
    ///
    /// Returns nil if the NSRange is invalid (NSNotFound or exceeds text length).
    /// NSRange already uses UTF-16 code units, so this is primarily validation.
    static func selectionToUTF16Range(
        nsRange: NSRange,
        text: String
    ) -> UTF16Range? {
        guard nsRange.location != NSNotFound else { return nil }
        let utf16Count = (text as NSString).length
        let end = nsRange.location + nsRange.length
        guard nsRange.location >= 0,
              end >= nsRange.location,
              end <= utf16Count else {
            return nil
        }
        return UTF16Range(
            startUTF16: nsRange.location,
            endUTF16: end
        )
    }

    /// Converts canonical UTF-16 start/end offsets back to an NSRange.
    ///
    /// Returns nil if offsets are negative, inverted, or exceed text length.
    static func utf16RangeToNSRange(
        startUTF16: Int,
        endUTF16: Int,
        text: String
    ) -> NSRange? {
        guard startUTF16 >= 0, endUTF16 >= startUTF16 else { return nil }
        let utf16Count = (text as NSString).length
        guard endUTF16 <= utf16Count else { return nil }
        return NSRange(location: startUTF16, length: endUTF16 - startUTF16)
    }

    // MARK: - Surrogate Pair Boundary Snapping

    /// Snaps a UTF-16 offset to a valid Unicode scalar boundary.
    ///
    /// If the offset lands in the middle of a surrogate pair, it snaps backward
    /// to the start of the pair. Offsets are clamped to [0, text.utf16.count].
    static func snapToValidBoundary(utf16Offset: Int, in text: String) -> Int {
        let utf16 = text.utf16
        let count = utf16.count
        let clamped = min(max(utf16Offset, 0), count)

        guard clamped > 0, clamped < count else {
            return clamped
        }

        let index = utf16.index(utf16.startIndex, offsetBy: clamped)
        // Check if we can map to a valid Unicode scalar position
        if index.samePosition(in: text.unicodeScalars) != nil {
            return clamped
        }

        // We're in the middle of a surrogate pair — snap backward
        return clamped - 1
    }

    // MARK: - Scroll Position <-> Character Offset (TextKit)

    #if canImport(UIKit)
    /// Maps a scroll Y offset to the nearest character (UTF-16) offset using TextKit layout.
    ///
    /// Uses the layout manager to find the glyph at the given vertical position,
    /// then maps that glyph to a character index.
    @MainActor
    static func scrollOffsetToCharOffset(
        scrollY: CGFloat,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> Int {
        let insetX = textContainer.lineFragmentPadding
        let point = CGPoint(x: insetX, y: scrollY)
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return charIndex
    }

    /// Maps a character (UTF-16) offset to a scroll Y position using TextKit layout.
    ///
    /// Finds the line fragment rect containing the character and returns its minY.
    @MainActor
    static func charOffsetToScrollOffset(
        charOffset: Int,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> CGFloat {
        let textLength = layoutManager.textStorage?.length ?? 0
        let clampedOffset = min(max(charOffset, 0), textLength)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: clampedOffset, length: 0),
            actualCharacterRange: nil
        )
        let rect = layoutManager.lineFragmentRect(
            forGlyphAt: max(glyphRange.location, 0),
            effectiveRange: nil
        )
        return rect.minY
    }
    #endif
}
