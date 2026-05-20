// Purpose: Tests for TranslationChunkContract — the strict JSON-array prompt +
// decode contract for feature #56 bilingual reading. The model is instructed to
// return ONLY a JSON array of N translated strings, same order; the decoder
// strictly validates count + element type.
//
// @coordinates-with: TranslationChunkContract.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Testing
import Foundation
@testable import vreader

@Suite("TranslationChunkContract")
struct TranslationChunkContractTests {

    // MARK: - Prompt builder

    @Test func prompt_includesTargetLanguage() {
        let prompt = TranslationChunkContract.userPrompt(
            segments: ["Hello."], targetLanguage: "Chinese", style: .natural)
        #expect(prompt.contains("Chinese"))
    }

    @Test func prompt_includesEverySourceSegment() {
        let segments = ["First segment.", "Second segment.", "Third."]
        let prompt = TranslationChunkContract.userPrompt(
            segments: segments, targetLanguage: "Japanese", style: .natural)
        for segment in segments {
            #expect(prompt.contains(segment))
        }
    }

    @Test func prompt_instructsJSONArrayOfExactCount() {
        let prompt = TranslationChunkContract.userPrompt(
            segments: ["a", "b", "c"], targetLanguage: "French", style: .natural)
        // The prompt must demand a JSON array and state the exact element count.
        #expect(prompt.lowercased().contains("json"))
        #expect(prompt.contains("3"))
    }

    @Test func prompt_foldsInTranslationStyle() {
        // The style is consumed ONLY here (Gate-2 round-2 N4) — it must appear
        // in the prompt text, distinctly per style.
        let literal = TranslationChunkContract.userPrompt(
            segments: ["x"], targetLanguage: "German", style: .literal)
        let literary = TranslationChunkContract.userPrompt(
            segments: ["x"], targetLanguage: "German", style: .literary)
        #expect(literal != literary)
        #expect(literal.lowercased().contains("literal"))
        #expect(literary.lowercased().contains("literary"))
    }

    // MARK: - Strict decode

    @Test func decode_wellFormedArrayMapsInOrder() throws {
        let json = #"["你好","世界","再见"]"#
        let result = try TranslationChunkContract.decode(json, expectedCount: 3)
        #expect(result == ["你好", "世界", "再见"])
    }

    @Test func decode_acceptsArrayWrappedInWhitespace() throws {
        let json = "  \n [\"a\", \"b\"] \n  "
        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
        #expect(result == ["a", "b"])
    }

    @Test func decode_stripsMarkdownCodeFence() throws {
        // Models often wrap JSON in ```json ... ``` — the decoder tolerates it.
        let json = "```json\n[\"alpha\", \"beta\"]\n```"
        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
        #expect(result == ["alpha", "beta"])
    }

    @Test func decode_countMismatchTooFewThrowsCountMismatch() {
        #expect(throws: TranslationChunkContract.DecodeError.countMismatch(expected: 3, actual: 1)) {
            _ = try TranslationChunkContract.decode(#"["only one"]"#, expectedCount: 3)
        }
    }

    @Test func decode_countMismatchTooManyThrowsCountMismatch() {
        #expect(throws: TranslationChunkContract.DecodeError.countMismatch(expected: 2, actual: 4)) {
            _ = try TranslationChunkContract.decode(#"["a","b","c","d"]"#, expectedCount: 2)
        }
    }

    @Test func decode_nonStringElementThrowsNotAStringArray() {
        // A numeric element is not a translated string.
        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
            _ = try TranslationChunkContract.decode(#"["ok", 42]"#, expectedCount: 2)
        }
    }

    @Test func decode_nestedArrayThrowsNotAStringArray() {
        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
            _ = try TranslationChunkContract.decode(#"[["nested"], "b"]"#, expectedCount: 2)
        }
    }

    @Test func decode_notAnArrayThrowsNotAStringArray() {
        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
            _ = try TranslationChunkContract.decode(#"{"text": "not an array"}"#, expectedCount: 1)
        }
    }

    @Test func decode_garbageThrowsNotAStringArray() {
        #expect(throws: TranslationChunkContract.DecodeError.notAStringArray) {
            _ = try TranslationChunkContract.decode("this is not json at all", expectedCount: 1)
        }
    }

    @Test func decode_emptyArrayWithExpectedZeroSucceeds() throws {
        let result = try TranslationChunkContract.decode("[]", expectedCount: 0)
        #expect(result.isEmpty)
    }

    @Test func decode_arrayWithEmptyStringElementsIsValid() throws {
        // An empty translated string is a valid element (model returned "" for
        // a blank source segment) — count still matters.
        let result = try TranslationChunkContract.decode(#"["", "real", ""]"#, expectedCount: 3)
        #expect(result == ["", "real", ""])
    }

    @Test func decode_preservesBackticksInsideAJSONStringElement() throws {
        // A JSON string element that legitimately contains ``` must NOT be
        // truncated by the code-fence stripper (Gate-4 round-1 Medium).
        let json = "```json\n[\"code: ```x```\", \"plain\"]\n```"
        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
        #expect(result == ["code: ```x```", "plain"])
    }

    @Test func decode_openingFenceWithNoClosingFenceStillDecodes() throws {
        // A fenced payload with no trailing ``` line — the opening fence is
        // dropped, the body still decodes.
        let json = "```json\n[\"a\", \"b\"]"
        let result = try TranslationChunkContract.decode(json, expectedCount: 2)
        #expect(result == ["a", "b"])
    }
}
