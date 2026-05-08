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
        // Ensure layout is computed up to the target offset.
        // With allowsNonContiguousLayout, the layout manager may not have
        // laid out text this far — lineFragmentRect returns wrong results
        // for chapters deep in the file (e.g., chapter 1000). (bug #102 follow-up)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: clampedOffset + 1))
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

    // MARK: - Search-Tap Scroll Positioning (Bug #153)

    /// Computes a target `contentOffset.y` that places a matched line comfortably
    /// inside the viewport with headroom from the top — distinct from the position-
    /// restore path, which intentionally puts the saved offset at the very top edge.
    ///
    /// Bug #153 background: search-result-tap navigation previously called
    /// `setContentOffset(_:_:)` with `lineFragmentRect.minY` directly. That positions
    /// the matched line at `textContainerInset.top` below the visible top edge — fine
    /// for matches in the middle of the document, but for matches deep in the document
    /// iOS clamps `contentOffset.y` to `contentSize.height - bounds.height`, and the
    /// matched line ends up arbitrarily placed (often below the visible center, with
    /// the line's leading edge above the viewport so the user only sees the trailing
    /// fragment). The 3-second highlight auto-clear timer then expires before the user
    /// can find the match by scrolling — the bug's user-visible symptom.
    ///
    /// This helper applies a `headroomFraction` (default 0.25) of the viewport height
    /// as breathing room above the matched line. The caller still passes the result to
    /// `setContentOffset(_:_:)`, which iOS clamps automatically — but with headroom
    /// the unclamped target is no longer near the document end's clamp boundary, so
    /// the matched line lands closer to where we asked.
    ///
    /// The returned value is in scroll-view coordinates (`lineY` is added to
    /// `topInset` to convert from text-container coordinates).
    ///
    /// - Parameters:
    ///   - lineY: y-coordinate of the matched line in text-container coordinates,
    ///     i.e., the value returned by `charOffsetToScrollOffset`.
    ///   - viewportHeight: visible height of the text view (`bounds.height`).
    ///   - topInset: `textContainerInset.top` — converts text-container → scroll-view y.
    ///   - headroomFraction: where to place the line in the viewport, 0 = top edge,
    ///     0.5 = vertical center. Clamped to `[0, 0.9]`.
    static func scrollOffsetForVisibleMatch(
        lineY: CGFloat,
        viewportHeight: CGFloat,
        topInset: CGFloat,
        headroomFraction: CGFloat = 0.25
    ) -> CGFloat {
        let clampedFraction = min(max(headroomFraction, 0), 0.9)
        let headroom = viewportHeight * clampedFraction
        return max(0, lineY + topInset - headroom)
    }
}
