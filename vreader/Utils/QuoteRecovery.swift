// Purpose: Find a text quote within a larger body, with context-aware disambiguation.
// Fallback mechanism when exact position data (CFI, offset, page) fails to restore.
//
// Search strategy (in order):
// 1. Exact match — unique → .exact confidence
// 2. Multiple exact matches — disambiguate with context → .contextMatch
// 3. Case-insensitive match → .fuzzy
// 4. Whitespace-normalized match → .fuzzy
// 5. Return nil if nothing found
//
// @coordinates-with: (future) AnnotationRestorer, HighlightStore

import Foundation

/// Confidence level of a quote recovery match.
enum QuoteConfidence: Sendable, Equatable {
    /// The quote was found exactly once — unambiguous.
    case exact
    /// Multiple exact matches existed; context narrowed it to one.
    case contextMatch
    /// Match required case-insensitive or whitespace-normalized search.
    case fuzzy
}

/// The result of locating a quote within a body of text.
struct QuoteRecoveryResult: Sendable, Equatable {
    /// Range of the matched text within the source string.
    let matchRange: Range<String.Index>
    /// UTF-16 code-unit offset of the match start from the beginning of the text.
    let utf16Offset: Int
    /// How the match was found.
    let confidence: QuoteConfidence
}

/// Stateless utility for recovering a text quote's position within a body of text.
enum QuoteRecovery {

    /// Find `quote` within `text`, optionally using surrounding context to disambiguate.
    ///
    /// - Parameters:
    ///   - quote: The text to find. Empty string returns nil.
    ///   - contextBefore: Text expected immediately before the quote (suffix match). Nil to skip.
    ///   - contextAfter: Text expected immediately after the quote (prefix match). Nil to skip.
    ///   - text: The full body of text to search within.
    /// - Returns: A `QuoteRecoveryResult` or nil if no match found.
    static func findQuote(
        quote: String,
        contextBefore: String?,
        contextAfter: String?,
        in text: String
    ) -> QuoteRecoveryResult? {
        guard !quote.isEmpty, !text.isEmpty else { return nil }

        // Strategy 1 & 2: Exact match
        let exactRanges = allRanges(of: quote, in: text)
        if let result = resolveMatches(
            ranges: exactRanges,
            confidence: .exact,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            text: text
        ) {
            return result
        }

        // Strategy 3: Case-insensitive match
        let ciRanges = allRanges(of: quote, in: text, options: .caseInsensitive)
        if let result = resolveMatches(
            ranges: ciRanges,
            confidence: .fuzzy,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            text: text,
            caseInsensitive: true
        ) {
            return result
        }

        // Strategy 4: Whitespace-normalized match
        if let result = findWhitespaceNormalized(
            quote: quote,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            in: text
        ) {
            return result
        }

        return nil
    }

    // MARK: - Private helpers

