// Purpose: Application + manual DI container — feature #106 WI-8. Holds the
// process-singleton Room database, repository, and importer so the Library
// ViewModel gets shared instances (a Hilt module is a Phase-3 follow-on; manual
// wiring at the app edge keeps the foundation bar dependency-light — rule 50 §5).
package com.vreader.app

import android.app.Application
import android.content.Context
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.imports.IncomingBookResolver
import com.vreader.app.imports.IncomingImportCoordinator
import com.vreader.app.reader.BookOpener
import com.vreader.app.search.BookTextExtractor
import com.vreader.app.search.EpubTextExtractor
import com.vreader.app.search.asSearcher
import com.vreader.app.search.SearchIndexCoordinator
import com.vreader.app.search.TxtMdTextExtractor
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.ai.AiSettingsViewModel
import com.vreader.app.backup.net.KeystoreSecretCipher
import com.vreader.app.backup.net.SecretCipher
import com.vreader.app.bilingual.BilingualAiReadiness
import com.vreader.app.bilingual.BilingualServices
import com.vreader.app.bilingual.BilingualViewModel
import com.vreader.app.bilingual.ChapterTextProvider
import com.vreader.app.bilingual.ChapterTranslationPrefetcher
import com.vreader.app.bilingual.ChapterTranslationStore
import com.vreader.app.bilingual.PerBookBilingualStore
import com.vreader.app.stats.ReadingStatsRepository
import com.vreader.app.stats.ReadingTimeTracker
import com.vreader.app.stats.clock.SystemDateClock
import com.vreader.app.stats.clock.SystemElapsedClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.map
import vreader.contracts.BookFormat
import java.io.File

/**
 * Process-wide singletons, lazily built. [secretCipher] protects the AI provider API keys
 * at rest — the production default is a #116 [KeystoreSecretCipher] under a DISTINCT AI
 * alias (`vreader.ai.password`, separate from WebDAV/OPDS); it is injectable so the WI-4b
 * Robolectric wiring test can pass a fake (AndroidKeyStore is unavailable under Robolectric).
 * [prefsStoreFactory] builds a device-local Preferences DataStore from a backing file NAME;
 * the production default writes under noBackupFilesDir (the readerSettingsStore convention).
 * It is injectable so a test can record which file each store is bound to (a name clash would
 * make two subsystems overwrite each other's prefs).
 */
