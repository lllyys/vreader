// Purpose: The UTF-16 character span of one chapter in a book's
// flattened text, used to bound a Chapter-scoped AI summary.
//
// Key decisions:
// - UTF-16 offsets to match Locator.charOffsetUTF16 and
//   AIContextExtractor's existing TXT/MD slicing math — mixing units
//   (UTF-16 vs Character) is the bug class to avoid.
// - `start` is inclusive, `end` is exclusive, like a Swift Range.
// - The initializer clamps to enforce the span invariant
//   (`start >= 0`, `end >= start`) so an invalid span is unrepresentable
//   without forcing an optional on callers. A zero-length span
//   (`start == end`) is valid and means an empty chapter slice.
//
// @coordinates-with: SummaryScopeResolver.swift, AIContextExtractor.swift

import Foundation

/// The UTF-16 character span of one chapter in a book's flattened text,
/// used to bound a Chapter-scoped AI summary.
///
/// Offsets are UTF-16 code units (matching `Locator.charOffsetUTF16`).
/// `startUTF16` is inclusive; `endUTF16` is exclusive. The initializer
/// clamps invalid input — a negative start becomes `0`, and an end
/// below the start is raised to the start (a zero-length span) — so the
/// half-open-span invariant always holds.
struct ChapterBounds: Sendable, Equatable {
    /// Inclusive UTF-16 offset where the chapter begins. Always `>= 0`.
    let startUTF16: Int
    /// Exclusive UTF-16 offset where the chapter ends. Always `>= startUTF16`.
    let endUTF16: Int

    /// Creates a chapter span, clamping to enforce the half-open
    /// invariant: `startUTF16` is raised to `0` if negative, and
    /// `endUTF16` is raised to `startUTF16` if it would be smaller.
    init(startUTF16: Int, endUTF16: Int) {
        let clampedStart = max(0, startUTF16)
        self.startUTF16 = clampedStart
        self.endUTF16 = max(clampedStart, endUTF16)
    }
}
