// Purpose: feature #131 WI-4a — the bilingual prefetch coordinator. Resolves the
// active AI provider from a SINGLE AiProviderStore.snapshot() (so a chat/test can't
// pair snapshot metadata with a concurrently-edited/deleted key — AiProviderStore.kt
// §snapshot), decrypts the key snapshot-consistent via store.apiKey(profile), builds
// an AiClient via an INJECTED factory (default AiProviderFactory::create), builds a
// ChapterTranslationService bound to that client, and translates a unit.
//
// Three entry points (iOS ChapterTranslationPrefetcher parity):
//  - prefetch(unit)                         — the plain-text path (segments from the provider).
//  - prefetchDirect(unit, segments, lang)   — the count-divergence direct-block path (iOS #268/#330/#343).
//  - cachedDirect(unit, expectedCount, lang) — the ZERO-PROVIDER cache-only restore (iOS #306):
//        returns a cached translation on a hit WITHOUT an active provider.
//
// #306: a cache HIT still returns even with NO active provider (the setup can be
// gone / not-yet-configured but a prior translation is on disk). A cache MISS with no
// active provider maps to ProviderFailed. Cipher/decrypt failure while resolving the
// key maps to ProviderFailed, never a crash. AiRequest.model uses the M3 blank-model
// fallback `profile.model.ifBlank { profile.kind.defaultModel }` (the service builds
// the request, so the fallback is exercised there via the profile passed through).
//
// @coordinates-with: ChapterTextProvider.kt, ChapterTranslationService.kt,
//   ChapterTranslationError.kt, com.vreader.app.ai.AiProviderStore /
//   AiProviderFactory / AiClient / AiProviderProfile,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-4a)
package com.vreader.app.bilingual

import com.vreader.app.ai.AiClient
import com.vreader.app.ai.AiProviderFactory
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiProviderStore
import kotlinx.coroutines.CancellationException

/**
 * Coordinates cache-first bilingual translation for one book. [bookKey] is the book's
 * fingerprint key; [textProvider] enumerates a unit's source segments; [store] resolves
 * the active provider; [clientFactory] builds the transport client from the resolved
 * profile + decrypted key (default [AiProviderFactory.create]); [serviceFactory] wires
 * that client into a [ChapterTranslationService].
 */
class ChapterTranslationPrefetcher(
    private val bookKey: String,
    private val textProvider: ChapterTextProvider,
    private val store: AiProviderStore,
    private val serviceFactory: (AiClient) -> ChapterTranslationService,
    private val clientFactory: (AiProviderProfile, String) -> AiClient = AiProviderFactory::create,
) {

    /**
     * Translates [unit]'s source text into [targetLanguage] via the active provider,
     * serving from cache on a hit (inside the service). When there is NO active
     * provider a cache hit still returns (#306); a cache miss maps to
     * [ChapterTranslationError.ProviderFailed]. A cipher/decrypt failure maps to
     * ProviderFailed (never a crash). [granularity] is paragraph in v1.
     */
    suspend fun prefetch(
        unit: TranslationUnitId,
        targetLanguage: String,
        granularity: TranslationGranularity = TranslationGranularity.paragraph,
    ): ChapterTranslationResult {
        val sourceText = textProvider.sourceText(unit)
        // Cache-FIRST (the class's contract): a valid cache hit must NOT depend on a
        // healthy cipher/provider or incur any provider work. Only a cache MISS resolves
        // and builds the provider. This also serves the #306 no-provider hit for free.
        cacheOnlyService()
            .cachedTranslation(bookKey, unit, sourceText, targetLanguage, granularity)
            ?.let { return it }

        val resolved = resolveProvider() ?: throw ChapterTranslationException(
            ChapterTranslationError.ProviderFailed("no AI provider configured"),
        )
        // The cache was just read (a miss) — skip the redundant read; the write still runs.
        return serviceFactory(resolved.client)
            .translate(bookKey, unit, sourceText, targetLanguage, resolved.profile, granularity, bypassCacheRead = true)
    }

    /**
     * Translates a PRE-SEGMENTED [sourceSegments] list directly (the divergence path —
     * the caller's OWN enumerated blocks pair 1:1 with the result). Serves a cache hit
     * with no provider (#306, keyed on the enumerate's count); a cache miss with no
     * provider maps to ProviderFailed. Returns a list the same length as [sourceSegments].
     */
    suspend fun prefetchDirect(
        unit: TranslationUnitId,
        sourceSegments: List<String>,
        targetLanguage: String,
    ): List<String> {
        // Cache-FIRST, keyed on the enumerate's count (the direct 1:1 contract): a hit
        // returns with no provider (#306) and never touches the cipher/factory.
        cacheOnlyService()
            .cachedTranslation(bookKey, unit, expectedSegmentCount = sourceSegments.size, targetLanguage = targetLanguage)
            ?.let { return it.segments }

        val resolved = resolveProvider() ?: throw ChapterTranslationException(
            ChapterTranslationError.ProviderFailed("no AI provider configured"),
        )
        return serviceFactory(resolved.client)
            .translatePreSegmented(bookKey, unit, sourceSegments, targetLanguage, resolved.profile)
    }

    /**
     * A ZERO-PROVIDER cache-only restore (#306 / iOS Bug #343): returns the cached
     * translation on a hit whose stored source-segment count equals [expectedCount],
     * WITHOUT requiring — or building — any provider client. Returns null on a miss.
     * Never calls [clientFactory] or [store].snapshot().
     */
    suspend fun cachedDirect(
        unit: TranslationUnitId,
        expectedCount: Int,
        targetLanguage: String,
    ): ChapterTranslationResult? =
        cacheOnlyService()
            .cachedTranslation(bookKey, unit, expectedSegmentCount = expectedCount, targetLanguage = targetLanguage)

    // ── internals ─────────────────────────────────────────────

    private class ResolvedProvider(val profile: AiProviderProfile, val client: AiClient)

    /**
     * Resolves the active provider from ONE snapshot + a snapshot-consistent key
     * decrypt, then builds the client via [clientFactory]. Returns null when there is
     * no active profile. A cipher/decrypt failure (or a factory failure) maps to
     * [ChapterTranslationError.ProviderFailed] — never a crash. A CancellationException
     * propagates (cooperative cancellation is not a provider failure).
     */
    private suspend fun resolveProvider(): ResolvedProvider? {
        val profile = store.snapshot().active ?: return null
        val apiKey = try {
            store.apiKey(profile)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            throw ChapterTranslationException(
                ChapterTranslationError.ProviderFailed("provider key unavailable"),
                e,
            )
        }
        val client = try {
            clientFactory(profile, apiKey)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            throw ChapterTranslationException(
                ChapterTranslationError.ProviderFailed("could not build the AI client"),
                e,
            )
        }
        return ResolvedProvider(profile, client)
    }

    /**
     * A service used ONLY for cache-only lookups (its client is never called on the
     * cache path). Built via [serviceFactory] with a sentinel client that throws if a
     * cache path ever reaches the provider — a defensive assertion, not a live client.
     */
    private fun cacheOnlyService(): ChapterTranslationService =
        serviceFactory(NeverCalledAiClient)

    private object NeverCalledAiClient : AiClient {
        override fun streamChat(request: com.vreader.app.ai.AiRequest) =
            throw IllegalStateException("cache-only path must not reach the provider")
        override suspend fun chat(request: com.vreader.app.ai.AiRequest) =
            throw IllegalStateException("cache-only path must not reach the provider")
        override suspend fun testConnection() =
            throw IllegalStateException("cache-only path must not reach the provider")
    }
}
