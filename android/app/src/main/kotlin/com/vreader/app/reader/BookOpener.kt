// Purpose: Open a stored EPUB with Readium-Kotlin → a Publication + extract its
// metadata — feature #106 WI-5. This is the UI-free OPEN path (parsing, not
// rendering); the visible reader host that DISPLAYS the publication is the
// design-blocked #1745 surface and will consume this opener. Mirrors the iOS
// AssetRetriever → PublicationOpener flow; the wiring is lifted from the
// Spike-B harness (spikes/android-reader-bench ReaderOpener), now product code.
package com.vreader.app.reader

import android.content.Context
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.io.File

/** A stored EPUB could not be opened/parsed by Readium (missing / retrieve / open failure). */
class BookOpenException(message: String) : Exception(message)

/** The book-level metadata the Library needs from an opened publication. */
data class BookMetadata(val title: String?, val readingOrderCount: Int)

/**
 * Opens a stored EPUB (app-private storage [File]) into a Readium [Publication].
 * EPUB-only (`pdfFactory = null`). The blocking disk/ZIP/XML parse runs on
 * [ioDispatcher] (injected — never parse a 13–18MB EPUB on Main). All failure
 * modes surface as a typed [BookOpenException].
 */
@OptIn(ExperimentalReadiumApi::class)
class BookOpener(
    private val context: Context,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    /**
     * Opens the publication. **Caller owns the returned [Publication]** and MUST
     * `close()` it (see [readMetadata] for the open→read→close convenience).
     */
    suspend fun open(file: File): Publication = withContext(ioDispatcher) { openInternal(file) }

    /**
     * Opens the book, reads its [BookMetadata], and closes the publication — the
     * import/library path that confirms a stored artifact is a readable EPUB and
     * extracts its real title (today the imported title is the filename).
     */
    suspend fun readMetadata(file: File): BookMetadata = withContext(ioDispatcher) {
        val publication = openInternal(file)
        try {
            BookMetadata(
                title = publication.metadata.title,
                readingOrderCount = publication.readingOrder.size,
            )
        } finally {
            publication.close()
        }
    }

    private suspend fun openInternal(file: File): Publication {
        if (!file.exists()) throw BookOpenException("book not found at ${file.absolutePath}")
        val httpClient = DefaultHttpClient()
        val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
        val parser = DefaultPublicationParser(
            context = context,
            httpClient = httpClient,
            assetRetriever = assetRetriever,
            pdfFactory = null,
        )
        val opener = PublicationOpener(parser)

        val asset = assetRetriever.retrieve(file.toUrl(isDirectory = false))
            .getOrElse { throw BookOpenException("retrieve failed: $it") }
        // The Asset owns an open file handle. On a successful open() the returned
        // Publication takes ownership (its close() releases it); on ANY failure
        // after retrieval we must close the Asset ourselves or it leaks.
        var handedOff = false
        try {
            val publication = opener.open(asset, allowUserInteraction = false)
                .getOrElse { throw BookOpenException("open failed: $it") }
            handedOff = true
            return publication
        } finally {
            if (!handedOff) asset.close()
        }
    }
}
