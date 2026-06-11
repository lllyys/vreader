// Purpose: Pure segmentation utility for feature #56 bilingual reading. Splits
// a chapter's plain text into translation segments — either paragraphs or
// sentences, selected by the book's `granularity` setting (design §2.2).
//
// Key decisions:
// - Paragraph split is blank-line / block-boundary based: a single newline is
//   a soft wrap (same paragraph), a blank line separates paragraphs.
// - Sentence split uses `String.enumerateSubstrings(.bySentences)`, which is
//   locale-aware and handles CJK fullwidth terminators (。！？) as well as
//   Latin punctuation — no manual punctuation table.
// - Every produced segment is whitespace-trimmed and empty segments dropped,
//   so a translation request never carries a blank segment.
//
// @coordinates-with: ChapterTranslationChunker.swift,
//   ChapterTranslationService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Foundation

/// Pure paragraph / sentence segmentation for chapter translation.
enum ChapterSegmenter {

    /// Splits chapter text into paragraphs. Paragraphs are separated by one or
    /// more blank lines; a single line break inside a paragraph is a soft wrap
    /// and does not split. Each paragraph is trimmed; empty ones are dropped.
    static func paragraphs(in chapterText: String) -> [String] {
        // Bug #344 (Gate-4 Medium): derive from the SAME range scanner the
        // TXT/MD display side uses, so the blank-line definition can never
        // diverge between the two sides of the 1:1 contract. The old regex
        // split only on `\\n[ \\t]*\\n+`, while the display scanner treats ANY
        // whitespace-only line (incl. U+3000 / U+00A0 — common in CJK
        // files) as a separator — that divergence made the display side
        // count MORE paragraphs than the translation side and paint
        // source-only. Each scan range contains at least one
        // non-whitespace character by construction, so trimming never
        // yields an empty (and no filter is applied — a filter could
        // re-introduce a count skew against the raw ranges).
        let ns = chapterText as NSString
        return BilingualParagraphRanges.scan(sourceText: chapterText).map {
            ns.substring(with: NSRange(
                location: $0.lowerBound, length: $0.upperBound - $0.lowerBound))
                // Preserve the pre-#344 contract: soft-wrap line endings
                // inside a paragraph normalize to \n (Gate-4 round 2 —
                // translation prompts + cached rows carried \n, never \r\n).
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Splits chapter text into sentences. CJK-aware via
    /// `enumerateSubstrings(.bySentences)`. Each sentence is trimmed; empty
    /// fragments are dropped.
    static func sentences(in chapterText: String) -> [String] {
        var result: [String] = []
        let full = chapterText.startIndex..<chapterText.endIndex
        chapterText.enumerateSubstrings(in: full, options: [.bySentences, .localized]) {
            substring, _, _, _ in
            guard let substring else { return }
            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append(trimmed)
            }
        }
        // `.bySentences` on a fragment with no terminal punctuation still
        // yields the fragment; only a fully-empty input yields nothing.
        return result
    }

    /// Bug #344: UTF-16 half-open ranges of each sentence (trimmed bounds),
    /// in source order — the display-side twin of `sentences(in:)`.
    ///
    /// COUNT-PARITY CONTRACT: `sentenceRanges(in: s).count ==
    /// sentences(in: s).count` for every input. Both walk the same
    /// `.bySentences` enumeration with the same trim + drop-empty rules, so
    /// the TXT/MD sentence-interlinear renderer and the translation
    /// segmentation pair 1:1 by construction (the #266/#343 contract).
    static func sentenceRanges(in chapterText: String) -> [Range<Int>] {
        var result: [Range<Int>] = []
        let full = chapterText.startIndex..<chapterText.endIndex
        let whitespace = CharacterSet.whitespacesAndNewlines
        chapterText.enumerateSubstrings(in: full, options: [.bySentences, .localized]) {
            substring, substringRange, _, _ in
            guard let substring else { return }
            let nsRange = NSRange(substringRange, in: chapterText)
            // Shrink the range to the trimmed bounds so the interlinear row
            // lands flush after the sentence's last visible character —
            // mirroring `sentences(in:)`'s trim. Surrogate halves are never
            // whitespace, so per-UTF-16-unit scanning is safe.
            let units = Array(substring.utf16)
            var lead = 0
            while lead < units.count,
                  let scalar = Unicode.Scalar(UInt32(units[lead])),
                  whitespace.contains(scalar) {
                lead += 1
            }
            var trail = 0
            while trail < units.count - lead,
                  let scalar = Unicode.Scalar(UInt32(units[units.count - 1 - trail])),
                  whitespace.contains(scalar) {
                trail += 1
            }
            let start = nsRange.location + lead
            let end = nsRange.location + nsRange.length - trail
            // Whitespace-only fragments trim to nothing — `sentences(in:)`
            // drops them, so the range scanner must too (count parity).
            guard start < end else { return }
            result.append(start..<end)
        }
        return result
    }

}
