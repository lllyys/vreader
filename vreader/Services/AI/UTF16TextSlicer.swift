// Purpose: Surrogate-pair-safe UTF-16 slicing of a String.
// Extracted from AIContextExtractor (feature #69) so the slicing
// utility is independently testable and the extractor stays small.
//
// Key decisions:
// - Slicing snaps to Unicode scalar boundaries so a surrogate pair is
//   never bisected — a lone surrogate / replacement character would
//   corrupt the text sent to an AI provider.
// - The start boundary snaps UP and the end boundary snaps DOWN, so the
//   sliced UTF-16 length never exceeds the requested span (this matters
//   for budget-bounded extraction windows).
//
// @coordinates-with: AIContextExtractor.swift

import Foundation

/// Surrogate-pair-safe UTF-16 slicing helpers.
enum UTF16TextSlicer {

    /// The direction a UTF-16 offset snaps when it lands inside a
    /// surrogate pair.
    enum SnapDirection {
        /// Snap toward the end of the string (offset never shrinks).
        case up
        /// Snap toward the start of the string (offset never grows).
        case down
    }

    /// Returns `text` sliced by UTF-16 offsets. The start boundary snaps
    /// UP and the end boundary snaps DOWN to the nearest Unicode scalar
    /// boundary, so a surrogate pair is never bisected AND the resulting
    /// UTF-16 length never exceeds `toUTF16 - fromUTF16`. Offsets are
    /// clamped to `[0, utf16.count]` internally.
    static func slice(_ text: String, fromUTF16: Int, toUTF16: Int) -> String {
        guard toUTF16 > fromUTF16 else { return "" }
        guard let startIdx = scalarAlignedIndex(in: text, utf16Offset: fromUTF16, snap: .up),
              let endIdx = scalarAlignedIndex(in: text, utf16Offset: toUTF16, snap: .down) else {
            return ""
        }
        // Snapping can collapse a degenerate single-pair slice — guard
        // against an inverted range.
        guard startIdx <= endIdx else { return "" }
        return String(text[startIdx..<endIdx])
    }

    /// Converts a UTF-16 offset to a `String.Index` aligned to a Unicode
    /// scalar boundary. If the offset lands inside a surrogate pair, it
    /// snaps in `snap`'s direction until it reaches a valid boundary, so
    /// a slice never contains a lone surrogate / replacement character.
    static func scalarAlignedIndex(
        in text: String, utf16Offset: Int, snap: SnapDirection
    ) -> String.Index? {
        let utf16View = text.utf16
        let clamped = max(0, min(utf16Offset, utf16View.count))
        var idx = utf16View.index(utf16View.startIndex, offsetBy: clamped)
        switch snap {
        case .up:
            while idx < utf16View.endIndex, idx.samePosition(in: text) == nil {
                idx = utf16View.index(idx, offsetBy: 1)
            }
        case .down:
            while idx > utf16View.startIndex, idx.samePosition(in: text) == nil {
                idx = utf16View.index(idx, offsetBy: -1)
            }
        }
        return idx.samePosition(in: text)
    }
}
