// Purpose: The strict JSON-array prompt + decode contract for feature #56
// bilingual chapter translation. The model is instructed to return ONLY a JSON
// array of N translated strings in source order; the decoder strictly
// validates that the response is exactly that — N string elements.
//
// Key decisions:
// - `AIRequest` has no API-level `response_format` field (verified), so the
//   "return only a JSON array" contract is prompt-level + strict JSON decode
//   (v4 Gate-2 finding F5 — rare-delimiter splitting was rejected because the
//   model can reproduce any delimiter; a JSON-array schema is unambiguous).
// - The decoder tolerates a leading/trailing ```json fence and surrounding
//   whitespace (models add them), but is strict about the element count and
//   that every element is a string — anything else throws so the caller
//   (`ChapterTranslationService`) falls back to one-segment-per-request.
// - `style` is folded into the prompt HERE and only here (Gate-2 round-2 N4).
//
// @coordinates-with: ChapterSegmenter.swift, ChapterTranslationChunker.swift,
//   ChapterTranslationService.swift, TranslationStyle.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Foundation

/// Builds the chunk translation prompt and strictly decodes the response.
enum TranslationChunkContract {

    /// A decode failure — surfaced so the service can fall back to a
    /// one-segment-per-request retry.
    enum DecodeError: Error, Equatable {
        /// The response was not a JSON array of strings.
        case notAStringArray
        /// The array length did not equal the expected segment count.
        case countMismatch(expected: Int, actual: Int)
    }

    /// Builds the `userPrompt` for one chunk of source segments. The model is
    /// told to translate each segment into `targetLanguage` in the given
    /// `style` and return ONLY a JSON array of exactly N strings, same order.
    static func userPrompt(
        segments: [String],
        targetLanguage: String,
        style: TranslationStyle
    ) -> String {
        let count = segments.count
        let styleClause: String
        switch style {
        case .literal:
            styleClause = "Use a LITERAL, word-for-word translation that stays "
                + "close to the source sentence structure."
        case .natural:
            styleClause = "Use NATURAL, idiomatic \(targetLanguage) phrasing that "
                + "reads fluently to a native speaker."
        case .literary:
            styleClause = "Use a LITERARY, polished translation with elevated, "
                + "well-crafted \(targetLanguage) prose."
        }

        // Number the segments so the model's array ordering is unambiguous.
        let numbered = segments.enumerated()
            .map { "[\($0.offset)] \($0.element)" }
            .joined(separator: "\n\n")

        return """
        Translate each of the following \(count) text segment(s) into \(targetLanguage).
        \(styleClause)

        Respond with ONLY a JSON array of exactly \(count) string(s) — the \
        translation of each segment, in the same order. No commentary, no keys, \
        no markdown — just the JSON array.

        Source segments:
        \(numbered)
        """
    }

    /// Strictly decodes a model response into exactly `expectedCount`
    /// translated strings. Tolerates a surrounding ```json fence and
    /// whitespace; throws `DecodeError` on anything that is not a JSON array
    /// of exactly that many string elements.
    static func decode(_ raw: String, expectedCount: Int) throws -> [String] {
        let cleaned = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw DecodeError.notAStringArray
        }
        let decoded: [String]
        do {
            decoded = try JSONDecoder().decode([String].self, from: data)
        } catch {
            // Decodes-but-not-as-[String] (object, number element, nested
            // array, …) → not a string array.
            throw DecodeError.notAStringArray
        }
        guard decoded.count == expectedCount else {
            throw DecodeError.countMismatch(expected: expectedCount, actual: decoded.count)
        }
        return decoded
    }

    /// Removes a leading/trailing Markdown code fence (```json … ``` or ``` … ```).
    ///
    /// The closing fence is removed ONLY when the final non-whitespace line is
    /// exactly ```` ``` ````. A bare ```` ``` ```` occurring *inside* the
    /// payload (e.g. a JSON string element that literally contains backticks)
    /// is left intact — searching backwards for any backtick run would
    /// truncate such a legitimate payload (Gate-4 round-1 Medium).
    private static func stripCodeFence(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }

        var lines = text.components(separatedBy: "\n")
        // Drop the opening fence line (``` or ```json). With no newline at all
        // the input is just a lone fence — nothing to unwrap.
        guard lines.count > 1 else { return text }
        lines.removeFirst()

        // Drop the closing fence only if the LAST non-blank line is exactly ```.
        if let lastNonBlankIndex = lines.lastIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }), lines[lastNonBlankIndex].trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeSubrange(lastNonBlankIndex...)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
