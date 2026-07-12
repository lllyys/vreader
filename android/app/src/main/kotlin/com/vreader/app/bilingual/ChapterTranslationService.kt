// Purpose: feature #131 WI-3 — translates one chapter/document unit for Android
// bilingual reading (parity with iOS ChapterTranslationService.swift). The
// host-agnostic segment→chunk→translate→decode→per-segment-fallback→cache pipeline.
// A cache HIT returns the stored segments with zero AiClient calls; a MISS segments
// the source (paragraph granularity in v1), chunks it under a char budget, sends one
// one-shot AiClient.chat per chunk, strictly decodes the JSON string-array, falls
// back to one-request-per-segment on a decode failure, degrades a single failed chunk
// to source-only (and does NOT cache a partial result — a re-read retries the gap),
// and caches the recombined translation only on FULL success.
//
// Key decisions (mirroring iOS):
// - ChapterTranslationError is a sealed *value* type (WI-1), not a Throwable, so the
//   service raises [ChapterTranslationException] wrapping it — callers branch on
//   `.error`. `from()` is the AiError→ChapterTranslationError mapper.
// - Dual cancellation (iOS ChapterTranslationService.swift:359-364, M2): BOTH a native
//   CancellationException AND a typed ChapterTranslationException(Cancelled) thrown by
//   a chunk are re-raised as Cancelled BEFORE the generic degrade — a cancel aborts the
//   whole translation and is NEVER degraded-and-cached.
// - ensureActive() runs between chunks AND immediately before the Room write, so a
//   cancel right before the upsert leaves no row.
// - A partially-degraded result is NOT cached (iOS Bug #330); a cache-write failure
//   does NOT fail the translation (rule 50 §6). translatePreSegmented caches the
//   fully-successful result under the ENUMERATE's count (iOS Bug #343) so a
//   toggle/reopen restores via cachedTranslation(expectedSegmentCount) with zero
//   provider calls.
//
// @coordinates-with: ChapterTranslationStore.kt, ChapterSegmenter.kt,
//   TranslationChunker.kt, TranslationChunkContract.kt, ChapterTranslationError.kt,
//   com.vreader.app.ai.AiClient / AiRequest, AiProviderProfile,
//   iOS vreader/Services/AI/ChapterTranslationService.swift,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-3)
package com.vreader.app.bilingual

import com.vreader.app.ai.AiClient
import com.vreader.app.ai.AiMessage
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiRole
import com.vreader.app.ai.AiRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** The outcome of translating one unit. */
data class ChapterTranslationResult(
    /** One translated segment per source segment, in order. */
    val segments: List<String>,
    /** True when served entirely from the disk cache (no provider call). */
    val fromCache: Boolean,
)

/**
 * The throwable carrier for the [ChapterTranslationError] value type — the sealed
 * error is not itself a Throwable, so the service raises this and callers read
 * [error]. [cause] carries the original throwable for logging when there was one.
 */
class ChapterTranslationException(
    val error: ChapterTranslationError,
    cause: Throwable? = null,
) : Exception(
    when (error) {
        is ChapterTranslationError.ProviderFailed -> error.message
        ChapterTranslationError.Offline -> "offline"
        ChapterTranslationError.TimedOut -> "timed out"
        ChapterTranslationError.Cancelled -> "cancelled"
    },
    cause,
)

/**
 * Translates one chapter/document unit into a target language with a provider-aware
 * disk cache. All AI is reached through the injected [aiClient] (the #118 seam; the
 * fake in tests). [promptVersion] is the cache-identity component — v1 is
 * `bilingual-v1|g=paragraph`.
 */
