// Purpose: One shared UTF-16-unit clamp for the AI context builders. Truncates a
// string to at most `maxUTF16` UTF-16 code units at a Character (grapheme)
// boundary, so it is CJK-safe and never splits a surrogate pair or a ZWJ
// grapheme cluster. Feature #86 WI-2 — extracted so `ChatAnnotationContext` and
// `ChatContextAssembler` share one implementation (Gate-4: avoid drift).
//
// @coordinates-with: ChatAnnotationContext.swift, ChatContextAssembler.swift

import Foundation

enum UTF16Clamp {
    /// Returns `s` truncated to at most `maxUTF16` UTF-16 units, cut at a
    /// Character boundary (never mid-grapheme/scalar). `maxUTF16 <= 0` → "".
    static func clamp(_ s: String, maxUTF16: Int) -> String {
        guard maxUTF16 > 0 else { return "" }
        guard s.utf16.count > maxUTF16 else { return s }
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(after: idx)
            if s[s.startIndex..<next].utf16.count > maxUTF16 { break }
            idx = next
        }
        return String(s[s.startIndex..<idx])
    }
}