class AppContainer(
    context: Context,
    private val secretCipher: SecretCipher = KeystoreSecretCipher(AI_KEY_ALIAS),
    prefsStoreFactory: ((String) -> androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences>)? = null,
) {
    private val appContext = context.applicationContext

    /** Resolves the Preferences-DataStore factory: the injected one, or the noBackupFilesDir default. */
    private val prefsStore: (String) -> androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> =
        prefsStoreFactory ?: { fileName ->
            androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
                File(appContext.noBackupFilesDir, fileName)
            }
        }

    val database: VReaderDatabase by lazy { VReaderDatabase.build(appContext) }
    val repository: LibraryRepository by lazy {
        LibraryRepository(database.bookDao(), database.readingPositionDao())
    }

    /** App-private book storage — shared by the importer and the #155 inbound-import sweep. */
    private val booksDir: File = File(appContext.filesDir, "books")

    val importer: BookImporter by lazy { BookImporter(booksDir, repository) }

    // feature #122 — reading-stats. The repository + the time tracker are process-singletons so a
    // reading session survives the (shorter-lived) reader ViewModel / rotation. ONE shared DateClock
    // so the dashboard's "today" and the tracker's bucket dates can't drift apart.
    private val dateClock: SystemDateClock by lazy { SystemDateClock() }
    val statsRepository: ReadingStatsRepository by lazy {
        ReadingStatsRepository(database.readingStatsDao(), repository, dateClock)
    }
    val readingTimeTracker: ReadingTimeTracker by lazy {
        ReadingTimeTracker(statsRepository, SystemElapsedClock(), dateClock)
    }

    // feature #123 — annotations (EPUB highlights & notes). Process-singleton so the reader VM /
    // rotation share one instance (the statsRepository precedent).
    val annotationsRepository: AnnotationsRepository by lazy {
        AnnotationsRepository(database.annotationDao())
    }

    // feature #127 — library collections. Process-singleton (the annotationsRepository precedent).
    val collectionRepository: com.vreader.app.data.CollectionRepository by lazy {
        com.vreader.app.data.CollectionRepository(database.collectionDao())
    }

    // feature #129 — reader display settings. A device-local DataStore (the OpdsSourceStore /
    // AiProviderStore precedent), global (not per-book), process-singleton so a settings change
    // propagates to whatever reader is open. Stored under noBackupFilesDir — display prefs are
    // per-device (NOT in the backup contract), so they must be excluded from Android Auto Backup.
    internal val readerSettingsDataStore = prefsStore(READER_SETTINGS_PREFS)
    val readerSettingsStore: com.vreader.app.reader.settings.ReaderSettingsStore by lazy {
        com.vreader.app.reader.settings.ReaderSettingsStore(readerSettingsDataStore)
    }

    /** Process-lifetime scope for fire-and-forget writes that must outlive a screen
     *  (e.g. the reader's onStop position flush — it must finish even as the activity
     *  is being torn down). */
    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // feature #128 WI-5 — cross-book search index. The coordinator observes the library and
    // streams each indexable book (epub/txt/md) through the WI-3 extractors into WI-4's staging →
    // atomic publish. Eagerly started once from onCreate; pdf/azw3 map to null (never indexable).
    private val bookOpener: BookOpener by lazy { BookOpener(appContext) }
    private val epubTextExtractor: EpubTextExtractor by lazy { EpubTextExtractor(bookOpener) }
    private val txtMdTextExtractor: TxtMdTextExtractor by lazy { TxtMdTextExtractor() }
    val searchIndexCoordinator: SearchIndexCoordinator by lazy {
        SearchIndexCoordinator(
            repository = repository,
            searchDao = database.searchDao(),
            extractorFor = { fmt: BookFormat ->
                when (fmt) {
                    BookFormat.epub -> epubTextExtractor
                    BookFormat.txt, BookFormat.md -> txtMdTextExtractor
                    BookFormat.pdf, BookFormat.azw3 -> null   // metadata-only — never indexed
                }
            },
            scope = appScope,
            ioDispatcher = Dispatchers.IO,
        )
    }

    /** Idempotent — starts the single search-index collector (the coordinator's own AtomicBoolean
     *  makes a repeat call a no-op). Called once from [VReaderApp.onCreate]. */
    fun startSearchIndexing() = searchIndexCoordinator.startSearchIndexing()

    // feature #128 WI-6 — the query pipeline. SearchRepository turns a raw query into an observable
    // Flow of first-hit-per-book text hits (grows as indexing completes); RecentSearchesStore is a
    // device-local DataStore under noBackupFilesDir (the readerSettingsStore precedent — recents are
    // per-device, NOT in the backup contract). The SearchViewModel factory wires the metadata filter,
    // the text-hit Flow, the completeness gate, and recent-recording for the WI-7 screen.
    val searchRepository: com.vreader.app.search.SearchRepository by lazy {
        com.vreader.app.search.SearchRepository(database.searchDao())
    }
    internal val recentSearchesDataStore = prefsStore(RECENT_SEARCHES_PREFS)
    val recentSearchesStore: com.vreader.app.search.RecentSearchesStore by lazy {
        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
    }

    // ── feature #131 WI-4b — bilingual + AI-config DI graph ──────────────────────────────
    // AppContainer NOW constructs AiProviderStore (previously not provided — only a comment
    // named it above, "OpdsSourceStore / AiProviderStore precedent"). Keys are kept ONLY as
    // SecretCipher tokens; both DataStores follow the readerSettingsStore convention (device-local
    // under noBackupFilesDir — per-device config, NOT in the backup contract). The bilingual
    // services (translation cache store, readiness gate, prefetcher + VM factories) live in a
    // BilingualServices holder to keep this file focused.

    internal val aiProvidersDataStore = prefsStore(AI_PROVIDERS_PREFS)
    internal val bilingualPerBookDataStore = prefsStore(BILINGUAL_PER_BOOK_PREFS)

    /** Process-singleton AI-provider store (API keys as [secretCipher] tokens, never plaintext). */
    val aiProviderStore: AiProviderStore by lazy { AiProviderStore(aiProvidersDataStore, secretCipher) }

    /** Process-singleton per-book bilingual-config store (enabled / targetLanguage / granularity). */
    val perBookBilingualStore: PerBookBilingualStore by lazy { PerBookBilingualStore(bilingualPerBookDataStore) }

    /** The bilingual + AI-config DI holder (stores, readiness gate, and per-session factories). */
    private val bilingualServices: BilingualServices by lazy {
        BilingualServices(
            aiProviderStore = aiProviderStore,
            chapterTranslationDao = database.chapterTranslationDao(),
            perBookBilingualStore = perBookBilingualStore,
        )
    }

    /** Process-singleton coroutine cache boundary over the translation DAO. */
    val chapterTranslationStore: ChapterTranslationStore get() = bilingualServices.chapterTranslationStore

    /** Process-singleton provider+key readiness gate (drives the bilingual setup-sheet state). */
    val bilingualAiReadiness: BilingualAiReadiness get() = bilingualServices.bilingualAiReadiness

    /**
     * Builds a PER-SESSION [ChapterTranslationPrefetcher] for [bookKey] over [textProvider]
     * (the prefetcher's injected client factory defaults to `AiProviderFactory::create`).
     * A fresh instance per open book — never a singleton.
     */
    fun chapterTranslationPrefetcher(bookKey: String, textProvider: ChapterTextProvider): ChapterTranslationPrefetcher =
        bilingualServices.prefetcher(bookKey, textProvider)

    /**
     * Builds a PER-SESSION [BilingualViewModel] for [bookKey] over [textProvider], wired to the
     * real prefetcher, the live provider snapshot, and the readiness gate.
     */
    fun bilingualViewModel(bookKey: String, textProvider: ChapterTextProvider): BilingualViewModel =
        bilingualServices.bilingualViewModel(bookKey, textProvider)

    /** Builds a fresh [AiSettingsViewModel] over the shared [aiProviderStore] (the WI-AIP Variant-A sheet). */
    fun aiSettingsViewModel(): AiSettingsViewModel = AiSettingsViewModel(aiProviderStore)

    /**
     * feature #133 WI-10 — the per-reader-session in-book-search ViewModel for a TXT/MD host. Wires the
     * WI-6 [InBookSearchRepository] (FTS DAO page/count/resume + the WI-4 [TxtMdInBookHitResolver] over the
     * already-decoded [decodedText]) behind the WI-8 [InBookSearchViewModel], gated by the WI-7
     * [IndexStateGate] over the DAO's `observeIndexState` Flow and fed the GLOBAL recents store.
     *
     * The EPUB engine seam is NEVER invoked for a TXT/MD host (the repository dispatches only the TXT/MD
     * branch for `txt`/`md`), so `epubEngineFor` is an error-throwing guard — a call would be a wiring bug.
     * ONE [InBookSearchRepository] per session (the VM's `closeAllEpubCursors` lifecycle contract holds
     * uniformly even though TXT has no cursors). [coroutineScope] is the VM's `viewModelScope` in production
     * (the VM cancels its child collectors on `onCleared`).
     */
    fun inBookSearchViewModel(
        bookKey: String,
        format: BookFormat,
        decodedText: String,
        contentSHA256: String,
        fileByteCount: Long,
        coroutineScope: CoroutineScope,
    ): com.vreader.app.search.InBookSearchViewModel {
        val searchDao = database.searchDao()
        val repository = com.vreader.app.search.InBookSearchRepository(
            dispatcher = Dispatchers.Default,
            fts = com.vreader.app.search.InBookFtsDeps(
                matchingChunksPage = { ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit ->
                    searchDao.matchingChunksPage(bookKey, ftsQuery, afterSectionIndex, afterChunkOrdinal, afterId, limit)
                },
                chunkAtOrAfter = { ftsQuery, atSectionIndex, atChunkOrdinal, atId ->
                    searchDao.chunkAtOrAfter(bookKey, ftsQuery, atSectionIndex, atChunkOrdinal, atId)
                },
                // The resolver re-derives the chunk boundaries from the ALREADY-decoded reader text (no I/O);
                // memoized per session inside the resolver (built once).
                resolverFor = {
                    com.vreader.app.search.TxtMdInBookHitResolver(
                        contentSHA256 = contentSHA256,
                        fileByteCount = fileByteCount,
                        format = format.name,
                        decodedText = decodedText,
                    )
                },
            ),
            // TXT/MD never reaches the EPUB branch — a call here is a dispatch bug, fail fast.
            epubEngineFor = { error("EPUB in-book search engine requested on a TXT/MD host") },
        )
        return com.vreader.app.search.InBookSearchViewModel(
            bookKey = bookKey,
            format = format,
            searcher = repository.asSearcher(),
            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
            indexStateFlow = searchDao.observeIndexState(bookKey),
            // For a settled-`indexed` TXT/MD row the gate consults this to decide Ready vs definitive
            // NoResults. `hasOccurrence` carries no query, so we report Ready (true) and let the actual
            // `page(...)` be the source of truth: a settled book with zero matches runs one fast FTS query
            // and the repository returns NoResults — the SAME UI outcome the gate's occurrence short-circuit
            // would give, without threading the live query through a shared mutable seam (no race). The gate
            // is only consulted on a settled-indexed row, so this never fires while Indexing/missing/failed.
            hasOccurrence = { true },
            recentsFlow = recentSearchesStore.recents(),
            recordQuery = { q -> recentSearchesStore.record(q) },
            dispatcher = Dispatchers.Default,
            coroutineScope = coroutineScope,
        )
    }

    /**
     * feature #133 WI-11 — the per-reader-session in-book-search ViewModel for the EPUB host. EPUB search does
     * NOT use the #128 FTS index at all (a chunk-level, location-less index cannot yield a jumpable position);
     * instead the WI-6 [InBookSearchRepository]'s EPUB branch runs Readium's OWN `SearchService` over the LIVE
     * [publication] via the WI-5 [EpubInBookSearchEngine] production constructor (which wraps the real
     * publication behind the `PublicationSearchSource` seam), returning navigable Readium `Locator`s the host
     * jumps to with `navigator.go`.
     *
     * EPUB bypasses the WI-7 index-state gate entirely: the [indexStateFlow] emits `null` (missing) and
     * [hasOccurrence] reports Ready, so the gate resolves to Ready and the engine's own `isSearchable` probe
     * is the real capability check (an un-searchable publication → the repository's [InBookSearchOutcome.Unsupported]
     * → the WI-8 VM's `hidesSearchEntry`, so the host omits the Search icon). The TXT/MD FTS branch is NEVER
     * invoked for an EPUB host, so its factories are error-throwing guards (a call would be a wiring bug).
     *
     * ONE [InBookSearchRepository] per session (so the live Readium `SearchIterator` behind
     * `SearchCursor.Epub` is held once and disposed via `closeAllEpubCursors` on dismiss / `onCleared`).
     * [coroutineScope] is the host's `lifecycleScope` in production (the VM cancels its child collectors on
     * `onCleared`).
     */
    fun epubInBookSearchViewModel(
        bookKey: String,
        publication: org.readium.r2.shared.publication.Publication,
        coroutineScope: CoroutineScope,
    ): com.vreader.app.search.InBookSearchViewModel {
        val repository = com.vreader.app.search.InBookSearchRepository(
            dispatcher = Dispatchers.Default,
            // The EPUB host never reaches the FTS branch (the repository dispatches only the EPUB branch for
            // `epub`), so the TXT/MD deps are error-throwing guards — a call here is a wiring bug, fail fast.
            fts = com.vreader.app.search.InBookFtsDeps(
                matchingChunksPage = { _, _, _, _, _ -> error("FTS matchingChunksPage requested on an EPUB host") },
                chunkAtOrAfter = { _, _, _, _ -> error("FTS chunkAtOrAfter requested on an EPUB host") },
                resolverFor = { error("FTS resolver requested on an EPUB host") },
            ),
            // The LIVE wiring: build the WI-5 engine over the real Readium publication (its production
            // constructor wraps the publication behind the `PublicationSearchSource` seam). One engine per
            // repository/session; the repository memoizes it per bookKey.
            epubEngineFor = { com.vreader.app.search.EpubInBookSearchEngine(publication) },
        )
        return com.vreader.app.search.InBookSearchViewModel(
            bookKey = bookKey,
            format = BookFormat.epub,
            searcher = repository.asSearcher(),
            indexStateGate = com.vreader.app.search.IndexStateGate(Dispatchers.Default),
            // EPUB bypasses the FTS index-state gate: a `null` (missing) row + `hasOccurrence == true` resolve
            // the gate to Ready, so the engine's own `isSearchable` probe is the capability check.
            indexStateFlow = kotlinx.coroutines.flow.flowOf(null),
            hasOccurrence = { true },
            recentsFlow = recentSearchesStore.recents(),
            recordQuery = { q -> recentSearchesStore.record(q) },
            dispatcher = Dispatchers.Default,
            coroutineScope = coroutineScope,
        )
    }

    /** Builds a [com.vreader.app.search.SearchViewModel] wired to the live library, in-text repository,
     *  recents, collections, and the settled-completeness gate. */
    fun searchViewModel(): com.vreader.app.search.SearchViewModel =
        com.vreader.app.search.SearchViewModel(
            libraryFlow = repository.observeLibrary(),
            textHitsFor = { q -> searchRepository.textHits(q) },
            recentsFlow = recentSearchesStore.recents(),
            collectionsFlow = collectionRepository.observeCollections(),
            indexCompleteFlow = database.searchDao().observeUnsettledIndexableCount()
                .map { it == 0 },
            recordQuery = { q -> recentSearchesStore.record(q) },
        )

    // ── feature #155 — "Open with VReader" / "Share to VReader" ───────────────────────────
    // ImportActivity resolves + opens each inbound stream while its read grant is alive and
    // hands the already-open work to the PROCESS-WIDE coordinator, which owns every stream
    // and drains ONE queue with ONE worker — so sequencing and the in-flight cap hold across
    // concurrent ImportActivity instances, and a copy outlives the activity that started it.
    // Both are lazy and reuse the EXISTING repository/importer/appScope singletons: an
    // inbound document must land in the same library as a SAF-picked one.

    /** Resolves an inbound content URI to a format + name + ONE already-open, rewound stream. */
    val incomingBookResolver: IncomingBookResolver by lazy {
        IncomingBookResolver(appContext.contentResolver)
    }

    val incomingImportCoordinator: IncomingImportCoordinator by lazy {
        IncomingImportCoordinator(importer = importer, booksDir = booksDir, appScope = appScope)
    }

    init {
        // EXACTLY ONCE, in the constructor — so it cannot race a live import (nothing can
        // have reached [importer] yet) and cannot run twice. Deliberately the companion
        // form: the instance method would force the importer, and with it Room, onto the
        // startup path. Age-gated to >1h, so even a hypothetical concurrent import is safe.
        IncomingImportCoordinator.sweepStaleTempFiles(booksDir)
    }

    /** In-memory last reading char-offset per fingerprintKey. Written synchronously on
     *  save so a fast rotation / reopen restores the LATEST position without waiting for
     *  the async Room write to commit; Room remains the durable store across process death. */
    private val lastOffsets = java.util.concurrent.ConcurrentHashMap<String, Int>()
    fun cacheOffset(fingerprintKey: String, charOffsetUtf16: Int) { lastOffsets[fingerprintKey] = charOffsetUtf16 }
    fun cachedOffset(fingerprintKey: String): Int? = lastOffsets[fingerprintKey]

    /** In-memory last PDF page index per fingerprintKey — a TYPED cache distinct from the
     *  char-offset one (feature #115; a PDF position is a page, not a UTF-16 offset). */
    private val lastPages = java.util.concurrent.ConcurrentHashMap<String, Int>()
    fun cachePage(fingerprintKey: String, page: Int) { lastPages[fingerprintKey] = page }
    fun cachedPage(fingerprintKey: String): Int? = lastPages[fingerprintKey]

    companion object {
        /** The AndroidKeyStore alias for AI provider API keys — DISTINCT from WebDAV/OPDS
         *  (`vreader.webdav.password` / `vreader.opds.password`) so subsystems never share a key. */
        const val AI_KEY_ALIAS = "vreader.ai.password"

        // DISTINCT device-local Preferences backing files (a clash would make two subsystems
        // overwrite each other's prefs). All live under noBackupFilesDir (per-device, not backed up).
        const val READER_SETTINGS_PREFS = "reader_settings.preferences_pb"
        const val RECENT_SEARCHES_PREFS = "recent_searches.preferences_pb"
        const val AI_PROVIDERS_PREFS = "ai_providers.preferences_pb"
        const val BILINGUAL_PER_BOOK_PREFS = "bilingual_per_book.preferences_pb"
    }
}

class VReaderApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // feature #128 WI-5 — eagerly start the cross-book search-index collector (idempotent).
        container.startSearchIndexing()
    }
}