class ChapterTranslationService(
    private val aiClient: AiClient,
    private val store: ChapterTranslationStore,
    private val promptVersion: String,
    private val maxCharsPerChunk: Int = DEFAULT_MAX_CHARS_PER_CHUNK,
) {

    /**
     * A CACHE-ONLY lookup that needs NO provider (iOS Bug #306). Serves the canonical
     * row only when its stored `sourceParagraphCount` still matches the source
     * re-segmented into [granularity] segments — or when [acceptCountMismatch] is set
     * (self-healing consumers that carry the enumerate contract). Returns null on a
     * miss or a strict count mismatch.
     */
    suspend fun cachedTranslation(
        bookKey: String,
        unit: TranslationUnitId,
        sourceText: String,
        targetLanguage: String,
        granularity: TranslationGranularity = TranslationGranularity.paragraph,
        acceptCountMismatch: Boolean = false,
    ): ChapterTranslationResult? {
        val key = lookupKey(bookKey, unit, targetLanguage)
        val cached = store.translation(key) ?: return null
        val segments = segment(sourceText, granularity)
        if (cached.sourceParagraphCount != segments.size && !acceptCountMismatch) return null
        return ChapterTranslationResult(cached.translatedSegments, fromCache = true)
    }

    /**
     * The divergence-fallback restore (iOS Bug #343): serves the canonical row only
     * when its STORED `sourceParagraphCount` equals [expectedSegmentCount] (the
     * caller's own structure — e.g. a DOM enumerate's block count), so
     * blocks↔segments pair 1:1 by contract. Needs NO source text and NO provider → a
     * cache hit restores with zero provider calls.
     */
    suspend fun cachedTranslation(
        bookKey: String,
        unit: TranslationUnitId,
        expectedSegmentCount: Int,
        targetLanguage: String,
    ): ChapterTranslationResult? {
        val key = lookupKey(bookKey, unit, targetLanguage)
        val cached = store.translation(key) ?: return null
        if (cached.sourceParagraphCount != expectedSegmentCount) return null
        return ChapterTranslationResult(cached.translatedSegments, fromCache = true)
    }

    /**
     * Translates [sourceText] into [targetLanguage]. Serves from cache on a hit; on a
     * miss segments (paragraph granularity in v1) → chunks → per-chunk one-shot
     * requests → strict decode → per-segment fallback → per-chunk graceful degrade →
     * cache-write on FULL success only. Raises [ChapterTranslationException] on a
     * provider failure or cancellation. When [bypassCacheRead] is set the cache read
     * is skipped (an explicit re-translate) — the write still runs and replaces the
     * row in place.
     */
    suspend fun translate(
        bookKey: String,
        unit: TranslationUnitId,
        sourceText: String,
        targetLanguage: String,
        providerProfile: AiProviderProfile,
        granularity: TranslationGranularity = TranslationGranularity.paragraph,
        bypassCacheRead: Boolean = false,
    ): ChapterTranslationResult {
        val key = lookupKey(bookKey, unit, targetLanguage)
        // Segment FIRST — the count is needed to detect a stale cache row.
        val segments = segment(sourceText, granularity)

        if (!bypassCacheRead) {
            val cached = store.translation(key)
            if (cached != null) {
                if (cached.sourceParagraphCount == segments.size) {
                    return ChapterTranslationResult(cached.translatedSegments, fromCache = true)
                }
                // Stale (source changed): drop the row and re-translate. A delete
                // failure does not block re-translation — the later upsert refreshes
                // the same key regardless.
                runCatching { store.delete(key) }
            }
        }

        if (segments.isEmpty()) {
            return ChapterTranslationResult(emptyList(), fromCache = false)
        }

        val translated = translateSegments(segments, targetLanguage, providerProfile)

        // ensureActive() before the write: a cancel right before the upsert leaves no row.
        currentCoroutineContext().ensureActive()
        if (!translated.hadDegrade) {
            writeCache(bookKey, unit, targetLanguage, providerProfile, translated.segments, segments.size)
        }
        return ChapterTranslationResult(translated.segments, fromCache = false)
    }

    /**
     * Translates a PRE-SEGMENTED list of source segments directly (iOS Bug #268/#330/
     * #343), bypassing [ChapterSegmenter] — the caller's OWN enumerated block texts
     * pair 1:1 with the result by construction. Same per-chunk graceful degrade +
     * dual-cancellation contract as [translate]; on FULL success only, caches under
     * the canonical key with the ENUMERATE's count as `sourceParagraphCount`. A
     * partial degrade is NOT cached; a cache-write failure does not fail the
     * translation. Returns a list the same length as [segments].
     */
    suspend fun translatePreSegmented(
        bookKey: String,
        unit: TranslationUnitId,
        segments: List<String>,
        targetLanguage: String,
        providerProfile: AiProviderProfile,
    ): List<String> {
        if (segments.isEmpty()) return emptyList()

        val translated = translateSegments(segments, targetLanguage, providerProfile)

        currentCoroutineContext().ensureActive()
        if (!translated.hadDegrade) {
            writeCache(bookKey, unit, targetLanguage, providerProfile, translated.segments, segments.size)
        }
        return translated.segments
    }

    // ── internals ─────────────────────────────────────────────

    private data class ChunkedTranslation(val segments: List<String>, val hadDegrade: Boolean)

    /**
     * Chunks [segments], translates each chunk with the dual-cancellation + graceful
     * per-chunk degrade contract, and recombines in source order. Throws on
     * cancellation (native or typed) and on an all-chunks-failure. Returns the
     * recombined segments plus whether ANY chunk degraded (source-only) — a degraded
     * result is never cached by the callers.
     */
    private suspend fun translateSegments(
        segments: List<String>,
        targetLanguage: String,
        providerProfile: AiProviderProfile,
    ): ChunkedTranslation {
        val chunks = TranslationChunker.chunk(segments, maxCharsPerChunk)
        val translated = MutableList(segments.size) { "" }

        var anyChunkSucceeded = false
        var hadDegrade = false
        var lastChunkError: ChapterTranslationException? = null

        for (chunk in chunks) {
            // Between-chunk cancellation → typed Cancelled.
            try {
                currentCoroutineContext().ensureActive()
            } catch (e: CancellationException) {
                throw ChapterTranslationException(ChapterTranslationError.Cancelled, e)
            }

            val chunkSegments = chunk.map { segments[it] }
            try {
                val chunkResult = translateChunk(chunkSegments, targetLanguage, providerProfile)
                for ((offset, segmentIndex) in chunk.withIndex()) {
                    translated[segmentIndex] = chunkResult[offset]
                }
                anyChunkSucceeded = true
            } catch (e: CancellationException) {
                // Native coroutine cancellation → abort as Cancelled (BEFORE degrade).
                throw ChapterTranslationException(ChapterTranslationError.Cancelled, e)
            } catch (e: ChapterTranslationException) {
                // A typed Cancelled from a chunk must ABORT, not degrade (M2).
                if (e.error is ChapterTranslationError.Cancelled) throw e
                // Any other typed failure → degrade this chunk to source-only, continue.
                hadDegrade = true
                lastChunkError = e
            }
        }

        // If EVERY chunk failed (a genuine outage, not one over-budget chunk),
        // surface the error rather than returning an all-source-only result.
        if (!anyChunkSucceeded && lastChunkError != null) throw lastChunkError
        return ChunkedTranslation(translated, hadDegrade)
    }

    /**
     * Translates one chunk: a single whole-chunk request with a strict JSON-array
     * decode; on any decode / count mismatch, falls back to one request per segment.
     * A single over-budget segment is sub-split into ≤budget pieces and rejoined.
     */
    private suspend fun translateChunk(
        chunkSegments: List<String>,
        targetLanguage: String,
        providerProfile: AiProviderProfile,
    ): List<String> {
        // An oversized SINGLE segment (its own chunk, not sub-split by the chunker) is
        // sub-split into ≤budget pieces, translated piece by piece, and rejoined into
        // the one segment's translation.
        if (chunkSegments.size == 1) {
            val pieces = TranslationChunker.subSplit(chunkSegments[0], maxCharsPerChunk)
            if (pieces.size > 1) {
                val joined = StringBuilder()
                for (piece in pieces) {
                    currentCoroutineContext().ensureActive()
                    val response = send(TranslationChunkContract.userPrompt(listOf(piece), targetLanguage), providerProfile)
                    joined.append(decodeOrRaw(response, expectedCount = 1).single())
                }
                return listOf(joined.toString())
            }
        }

        val response = send(TranslationChunkContract.userPrompt(chunkSegments, targetLanguage), providerProfile)
        runCatching { TranslationChunkContract.decode(response, expectedCount = chunkSegments.size) }
            .getOrNull()
            ?.let { return it }

        // Decode failed → per-segment fallback (still under the same provider).
        val perSegment = ArrayList<String>(chunkSegments.size)
        for (segment in chunkSegments) {
            currentCoroutineContext().ensureActive()
            val oneResponse = send(TranslationChunkContract.userPrompt(listOf(segment), targetLanguage), providerProfile)
            perSegment.add(decodeOrRaw(oneResponse, expectedCount = 1).single())
        }
        return perSegment
    }

    /** Decodes to [expectedCount] strings, or falls back to the raw (trimmed) text. */
    private fun decodeOrRaw(raw: String, expectedCount: Int): List<String> =
        runCatching { TranslationChunkContract.decode(raw, expectedCount) }
            .getOrElse { List(expectedCount) { raw.trim() } }

    /**
     * Issues one one-shot request, mapping a transport failure to a typed
     * [ChapterTranslationException]. A native CancellationException propagates
     * (cooperative cancellation); a typed [ChapterTranslationException] is rethrown
     * as-is; any other throwable maps via [ChapterTranslationError.from].
     */
    private suspend fun send(prompt: String, providerProfile: AiProviderProfile): String {
        val request = AiRequest(
            model = providerProfile.model.ifBlank { providerProfile.kind.defaultModel },
            messages = listOf(AiMessage(AiRole.user, prompt)),
            temperature = providerProfile.temperature,
            maxTokens = providerProfile.maxTokens,
        )
        return try {
            aiClient.chat(request).text
        } catch (e: CancellationException) {
            throw e
        } catch (e: ChapterTranslationException) {
            throw e
        } catch (e: Throwable) {
            throw ChapterTranslationException(ChapterTranslationError.from(e), e)
        }
    }

    private fun segment(sourceText: String, granularity: TranslationGranularity): List<String> =
        when (granularity) {
            TranslationGranularity.paragraph -> ChapterSegmenter.paragraphs(sourceText)
            TranslationGranularity.sentence -> ChapterSegmenter.sentences(sourceText)
        }

    private fun lookupKey(bookKey: String, unit: TranslationUnitId, targetLanguage: String): String =
        CachedTranslation.lookupKey(bookKey, unit.storageKey, targetLanguage, promptVersion)

    /** Writes the canonical row. A store-write failure does not fail the translation. */
    private suspend fun writeCache(
        bookKey: String,
        unit: TranslationUnitId,
        targetLanguage: String,
        @Suppress("UNUSED_PARAMETER") providerProfile: AiProviderProfile,
        segments: List<String>,
        sourceParagraphCount: Int,
    ) {
        runCatching {
            store.upsert(
                CachedTranslation(
                    bookKey = bookKey,
                    unitStorageKey = unit.storageKey,
                    targetLanguage = targetLanguage,
                    promptVersion = promptVersion,
                    translatedSegments = segments,
                    sourceParagraphCount = sourceParagraphCount,
                    createdAt = System.currentTimeMillis(),
                ),
            )
        }
    }

    companion object {
        /**
         * The per-chunk character budget — conservative, well under any mainstream
         * provider's context window so a chunk + its prompt scaffold fit comfortably.
         */
        const val DEFAULT_MAX_CHARS_PER_CHUNK = 6000
    }
}
