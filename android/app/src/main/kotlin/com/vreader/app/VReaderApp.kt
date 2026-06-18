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

    /** Process-lifetime scope for fire-and-forget writes that must outlive a screen
     *  (e.g. the reader's onStop position flush — it must finish even as the activity
     *  is being torn down). */
    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
}

class VReaderApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
