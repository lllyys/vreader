// Purpose: feature #131 WI-4b — the bilingual + AI-config DI holder, extracted from
// AppContainer to keep VReaderApp.kt under the ~300-line file-size bar (rule 50 §9).
// Groups the process-singleton bilingual stores + the AI readiness gate, plus the
// per-session factory functions (translation prefetcher, BilingualViewModel). The
// AiProviderStore itself is constructed by AppContainer (it owns the cipher + DataStore)
// and passed in, so this holder does not reach for a Context.
//
// Key decisions:
// - The AiProviderStore, ChapterTranslationStore, PerBookBilingualStore, and
//   BilingualAiReadiness are process-singletons (one per app process) — a config or
//   provider change propagates to whatever reader session is open.
// - The prefetcher + BilingualViewModel are PER-SESSION (one per open book / VM
//   lifetime), so they are factory functions, not singletons. The prefetcher's
//   clientFactory param is LEFT at its AiProviderFactory::create default (the seam is
//   wired but built lazily per translate request).
// - `promptVersion` is the v1 cache-identity component `bilingual-v1|g=paragraph`
//   (granularity paragraph-only in v1 — plan §"Cache-identity"); the service factory
//   pins it so every translation caches under the same key.
//
// @coordinates-with: com.vreader.app.AppContainer (VReaderApp.kt), AiProviderStore,
//   ChapterTranslationStore, PerBookBilingualStore, ChapterTranslationService,
//   ChapterTranslationPrefetcher, BilingualViewModel, BilingualAiReadiness,
//   com.vreader.app.data.ChapterTranslationDao,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-4b)
package com.vreader.app.bilingual

import com.vreader.app.ai.AiClient
import com.vreader.app.ai.AiProviderSnapshot
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.data.ChapterTranslationDao
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * Wires the bilingual + AI-config graph. [aiProviderStore] is constructed by AppContainer
 * (it owns the cipher + DataStore); [chapterTranslationDao] is the Room DAO; the
 * per-book-config store is created over a caller-provided DataStore (AppContainer owns the
 * noBackupFilesDir DataStore, mirroring readerSettingsStore).
 *
 * @param aiProviderStore the process-singleton provider store (from AppContainer).
 * @param chapterTranslationDao the Room DAO backing the translation cache.
 * @param perBookBilingualStore the per-book bilingual-config store (AppContainer-owned DataStore).
 * @param ioDispatcher the dispatcher for the BilingualViewModel's store I/O (Dispatchers.IO default).
 */
class BilingualServices(
    val aiProviderStore: AiProviderStore,
    chapterTranslationDao: ChapterTranslationDao,
    val perBookBilingualStore: PerBookBilingualStore,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {

    /** The coroutine cache boundary over the translation DAO (process-singleton). */
    val chapterTranslationStore: ChapterTranslationStore =
        ChapterTranslationStore(chapterTranslationDao)

    /** The provider+key readiness gate driving the bilingual setup-sheet's configured state. */
    val bilingualAiReadiness: BilingualAiReadiness = BilingualAiReadiness(aiProviderStore)

    /**
     * Builds a [ChapterTranslationService] bound to [client], pinned to the v1 promptVersion.
     * The service is the per-chunk translate + cache pipeline; its cache is the shared
     * [chapterTranslationStore]. Used both for the live translate path and the cache-only path.
     */
    private fun serviceFactory(client: AiClient): ChapterTranslationService =
        ChapterTranslationService(client, chapterTranslationStore, PROMPT_VERSION_V1)

    /**
     * A PER-SESSION [ChapterTranslationPrefetcher] for [bookKey] over [textProvider]. The
     * injected `clientFactory` is LEFT at its `AiProviderFactory::create` default — the
     * transport client is built lazily per translate request from the resolved profile.
     */
    fun prefetcher(
        bookKey: String,
        textProvider: ChapterTextProvider,
    ): ChapterTranslationPrefetcher =
        ChapterTranslationPrefetcher(
            bookKey = bookKey,
            textProvider = textProvider,
            store = aiProviderStore,
            serviceFactory = ::serviceFactory,
        )

    /**
     * A PER-SESSION [BilingualViewModel] for [bookKey] over [textProvider]. Wires the real
     * prefetcher, the live AI-provider snapshot provider (a single store.snapshot() read per
     * refresh — snapshot-consistency), and the readiness gate.
     */
    fun bilingualViewModel(
        bookKey: String,
        textProvider: ChapterTextProvider,
    ): BilingualViewModel =
        BilingualViewModel(
            bookKey = bookKey,
            store = perBookBilingualStore,
            prefetcher = prefetcher(bookKey, textProvider),
            snapshotProvider = { snapshot() },
            readiness = bilingualAiReadiness,
            dispatcher = ioDispatcher,
        )

    /** One consistent AI-provider snapshot for the VM's readiness refresh. */
    private suspend fun snapshot(): AiProviderSnapshot = aiProviderStore.snapshot()

    companion object {
        /**
         * The v1 cache-identity component `bilingual-v1|g=paragraph` (granularity is
         * paragraph-only in v1 — the `g=` slot is retained so a future granularity is a
         * distinct cache row by construction). Profile-agnostic / style-agnostic (Bug #342).
         */
        const val PROMPT_VERSION_V1 = "bilingual-v1|g=paragraph"
    }
}
