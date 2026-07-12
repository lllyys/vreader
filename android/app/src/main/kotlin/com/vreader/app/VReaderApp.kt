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
import com.vreader.app.reader.BookOpener
import com.vreader.app.search.BookTextExtractor
import com.vreader.app.search.EpubTextExtractor
import com.vreader.app.search.asSearcher
import com.vreader.app.search.SearchIndexCoordinator
import com.vreader.app.search.TxtMdTextExtractor
import com.vreader.app.annotations.AnnotationsRepository
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

/** Process-wide singletons, lazily built. */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val database: VReaderDatabase by lazy { VReaderDatabase.build(appContext) }
    val repository: LibraryRepository by lazy {
        LibraryRepository(database.bookDao(), database.readingPositionDao())
    }
    val importer: BookImporter by lazy {
        BookImporter(File(appContext.filesDir, "books"), repository)
    }

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
    private val readerSettingsDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
            File(appContext.noBackupFilesDir, "reader_settings.preferences_pb")
        }
    }
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
    private val recentSearchesDataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> by lazy {
        androidx.datastore.preferences.core.PreferenceDataStoreFactory.create {
            File(appContext.noBackupFilesDir, "recent_searches.preferences_pb")
        }
    }
    val recentSearchesStore: com.vreader.app.search.RecentSearchesStore by lazy {
        com.vreader.app.search.RecentSearchesStore(recentSearchesDataStore)
    }

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
