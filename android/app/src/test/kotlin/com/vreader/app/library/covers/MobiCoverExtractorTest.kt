// Purpose: feature #152 WI-3 — `MobiCoverExtractor`, the thin adapter that maps the pure-JVM
// parser's outcome onto the shared `CoverResult` vocabulary and decodes the located bytes.
//
// The adapter owns exactly one decision the parser cannot make: structural mode ⑩ — the target
// record was located and read, but its payload is not a decodable image (DRM-encrypted, or simply
// not an image). That is a property of the CONTENT, so it memoises as `None`, never `Failed`.
//
// The decode seam is injected rather than called statically. Robolectric's `BitmapFactory` is a
// shadow that does not really decode — it returns a non-null Bitmap for arbitrary bytes — so
// asserting "undecodable → None" against the shadow would assert nothing at all. Injecting the
// decoder tests the ADAPTER's routing honestly; the real `BitmapFactory` behaviour belongs to the
// connected lane.
package com.vreader.app.library.covers

import android.graphics.Bitmap
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.rules.TemporaryFolder
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class MobiCoverExtractorTest {

    @get:Rule
    val temp = TemporaryFolder()

    private fun bitmap(): Bitmap = Bitmap.createBitmap(2, 3, Bitmap.Config.ARGB_8888)

    private fun extractor(
        decode: (ByteArray) -> Bitmap?,
        parse: (File) -> MobiCoverParseResult,
    ) = MobiCoverExtractor(
        parse = parse,
        decode = decode,
        ioDispatcher = UnconfinedTestDispatcher(),
    )

    @Test
    fun `located bytes that decode become Art carrying that bitmap`() = runTest {
        val decoded = bitmap()
        val cover = jpegLike(64)
        val result = extractor(
            decode = { decoded },
            parse = { MobiCoverParseResult.Art(cover) },
        ).extract(File(temp.root, "book.azw3"))

        assertTrue("expected Art but got $result", result is CoverResult.Art)
        assertSame("the adapter hands back exactly the decoded bitmap", decoded, (result as CoverResult.Art).bitmap)
    }

    @Test
    fun `⑩ located bytes that do not decode are None, not Failed`() = runTest {
        // A DRM-encrypted or garbage payload is a property of the file's CONTENT, so it memoises.
        // Classifying it Failed would re-open and re-parse the book on every app start, forever.
        val result = extractor(
            decode = { null },
            parse = { MobiCoverParseResult.Art(ByteArray(64) { 0x7A }) },
        ).extract(File(temp.root, "drm.azw3"))

        assertEquals(CoverResult.None, result)
    }

    @Test
    fun `the adapter passes the parser's bytes to the decoder unchanged`() = runTest {
        val cover = jpegLike(128)
        var seen: ByteArray? = null
        extractor(
            decode = { bytes -> seen = bytes; bitmap() },
            parse = { MobiCoverParseResult.Art(cover) },
        ).extract(File(temp.root, "book.azw3"))

        assertArrayEquals("no re-slicing or copying between parser and decoder", cover, seen)
    }

    @Test
    fun `parser None maps to CoverResult None and never invokes the decoder`() = runTest {
        var decoderCalls = 0
        val result = extractor(
            decode = { decoderCalls++; bitmap() },
            parse = { MobiCoverParseResult.None },
        ).extract(File(temp.root, "no-cover.azw3"))

        assertEquals(CoverResult.None, result)
        assertEquals("nothing to decode", 0, decoderCalls)
    }

    @Test
    fun `parser Failed maps to CoverResult Failed, so the coordinator retries rather than memoises`() = runTest {
        val result = extractor(
            decode = { bitmap() },
            parse = { MobiCoverParseResult.Failed },
        ).extract(File(temp.root, "missing.azw3"))

        assertEquals(CoverResult.Failed, result)
    }

    @Test
    fun `a decoder that throws does not escape the extractor`() = runTest {
        // "No extractor throws" is a structural guarantee the coordinator depends on: one book must
        // never be able to kill the app-scope backfill for the whole library.
        val result = extractor(
            decode = { throw OutOfMemoryError("decoding a hostile image") },
            parse = { MobiCoverParseResult.Art(jpegLike(64)) },
        ).extract(File(temp.root, "hostile.azw3"))

        assertEquals(CoverResult.None, result)
    }

    @Test
    fun `the real parser is wired in by default`() = runTest {
        // Guards against the adapter defaulting to a stub: a genuine cover-bearing fixture on disk
        // must resolve end to end with no seam injected except the decoder.
        val cover = jpegLike(64)
        val file = writeFixture(temp.root, "wired.azw3", buildCoverBook(coverBytes = cover))
        var seen: ByteArray? = null
        val result = MobiCoverExtractor(
            decode = { bytes -> seen = bytes; bitmap() },
            ioDispatcher = UnconfinedTestDispatcher(),
        ).extract(file)

        assertTrue("expected Art but got $result", result is CoverResult.Art)
        assertArrayEquals("the default parse seam is the real MobiCoverParser", cover, seen)
    }
}