    /// Collect all non-overlapping ranges of `needle` in `haystack`.
    /// Overlapping matches are intentionally skipped (advances by upperBound).
    private static func allRanges(
        of needle: String,
        in haystack: String,
        options: String.CompareOptions = []
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(
                of: needle,
                options: options,
                range: searchStart..<haystack.endIndex
              ) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    /// Given candidate match ranges, pick the best one.
    /// - If exactly one range, return it with the given confidence.
    /// - If multiple, use context to disambiguate → .contextMatch (or .fuzzy if already fuzzy).
    /// - If zero, return nil.
    private static func resolveMatches(
        ranges: [Range<String.Index>],
        confidence: QuoteConfidence,
        contextBefore: String?,
        contextAfter: String?,
        text: String,
        caseInsensitive: Bool = false
    ) -> QuoteRecoveryResult? {
        guard !ranges.isEmpty else { return nil }

        if ranges.count == 1 {
            return makeResult(range: ranges[0], confidence: confidence, text: text)
        }

        // Multiple matches — try to disambiguate with context
        let disambiguated = disambiguate(
            ranges: ranges,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            text: text,
            caseInsensitive: caseInsensitive
        )

        // If context was provided and helped disambiguate, report .contextMatch.
        // If no context was provided (both nil), this is just a first-match fallback.
        let hasContext = contextBefore != nil || contextAfter != nil
        let resolvedConfidence: QuoteConfidence
        if confidence == .fuzzy {
            resolvedConfidence = .fuzzy
        } else if hasContext {
            resolvedConfidence = .contextMatch
        } else {
            resolvedConfidence = .exact
        }
        return makeResult(range: disambiguated, confidence: resolvedConfidence, text: text)
    }

    /// Score each candidate range by how well the surrounding text matches the context.
    /// Returns the best-scoring range, or the first if tied.
    /// When `caseInsensitive` is true, context comparison ignores case.
    private static func disambiguate(
        ranges: [Range<String.Index>],
        contextBefore: String?,
        contextAfter: String?,
        text: String,
        caseInsensitive: Bool = false
    ) -> Range<String.Index> {
        var bestRange = ranges[0]
        var bestScore = -1

        for range in ranges {
            var score = 0
            if let ctx = contextBefore {
                score += contextBeforeScore(range: range, context: ctx, text: text, caseInsensitive: caseInsensitive)
            }
            if let ctx = contextAfter {
                score += contextAfterScore(range: range, context: ctx, text: text, caseInsensitive: caseInsensitive)
            }
            if score > bestScore {
                bestScore = score
                bestRange = range
            }
        }
        return bestRange
    }

    /// Compare two characters, optionally case-insensitive.
    private static func charsEqual(_ a: Character, _ b: Character, caseInsensitive: Bool) -> Bool {
        caseInsensitive ? a.lowercased() == b.lowercased() : a == b
    }

    /// How many trailing characters of `context` match the text immediately before `range`.
    private static func contextBeforeScore(
        range: Range<String.Index>,
        context: String,
        text: String,
        caseInsensitive: Bool = false
    ) -> Int {
        let prefix = text[text.startIndex..<range.lowerBound]
        guard !prefix.isEmpty, !context.isEmpty else { return 0 }
        var pIdx = prefix.endIndex
        var cIdx = context.endIndex
        var matched = 0
        while pIdx > prefix.startIndex, cIdx > context.startIndex {
            pIdx = prefix.index(before: pIdx)
            cIdx = context.index(before: cIdx)
            guard charsEqual(prefix[pIdx], context[cIdx], caseInsensitive: caseInsensitive) else { break }
            matched += 1
        }
        return matched
    }

    /// How many leading characters of `context` match the text immediately after `range`.
    private static func contextAfterScore(
        range: Range<String.Index>,
        context: String,
        text: String,
        caseInsensitive: Bool = false
    ) -> Int {
        let suffix = text[range.upperBound..<text.endIndex]
        guard !suffix.isEmpty, !context.isEmpty else { return 0 }
        var sIdx = suffix.startIndex
        var cIdx = context.startIndex
        var matched = 0
        while sIdx < suffix.endIndex, cIdx < context.endIndex {
            guard charsEqual(suffix[sIdx], context[cIdx], caseInsensitive: caseInsensitive) else { break }
            sIdx = suffix.index(after: sIdx)
            cIdx = context.index(after: cIdx)
            matched += 1
        }
        return matched
    }

    /// Whitespace-normalized search: collapse whitespace runs, find all matches, disambiguate, map back.
    private static func findWhitespaceNormalized(
        quote: String,
        contextBefore: String?,
        contextAfter: String?,
        in text: String
    ) -> QuoteRecoveryResult? {
        let nQuote = normalizeWhitespace(quote)
        let nText = normalizeWhitespace(text)
        guard nQuote != quote || nText != text else { return nil }

        // Collect all normalized matches and map back to original ranges
        let nRanges = allRanges(of: nQuote, in: nText)
        var originalRanges: [Range<String.Index>] = []
        for nRange in nRanges {
            let nOffset = nText.distance(from: nText.startIndex, to: nRange.lowerBound)
            let nLength = nText.distance(from: nRange.lowerBound, to: nRange.upperBound)
            if let origRange = mapNormalizedRange(offset: nOffset, length: nLength, in: text) {
                originalRanges.append(origRange)
            }
        }

        guard !originalRanges.isEmpty else { return nil }

        // If single match, return directly; if multiple, disambiguate with context
        if originalRanges.count == 1 {
            return makeResult(range: originalRanges[0], confidence: .fuzzy, text: text)
        }

        let best = disambiguate(
            ranges: originalRanges,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            text: text
        )
        return makeResult(range: best, confidence: .fuzzy, text: text)
    }

    /// Collapse runs of whitespace to a single space using single-pass builder.
    private static func normalizeWhitespace(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        var inWhitespace = false
        for char in string {
            if char.isWhitespace || char.isNewline {
                if !inWhitespace && !result.isEmpty {
                    result.append(" ")
                    inWhitespace = true
                }
            } else {
                result.append(char)
                inWhitespace = false
            }
        }
        // Trim trailing space if present
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// Map a character offset in normalized text back to a range in the original text.
    private static func mapNormalizedRange(
        offset: Int, length: Int, in text: String
    ) -> Range<String.Index>? {
        var nPos = 0, idx = text.startIndex, inWS = false

        // Advance to normalized offset
        while idx < text.endIndex, nPos < offset {
            if text[idx].isWhitespace {
                if !inWS { nPos += 1; inWS = true }
            } else { nPos += 1; inWS = false }
            idx = text.index(after: idx)
        }
        // Skip leading whitespace at match position
        while idx < text.endIndex, text[idx].isWhitespace { idx = text.index(after: idx) }
        let start = idx

        // Consume normalized length
        var consumed = 0; inWS = false
        while idx < text.endIndex, consumed < length {
            if text[idx].isWhitespace {
                if !inWS { consumed += 1; inWS = true }
            } else { consumed += 1; inWS = false }
            idx = text.index(after: idx)
        }
        return start..<idx
    }

    /// Build a result from a range, computing the UTF-16 offset.
    private static func makeResult(
        range: Range<String.Index>,
        confidence: QuoteConfidence,
        text: String
    ) -> QuoteRecoveryResult {
        let utf16Offset = text.utf16.distance(
            from: text.utf16.startIndex,
            to: range.lowerBound.samePosition(in: text.utf16) ?? text.utf16.startIndex
        )
        return QuoteRecoveryResult(
            matchRange: range,
            utf16Offset: utf16Offset,
            confidence: confidence
        )
    }
}
