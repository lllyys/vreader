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
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.stats.ReadingStatsRepository
import com.vreader.app.stats.ReadingTimeTracker
import com.vreader.app.stats.clock.SystemDateClock
import com.vreader.app.stats.clock.SystemElapsedClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
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
    }
}
