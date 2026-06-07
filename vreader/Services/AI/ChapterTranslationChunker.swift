// Purpose: Pure chunking utility for feature #56 bilingual reading. Groups
// translation segment indices into chunks each under a provider character
// budget, so a chapter that exceeds the provider's context window is sent as
// several requests (edge case (a)).
//
// Key decisions:
// - A segment is NEVER split across chunks — the response↔source mapping
//   depends on a 1:1 segment correspondence within a chunk.
// - One over-budget segment occupies its own chunk; recombination across
//   chunks is the caller's job (`ChapterTranslationService`).
// - The budget is a CHARACTER count (`String.count`), not a byte count —
//   CJK text is multi-byte in UTF-8 but the provider window is token/char
//   based and char count is the closer, format-agnostic proxy.
//
// @coordinates-with: ChapterSegmenter.swift, ChapterTranslationService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Foundation

/// Pure segment-boundary chunker for chapter translation.
enum ChapterTranslationChunker {

    /// Groups `segments` indices into chunks, each chunk's total character
    /// count not exceeding `maxCharsPerChunk` — except a single segment that
    /// is itself over budget, which occupies its own chunk.
    ///
    /// - Parameter maxCharsPerChunk: the per-chunk character budget; expected
    ///   to be `> 0`. A non-positive budget is defensively coerced to `1`
    ///   (every non-empty segment then gets its own chunk) so the function
    ///   never divides by zero or loops — but callers should pass a real
    ///   provider budget.
    /// - Returns: an ordered array of index arrays. Flattening it yields
    ///   `0..<segments.count` in order — every index appears exactly once.
    static func chunk(segments: [String], maxCharsPerChunk: Int) -> [[Int]] {
        guard !segments.isEmpty else { return [] }
        let budget = max(1, maxCharsPerChunk)

        var chunks: [[Int]] = []
        var current: [Int] = []
        var currentCount = 0

        for (index, segment) in segments.enumerated() {
            let segmentCount = segment.count

            // An over-budget segment that would not fit even an empty chunk:
            // flush the current chunk, then give the big segment its own.
            if segmentCount > budget {
                if !current.isEmpty {
                    chunks.append(current)
                    current = []
                    currentCount = 0
                }
                chunks.append([index])
                continue
            }

            // Adding this segment would overflow the current chunk → start one.
            if !current.isEmpty && currentCount + segmentCount > budget {
                chunks.append(current)
                current = []
                currentCount = 0
            }

            current.append(index)
            currentCount += segmentCount
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    /// Bug #330: sub-splits a SINGLE over-budget segment (an oversized paragraph)
    /// into ordered pieces each `≤ maxChars`, so it can be translated piece by
    /// piece instead of sent whole (which overflows the provider context window
    /// → error). Splits on the last whitespace within each budget window when one
    /// exists (keeps words/sentences intact for space-delimited languages); falls
    /// back to a hard character boundary for a long unbroken run (e.g. CJK, which
    /// has no inter-word whitespace). Grapheme-based (`Character`/`String.Index`),
    /// so it never splits a surrogate pair or combining sequence.
    ///
    /// - Returns: `[text]` unchanged when `text.count ≤ maxChars`; otherwise the
    ///   ordered pieces, which concatenate back to `text`.
    static func subSplit(_ text: String, maxChars: Int) -> [String] {
        let cap = max(1, maxChars)
        guard text.count > cap else { return [text] }

        var pieces: [String] = []
        var remaining = Substring(text)
        while remaining.count > cap {
            let hardEnd = remaining.index(remaining.startIndex, offsetBy: cap)
            // Back up to the last whitespace within the [start, hardEnd) window.
            var breakAt = hardEnd
            var i = hardEnd
            while i > remaining.startIndex {
                let prev = remaining.index(before: i)
                if remaining[prev].isWhitespace { breakAt = i; break }
                i = prev
            }
            // No whitespace in the window (one long token) → hard split at cap.
            if breakAt == remaining.startIndex { breakAt = hardEnd }
            pieces.append(String(remaining[remaining.startIndex..<breakAt]))
            remaining = remaining[breakAt...]
        }
        if !remaining.isEmpty { pieces.append(String(remaining)) }
        return pieces
    }
}
