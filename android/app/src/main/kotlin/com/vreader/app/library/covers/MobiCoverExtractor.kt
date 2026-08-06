// Purpose: feature #152 WI-3 — the `CoverExtractor` for MOBI/AZW3/AZW/PRC books (every Kindle
// format canonicalises to `BookFormat.azw3`). A thin adapter: `MobiCoverParser` does the binary
// work in pure JVM and returns bytes; this decodes them into a Bitmap and speaks `CoverResult`.
//
// Key decisions:
// - **The split exists so the risky code is testable without Robolectric or an emulator.** All of
//   the parsing — the attacker-controlled record table, the unbacked spans, the sentinels — lives
//   behind an Android-free seam and is exercised in the fast JVM lane.
// - **A payload that does not decode is `None`, not `Failed`.** DRM-encrypted or garbage image
//   bytes are a property of the file's CONTENT, so the coordinator memoises the answer. Classifying
//   it `Failed` would re-open and re-parse the book on every app start, forever.
// - **The decode seam is injected.** Robolectric's `BitmapFactory` is a shadow that does not really
//   decode, so a test asserting "undecodable → None" against it would assert nothing. Injection
//   keeps the adapter's routing honestly testable; production uses the real `BitmapFactory`.
// - **Nothing escapes.** `extract` converts every `Throwable` (including `OutOfMemoryError` from a
//   hostile image) into a `CoverResult`, preserving `CancellationException` so structured
//   concurrency still holds. One book can never kill the app-scope backfill for the whole library.
//
// @coordinates-with: MobiCoverParser.kt, CoverResult.kt
package com.vreader.app.library.covers

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class MobiCoverExtractor(
    private val parse: (File) -> MobiCoverParseResult = MobiCoverParser::parse,
    private val decode: (ByteArray) -> Bitmap? = { bytes ->
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    },
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : CoverExtractor {

    override suspend fun extract(file: File): CoverResult = withContext(ioDispatcher) {
        try {
            when (val located = parse(file)) {
                is MobiCoverParseResult.Failed -> CoverResult.Failed
                is MobiCoverParseResult.None -> CoverResult.None
                is MobiCoverParseResult.Art ->
                    decode(located.bytes)?.let { CoverResult.Art(it) } ?: CoverResult.None
            }
        } catch (e: CancellationException) {
            throw e
        } catch (t: Throwable) {
            // The bytes were located, so the file was reachable; only turning them into an image
            // failed. That is content, not access — memoise it.
            CoverResult.None
        }
    }
}
