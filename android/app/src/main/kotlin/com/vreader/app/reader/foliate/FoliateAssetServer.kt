// Purpose: serve the foliate-js bundle + Android shell (from app assets/foliate/) and the imported
// book file (from app-private storage) to the reader WebView over a single VIRTUAL HTTPS origin
// (never file://). The book's untrusted scripts are neutered by the bundle patch (no `allow-scripts`
// on section iframes) + the shell CSP — NOT by origin separation: WI-0 proved foliate's section
// documents are shell-origin `blob:` URLs regardless of where the book FILE is served, so a separate
// book domain would not isolate them. Feature #126 WI-3.
package com.vreader.app.reader.foliate

import android.content.Context
import android.webkit.WebResourceResponse
import androidx.webkit.WebViewAssetLoader
import java.io.File

object FoliateAssetServer {

    /** The fixed virtual origin `WebViewAssetLoader` serves from. The bridge allow-lists ONLY this
     *  origin for `addWebMessageListener`, and blocks navigation/resource requests to any other. */
    const val SHELL_ORIGIN = "https://appassets.androidplatform.net"
    const val SHELL_URL = "$SHELL_ORIGIN/assets/foliate/reader.html"
    const val BOOK_PATH = "/book/"
    const val BOOK_NAME = "book"

    /** The same-origin URL the shell `fetch()`es to hand foliate the book bytes as a Blob. */
    fun bookUrl(): String = "$SHELL_ORIGIN$BOOK_PATH$BOOK_NAME"

    /**
     * One loader on [SHELL_ORIGIN]: `/assets/…` → app assets (bundle + shell), `/book/…` → the
     * imported book file. File IO happens inside the handler (off the main thread — the loader is
     * invoked on a WebView background thread).
     */
    fun loader(context: Context, bookFile: File): WebViewAssetLoader =
        WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context.applicationContext))
            .addPathHandler(BOOK_PATH, BookFilePathHandler(bookFile))
            .build()

    /** Serves the imported book file for ONLY the exact `book` sub-path (a hostile no-script section
     *  can't force repeated large-book streams via arbitrary `/book/...` URLs); null (→ the bridge
     *  fails closed with 404) for anything else or if the file is gone. */
    private class BookFilePathHandler(private val bookFile: File) : WebViewAssetLoader.PathHandler {
        override fun handle(path: String): WebResourceResponse? {
            if (path != BOOK_NAME) return null
            return try {
                if (!bookFile.isFile) {
                    null
                } else {
                    WebResourceResponse(
                        "application/octet-stream",
                        null,
                        200,
                        "OK",
                        mapOf("Cache-Control" to "no-store"),
                        bookFile.inputStream(),
                    )
                }
            } catch (e: Exception) {
                null
            }
        }
    }
}
