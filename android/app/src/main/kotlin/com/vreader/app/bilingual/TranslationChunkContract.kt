// Purpose: feature #131 WI-1 - the strict JSON-array prompt + decode contract for
// bilingual chapter translation. Port of iOS TranslationChunkContract.swift. The
// model is instructed to return ONLY a JSON array of N translated strings in
// source order; the decoder strictly validates that the response is exactly that.
//
// Key decisions (mirroring iOS):
// - No API-level response_format field, so the "return only a JSON array"
//   contract is prompt-level + strict JSON decode.
// - style is DESCOPED in v1 (Android) - the prompt carries NO style clause
//   (iOS had one; the Android v1 render path does not).
// - The decoder tolerates a leading/trailing ```json fence and surrounding
//   whitespace (models add them) but is strict about the element count and that
//   every element is a string - anything else throws DecodeError so the caller
//   falls back to one-segment-per-request.
// - stripCodeFence removes the closing fence ONLY when the final non-blank line
//   is exactly ``` - a bare ``` INSIDE a JSON string element is left intact.
//
// @coordinates-with: ChapterSegmenter.kt, TranslationChunker.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1),
//   iOS vreader/Services/AI/TranslationChunkContract.swift
package com.vreader.app.bilingual

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

/** Builds the chunk translation prompt and strictly decodes the response. */
object TranslationChunkContract {

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * A decode failure - surfaced (thrown) so the service can fall back to a
     * one-segment-per-request retry. Sealed so callers can exhaustively branch.
     */
    sealed class DecodeError(message: String) : Exception(message) {
        /** The response was not a JSON array of strings. */
        object NotAStringArray : DecodeError("response was not a JSON array of strings")

        /** The array length did not equal the expected segment count. */
        data class CountMismatch(val expected: Int, val actual: Int) :
            DecodeError("expected $expected segment(s), got $actual")
    }

    /**
     * Builds the userPrompt for one chunk of source segments. The model is told
     * to translate each segment into [targetLanguage] and return ONLY a JSON
     * array of exactly N strings, same order. No style clause (v1 descope).
     */
    fun userPrompt(segments: List<String>, targetLanguage: String): String {
        val count = segments.size

        // Number the segments so the model's array ordering is unambiguous.
        val numbered = segments
            .mapIndexed { i, segment -> "[$i] $segment" }
            .joinToString(separator = "\n\n")

        return """
            Translate each of the following $count text segment(s) into $targetLanguage.

            Respond with ONLY a JSON array of exactly $count string(s) - the translation of each segment, in the same order. No commentary, no keys, no markdown - just the JSON array.

            Source segments:
            $numbered
        """.trimIndent()
    }

    /**
     * Strictly decodes a model response into exactly [expectedCount] translated
     * strings. Tolerates a surrounding ```json fence and whitespace; throws
     * [DecodeError] on anything that is not a JSON array of exactly that many
     * string elements.
     */
    @Throws(DecodeError::class)
    fun decode(raw: String, expectedCount: Int): List<String> {
        val cleaned = stripCodeFence(raw).trim()

        val element = try {
            json.parseToJsonElement(cleaned)
        } catch (e: Exception) {
            throw DecodeError.NotAStringArray
        }

        val array = element as? JsonArray ?: throw DecodeError.NotAStringArray

        // Every element must be a JSON string primitive (not a number, object,
        // nested array, or bare literal).
        val decoded = ArrayList<String>(array.size)
        for (item in array) {
            val primitive = item as? JsonPrimitive ?: throw DecodeError.NotAStringArray
            if (!primitive.isString) throw DecodeError.NotAStringArray
            decoded.add(primitive.content)
        }

        if (decoded.size != expectedCount) {
            throw DecodeError.CountMismatch(expected = expectedCount, actual = decoded.size)
        }
        return decoded
    }

    /**
     * Removes a leading/trailing Markdown code fence (```json ... ``` or ``` ...
     * ```). The closing fence is removed ONLY when the final non-whitespace line
     * is exactly ```. A bare ``` occurring INSIDE the payload (e.g. a JSON string
     * element that literally contains backticks) is left intact.
     */
    private fun stripCodeFence(raw: String): String {
        val text = raw.trim()
        if (!text.startsWith("```")) return text

        val lines = text.split("\n").toMutableList()
        // Drop the opening fence line (``` or ```json). With no newline the input
        // is just a lone fence - nothing to unwrap.
        if (lines.size <= 1) return text
        lines.removeAt(0)

        // Drop the closing fence only if the LAST non-blank line is exactly ```.
        val lastNonBlankIndex = lines.indexOfLast { it.trim().isNotEmpty() }
        if (lastNonBlankIndex >= 0 && lines[lastNonBlankIndex].trim() == "```") {
            while (lines.size > lastNonBlankIndex) lines.removeAt(lines.size - 1)
        }
        return lines.joinToString("\n").trim()
    }
}
