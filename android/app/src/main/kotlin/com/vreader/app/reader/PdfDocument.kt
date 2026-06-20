// Purpose: feature #115 WI-1 (#110 Phase 3) — a safe wrapper over android.graphics.pdf
// .PdfRenderer for the PDF reader. PdfRenderer is NOT thread-safe, opens only one Page at a
// time, and close() must not race a render (it throws if a page is open) — so renderPage AND
// close are serialized through ONE Mutex on an IO dispatcher, and every openPage() is paired
// with Page.close() in finally. open() maps the failure modes the reader's state machine needs:
// SecurityException → ProtectedOrUnsupported (password-protected OR an unsupported security
// scheme — stock PdfRenderer has no cross-device unlock at minSdk 26), IOException/
// IllegalArgumentException/anything-else → Corrupt.
package com.vreader.app.reader

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.Log
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/** The outcome of opening a PDF — drives the reader's state machine. */
sealed interface PdfOpenResult {
    data class Ok(val document: PdfDocument) : PdfOpenResult
    /** Password-protected OR an unsupported security scheme (stock PdfRenderer can't open it). */
    data object ProtectedOrUnsupported : PdfOpenResult
    /** Damaged / undecodable file. */
    data object Corrupt : PdfOpenResult
}

class PdfDocument private constructor(
    private val renderer: PdfRenderer,
    private val descriptor: ParcelFileDescriptor,
    private val dispatcher: CoroutineDispatcher,
    /** Captured at open time (Gate-4): reading `renderer.pageCount` after close() would use a
     *  closed renderer / race the unserialized field. A PDF's page count is immutable. */
    val pageCount: Int,
) {
    /** Serializes renderPage AND close — PdfRenderer allows one open page at a time and close()
     *  must not race a render. */
    private val mutex = Mutex()
    private var closed = false

    /**
     * Render [pageIndex] into a Bitmap of [targetWidthPx] (height derived from the page aspect
     * ratio). Serialized: only one page is ever open. Returns a freshly-allocated bitmap; when
     * displayed in Compose (the PDF reader), Compose owns its drawn lifetime — do NOT recycle it
     * while it may still be drawn (recycling at the composable boundary races Compose's draw and
     * crashes; the reader lets GC reclaim off-screen page bitmaps).
     */
    suspend fun renderPage(pageIndex: Int, targetWidthPx: Int): Bitmap = withContext(dispatcher) {
        require(targetWidthPx > 0) { "targetWidthPx must be > 0" }
        mutex.withLock {
            check(!closed) { "PdfDocument is closed" }
            val page = renderer.openPage(pageIndex)
            try {
                val aspect = page.height.toFloat() / page.width.toFloat()
                val h = (targetWidthPx * aspect).toInt().coerceAtLeast(1)
                val bmp = Bitmap.createBitmap(targetWidthPx, h, Bitmap.Config.ARGB_8888)
                bmp.eraseColor(Color.WHITE)   // PDF pages render onto a white sheet
                page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                bmp
            } finally {
                page.close()
            }
        }
    }

    /** Close the renderer + descriptor, serialized so it can't race an in-flight render. */
    suspend fun close() = withContext(dispatcher) {
        mutex.withLock {
            if (closed) return@withLock
            closed = true
            runCatching { renderer.close() }
            runCatching { descriptor.close() }
        }
    }

    companion object {
        private const val TAG = "PdfDocument"

        /** Open [file] as a PDF, mapping the failure modes the reader needs. */
        fun open(file: File, dispatcher: CoroutineDispatcher = Dispatchers.IO): PdfOpenResult {
            var fd: ParcelFileDescriptor? = null
            return try {
                fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                val renderer = PdfRenderer(fd)
                PdfOpenResult.Ok(PdfDocument(renderer, fd, dispatcher, renderer.pageCount))
            } catch (e: SecurityException) {
                fd?.let { runCatching { it.close() } }
                PdfOpenResult.ProtectedOrUnsupported
            } catch (e: IOException) {
                fd?.let { runCatching { it.close() } }
                PdfOpenResult.Corrupt
            } catch (e: IllegalArgumentException) {
                fd?.let { runCatching { it.close() } }
                PdfOpenResult.Corrupt
            } catch (e: Throwable) {
                Log.w(TAG, "unexpected error opening PDF; treating as corrupt", e)
                fd?.let { runCatching { it.close() } }
                PdfOpenResult.Corrupt
            }
        }
    }
}
