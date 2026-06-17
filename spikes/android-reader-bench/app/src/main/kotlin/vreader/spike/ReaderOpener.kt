package vreader.spike

import android.content.Context
import java.io.File
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

/**
 * Spike B (#105) — the shared Readium-Kotlin 3.3.0 EPUB open path, reused by the
 * scroll benchmark (WI-2) and the anchor-restore probes (WI-3). Mirrors the iOS
 * AssetRetriever -> PublicationOpener flow; no product code, throwaway harness.
 *
 * Both `retrieve` and `open` are suspend + return Readium's own `Try<_, _Error>`
 * (NOT kotlin.Result). `pdfFactory = null` because this spike opens EPUB only —
 * no PDF adapter module is needed.
 */
@OptIn(ExperimentalReadiumApi::class)
object ReaderOpener {

    suspend fun open(context: Context, file: File): Publication {
        require(file.exists()) { "corpus not found at ${file.absolutePath}" }
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
            .getOrElse { error("retrieve failed: $it") }
        return opener.open(asset, allowUserInteraction = false)
            .getOrElse { error("open failed: $it") }
    }

    /** The corpus path the harness shell pushes to (app external files dir). */
    fun corpusFile(context: Context): File =
        File(context.getExternalFilesDir(null), "corpus.epub")
}
