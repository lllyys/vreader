// Purpose: feature #155 WI-3 — `IncomingBookResolver`, the D3 resolution chain over
// exactly ONE stream, plus `sanitizeDisplayName`. The input is attacker-controlled
// (ImportActivity is exported), so the load-bearing assertions here are structural:
//
//   * IDENTITY STABILITY — a name-derived format (steps 1-2) ALWAYS beats a MIME type
//     or a magic-byte sniff (steps 3-4). Format is part of the canonical key
//     "format:sha:bytes", so a sniff that CONTRADICTED an extension would mint a second
//     library row for a book already imported. Sniffing only ever fills a gap.
//   * ONE STREAM — asserted with a COUNTING ContentResolver, not inferred from success.
//     Two opens would be a TOCTOU window, and a one-shot provider may hand back
//     different bytes the second time.
//   * THE REWIND IS REAL — asserted by hashing the bytes the CALLER goes on to read and
//     comparing to the untouched original. "the sniff returned pdf" says nothing about
//     whether the stream is still usable.
//   * NO LEAK — the stream is closed before UnsupportedFormat propagates.
//
// Robolectric hosts a real ContentResolver; a registered fake ContentProvider answers
// query()/getType(), and ShadowContentResolver's input-stream SUPPLIER is what counts
// the opens. Fixtures are synthetic: a CI JVM unit test cannot read the gitignored
// `test-books/` tree, and the ZIP/naming edges need byte-exact control.
//
// Invisible characters are built from NUMERIC CODE POINTS via `cp()`, never pasted as
// literals: a literal bidi or NUL character in source is unreviewable, and one stray
// copy/paste turns a spoofing test into a test of nothing.
package com.vreader.app.imports

import android.content.ContentProvider
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.OpenableColumns
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.ImportException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowContentResolver
import vreader.contracts.BookFormat
import vreader.contracts.DocumentFingerprint
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream

@RunWith(RobolectricTestRunner::class)
class IncomingBookResolverTest {

    @get:Rule
    val temp = TemporaryFolder()

    private val authority = "com.vreader.test.docs"
    private lateinit var provider: FakeProvider
    private lateinit var contentResolver: ContentResolver
    private lateinit var subject: IncomingBookResolver

    /** Opens per URI, counted at exactly the seam the resolver calls. */
    private val opens = mutableMapOf<Uri, Int>()

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        contentResolver = context.contentResolver
        provider = FakeProvider()
        ShadowContentResolver.registerProviderInternal(authority, provider)
        subject = IncomingBookResolver(contentResolver, Dispatchers.Unconfined)
    }

    // ---- harness -----------------------------------------------------------

    /** One code point as a String — the only way invisible characters enter this file. */
    private fun cp(codePoint: Int): String = String(Character.toChars(codePoint))

    private class FakeProvider : ContentProvider() {
        var cursorFactory: () -> Cursor? = { null }
        var mimeType: String? = null

        override fun onCreate(): Boolean = true
        override fun query(
            uri: Uri,
            projection: Array<out String>?,
            selection: String?,
            selectionArgs: Array<out String>?,
            sortOrder: String?,
        ): Cursor? = cursorFactory()

        override fun getType(uri: Uri): String? = mimeType
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
        override fun update(
            uri: Uri,
            values: ContentValues?,
            selection: String?,
            selectionArgs: Array<out String>?,
        ): Int = 0
    }

    /** A stream that records its own close, so a leak is observable. */
    private class TrackingStream(bytes: ByteArray) : ByteArrayInputStream(bytes) {
        var closed = false
            private set

        override fun close() {
            closed = true
            super.close()
        }
    }

    /** A stream with no mark support — the resolver must WRAP it, not reject it. */
    private class NoMarkStream(private val bytes: ByteArray) : InputStream() {
        private var pos = 0
        var closed = false
            private set

        override fun read(): Int = if (pos < bytes.size) bytes[pos++].toInt() and 0xFF else -1
        override fun markSupported(): Boolean = false
        override fun close() { closed = true }
    }

    private fun uri(path: String): Uri = Uri.parse("content://$authority/$path")

    private fun cursorOf(vararg columns: Pair<String, Any?>): Cursor =
        MatrixCursor(columns.map { it.first }.toTypedArray()).apply {
            addRow(columns.map { it.second })
        }

    private fun emptyCursor(): Cursor =
        MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE))

    /** DISPLAY_NAME + SIZE as a provider would report them (either may be absent). */
    private fun declare(displayName: String?, size: Long? = null) {
        provider.cursorFactory = {
            cursorOf(OpenableColumns.DISPLAY_NAME to displayName, OpenableColumns.SIZE to size)
        }
    }

    /** Registers [bytes] behind [target], counts every open, exposes the last stream. */
    private fun serve(
        target: Uri,
        bytes: ByteArray,
        factory: (ByteArray) -> InputStream = { TrackingStream(it) },
    ): () -> InputStream {
        var last: InputStream? = null
        shadowOf(contentResolver).registerInputStreamSupplier(target) {
            opens[target] = (opens[target] ?: 0) + 1
            factory(bytes).also { last = it }
        }
        return { last ?: error("stream was never opened") }
    }

    private fun openCount(target: Uri): Int = opens[target] ?: 0

    private suspend fun open(target: Uri): PendingImport =
        requireNotNull(subject.resolveAndOpen(target)) { "resolveAndOpen returned null for $target" }

    private suspend fun expectUnsupported(target: Uri): ImportException.UnsupportedFormat {
        val error = runCatching { subject.resolveAndOpen(target) }.exceptionOrNull()
        assertTrue("expected UnsupportedFormat, got $error", error is ImportException.UnsupportedFormat)
        return error as ImportException.UnsupportedFormat
    }

    private fun sha(bytes: ByteArray): String =
        DocumentFingerprint.hashing(ByteArrayInputStream(bytes)).sha256

    // ---- fixtures ----------------------------------------------------------

    private fun ByteArrayOutputStream.u16(v: Int) { write(v and 0xFF); write((v ushr 8) and 0xFF) }
    private fun ByteArrayOutputStream.u32(v: Long) {
        write((v and 0xFF).toInt()); write(((v ushr 8) and 0xFF).toInt())
        write(((v ushr 16) and 0xFF).toInt()); write(((v ushr 24) and 0xFF).toInt())
    }

    /** A minimal OCF-shaped EPUB: stored `mimetype` first entry, 20 bytes, no extra field. */
    private fun epubBytes(): ByteArray = ByteArrayOutputStream().apply {
        write(byteArrayOf(0x50, 0x4B, 0x03, 0x04))
        u16(0x0A)                 // @4  version needed
        u16(0)                    // @6  flags
        u16(0)                    // @8  method = STORED
        u16(0); u16(0)            // @10 time / date
        u32(0)                    // @14 crc32
        u32(20); u32(20)          // @18 compressed / @22 uncompressed
        u16(8); u16(0)            // @26 name length / @28 extra length
        write("mimetype".toByteArray(Charsets.US_ASCII))
        write("application/epub+zip".toByteArray(Charsets.US_ASCII))
        write(ByteArray(128) { 0x42 })
    }.toByteArray()

    private fun pdfBytes(): ByteArray = "%PDF-1.7 body bytes".toByteArray(Charsets.US_ASCII)

    private fun textBytes(): ByteArray = "Once upon a time, 从前有座山。\n".repeat(20).toByteArray()

    /** Deterministic, definitively-not-text bytes: an invalid UTF-8 lead plus NULs. */
    private fun opaqueBytes(): ByteArray {
        val rng = kotlin.random.Random(155)
        return byteArrayOf(0x80.toByte(), 0x81.toByte(), 0x00, 0x00) +
            ByteArray(256) { rng.nextInt().toByte() }
    }

    // ---- the chain, step by step ------------------------------------------

    @Test
    fun step1_displayNameExtensionResolvesTheFormat() = runTest {
        val target = uri("s1/opaque-id")
        declare("Moby Dick.epub", size = 4096)
        serve(target, opaqueBytes())          // nothing sniffable: only the NAME can decide

        val pending = open(target)
        assertEquals(BookFormat.epub, pending.format)
        assertEquals("Moby Dick.epub", pending.displayName)
        assertEquals(4096L, pending.declaredSize)
        assertEquals(target.toString(), pending.sourceUri)
        assertEquals(target, pending.uri)
        pending.stream.close()
    }

    @Test
    fun step2_lastPathSegmentExtensionResolvesTheFormatWhenThereIsNoDisplayName() = runTest {
        val target = uri("s2/novel.pdf")
        declare(null)                          // the provider reports no name at all
        serve(target, opaqueBytes())

        val pending = open(target)
        assertEquals(BookFormat.pdf, pending.format)
        assertEquals("novel.pdf", pending.displayName)
        pending.stream.close()
    }

    @Test
    fun step3_mimeTypeResolvesTheFormatWhenNoNameCarriesAnExtension() = runTest {
        val target = uri("s3/12345")
        declare(null)
        provider.mimeType = "application/epub+zip"
        serve(target, opaqueBytes())

        val pending = open(target)
        assertEquals(BookFormat.epub, pending.format)
        assertEquals("Untitled.epub", pending.displayName)   // fallback name + resolved extension
        pending.stream.close()
    }

    @Test
    fun step4_magicBytesResolveTheFormatWhenNothingElseDoes() = runTest {
        val target = uri("s4/12345")
        declare(null)
        serve(target, pdfBytes())

        val pending = open(target)
        assertEquals(BookFormat.pdf, pending.format)
        assertEquals("Untitled.pdf", pending.displayName)
        pending.stream.close()
    }

    @Test
    fun step5_everythingFailsThrowsUnsupportedFormat() = runTest {
        val target = uri("s5/12345")
        declare("mystery.bin")
        serve(target, opaqueBytes())

        assertEquals("mystery.bin", expectUnsupported(target).name)
    }

    // ---- THE identity-stability invariant ----------------------------------

    @Test
    fun aDisplayNameExtensionAlwaysBeatsAContradictingSniff() = runTest {
        // The bytes ARE a valid EPUB; the name says .txt. The name must win: this file
        // may already be in the library as `txt:<sha>:<bytes>`, and answering `epub`
        // here would create a duplicate row and a second copy on disk.
        val target = uri("inv1/opaque-id")
        val bytes = epubBytes()
        declare("lying-name.txt")
        serve(target, bytes)

        val pending = open(target)
        assertEquals(BookFormat.txt, pending.format)
        assertEquals(sha(bytes), sha(pending.stream.readBytes()))
        pending.stream.close()
    }

    @Test
    fun aLastPathSegmentExtensionAlsoBeatsAContradictingSniff() = runTest {
        val target = uri("inv2/lying-name.txt")
        declare(null)
        serve(target, epubBytes())

        val pending = open(target)
        assertEquals(BookFormat.txt, pending.format)
        pending.stream.close()
    }

    @Test
    fun aDisplayNameExtensionAlsoBeatsAContradictingMimeType() = runTest {
        val target = uri("inv3/opaque-id")
        declare("notes.md")
        provider.mimeType = "application/pdf"
        serve(target, pdfBytes())

        val pending = open(target)
        assertEquals(BookFormat.md, pending.format)
        pending.stream.close()
    }

    @Test
    fun aDisplayNameExtensionBeatsALastPathSegmentExtension() = runTest {
        val target = uri("inv4/whatever.pdf")
        declare("real-name.epub")
        serve(target, opaqueBytes())

        val pending = open(target)
        assertEquals(BookFormat.epub, pending.format)
        pending.stream.close()
    }

    @Test
    fun aLastPathSegmentExtensionBeatsAContradictingMimeType() = runTest {
        val target = uri("inv5/real-name.md")
        declare(null)
        provider.mimeType = "text/plain"
        serve(target, textBytes())

        val pending = open(target)
        assertEquals(BookFormat.md, pending.format)
        pending.stream.close()
    }

    // ---- MIME types that carry no information ------------------------------

    @Test
    fun octetStreamContributesNothingAndFallsThroughToTheSniff() = runTest {
        val target = uri("mime1/12345")
        declare(null)
        provider.mimeType = "application/octet-stream"
        serve(target, pdfBytes())

        assertEquals(BookFormat.pdf, open(target).format)
    }

    @Test
    fun octetStreamAloneDoesNotRescueUnsniffableBytes() = runTest {
        val target = uri("mime2/12345")
        declare(null)
        provider.mimeType = "application/octet-stream"
        serve(target, opaqueBytes())

        expectUnsupported(target)
    }

    @Test
    fun wildcardAndNullMimeTypesContributeNothing() = runTest {
        for ((index, mime) in listOf<String?>("*/*", null, "", "   ").withIndex()) {
            val target = uri("mime3/$index/12345")
            declare(null)
            provider.mimeType = mime
            serve(target, opaqueBytes())
            expectUnsupported(target)
        }
    }

    @Test
    fun theMimeMapCoversEveryTypeInThePlan() {
        val map = mapOf(
            "application/epub+zip" to BookFormat.epub,
            "application/x-epub+zip" to BookFormat.epub,
            "application/epub" to BookFormat.epub,
            "application/pdf" to BookFormat.pdf,
            "application/x-pdf" to BookFormat.pdf,
            "text/plain" to BookFormat.txt,
            "text/markdown" to BookFormat.md,
            "text/x-markdown" to BookFormat.md,
            "application/vnd.amazon.ebook" to BookFormat.azw3,
            "application/vnd.amazon.mobi8-ebook" to BookFormat.azw3,
            "application/x-mobipocket-ebook" to BookFormat.azw3,
        )
        map.forEach { (mime, expected) ->
            assertEquals(mime, expected, IncomingBookResolver.formatForMimeType(mime))
            assertEquals(
                "$mime uppercased",
                expected,
                IncomingBookResolver.formatForMimeType(mime.uppercase()),
            )
            assertEquals(
                "$mime with parameters",
                expected,
                IncomingBookResolver.formatForMimeType("$mime; charset=utf-8"),
            )
        }
        listOf("application/octet-stream", "*/*", null, "", "application/zip", "image/png").forEach {
            assertNull("$it must contribute nothing", IncomingBookResolver.formatForMimeType(it))
        }
    }

    // ---- stream discipline -------------------------------------------------

    @Test
    fun theStreamIsRewoundAfterSniffing_sha256Matches() = runTest {
        // The assertion that matters most: hash what the CALLER would read and compare
        // to the untouched bytes. "sniff returned pdf" proves nothing about usability.
        val target = uri("sha1/12345")
        val bytes = pdfBytes() + ByteArray(9000) { (it % 251).toByte() }
        declare(null)
        serve(target, bytes)

        val pending = open(target)
        assertEquals(BookFormat.pdf, pending.format)
        assertEquals(sha(bytes), sha(pending.stream.readBytes()))
        pending.stream.close()
    }

    @Test
    fun theStreamIsUntouchedWhenTheNameAlreadyDecided() = runTest {
        val target = uri("sha2/12345")
        val bytes = textBytes()
        declare("story.txt")
        serve(target, bytes)

        val pending = open(target)
        assertEquals(sha(bytes), sha(pending.stream.readBytes()))
        pending.stream.close()
    }

    @Test
    fun aNonMarkSupportingStreamIsWrappedNotRejected() = runTest {
        val target = uri("mark1/12345")
        val bytes = epubBytes()
        val last = serve(target, bytes) { NoMarkStream(it) }
        declare(null)

        val pending = open(target)
        assertEquals(BookFormat.epub, pending.format)          // the sniff still ran
        assertTrue("the returned stream must support mark", pending.stream.markSupported())
        assertEquals(sha(bytes), sha(pending.stream.readBytes()))
        assertTrue("the source must be the unwrapped stream", last() is NoMarkStream)
        pending.stream.close()
    }

    @Test
    fun resolveAndOpenOpensExactlyOneStream() = runTest {
        val target = uri("count1/12345")
        declare("book.epub", size = 10)
        provider.mimeType = "application/epub+zip"
        serve(target, epubBytes())

        val pending = open(target)
        assertEquals("openInputStream must be called exactly once", 1, openCount(target))
        pending.stream.close()
    }

    @Test
    fun resolveAndOpenOpensExactlyOneStreamOnTheSniffingPathToo() = runTest {
        val target = uri("count2/12345")
        declare(null)
        serve(target, pdfBytes())

        val pending = open(target)
        assertEquals(1, openCount(target))
        pending.stream.close()
    }

    @Test
    fun resolveAndOpenOpensExactlyOneStreamEvenWhenItThrows() = runTest {
        val target = uri("count3/12345")
        declare("mystery.bin")
        serve(target, opaqueBytes())

        expectUnsupported(target)
        assertEquals(1, openCount(target))
    }

    @Test
    fun peekOpensNoStreamAtAll() = runTest {
        val target = uri("count4/12345")
        declare("book.epub", size = 77)
        serve(target, epubBytes())

        val meta = subject.peek(target)
        assertEquals("book.epub", meta.displayName)
        assertEquals(77L, meta.declaredSize)
        assertEquals("peek must not open a stream", 0, openCount(target))
    }

    @Test
    fun theStreamIsClosedBeforeUnsupportedFormatPropagates() = runTest {
        val target = uri("leak1/12345")
        declare("mystery.bin")
        val last = serve(target, opaqueBytes())

        expectUnsupported(target)
        assertTrue("the stream leaked", (last() as TrackingStream).closed)
    }

    @Test
    fun theWrappedStreamIsAlsoClosedWhenUnsupportedFormatPropagates() = runTest {
        val target = uri("leak2/12345")
        declare("mystery.bin")
        val last = serve(target, opaqueBytes()) { NoMarkStream(it) }

        expectUnsupported(target)
        assertTrue("closing the wrapper must close the source", (last() as NoMarkStream).closed)
    }

    @Test
    fun aProviderThatRefusesToOpenYieldsNull() = runTest {
        // A `file://` URI to a path that does not exist: openInputStream refuses. The
        // contract is a null return, not an exception, so the caller can distinguish
        // "unreadable" from "unsupported".
        val missing = Uri.fromFile(File(temp.newFolder(), "gone.epub"))
        assertNull(subject.resolveAndOpen(missing))
    }

    // ---- cursor metadata ---------------------------------------------------

    @Test
    fun peekReadsDisplayNameAndSize() = runTest {
        val target = uri("peek1/12345")
        declare("A Book.epub", size = 123456)
        assertEquals(IncomingMetadata("A Book.epub", 123456L), subject.peek(target))
    }

    @Test
    fun peekTreatsAnAbsentOrNegativeSizeAsUnknown() = runTest {
        declare("x.epub", size = null)
        assertNull(subject.peek(uri("peek2/a")).declaredSize)

        declare("x.epub", size = -1)
        assertNull(subject.peek(uri("peek2/b")).declaredSize)

        provider.cursorFactory = { cursorOf(OpenableColumns.DISPLAY_NAME to "x.epub") }
        assertNull(subject.peek(uri("peek2/c")).declaredSize)

        declare("x.epub", size = 0)
        assertEquals(0L, subject.peek(uri("peek2/d")).declaredSize)   // empty file: a KNOWN size
    }

    @Test
    fun peekSurvivesANullOrEmptyCursor() = runTest {
        provider.cursorFactory = { null }
        assertEquals(IncomingMetadata(null, null), subject.peek(uri("peek3/a")))

        provider.cursorFactory = { emptyCursor() }
        assertEquals(IncomingMetadata(null, null), subject.peek(uri("peek3/b")))
    }

    @Test
    fun peekPropagatesAQueryThatThrows() = runTest {
        // WI-5 maps this to PreResolved(Unreadable); swallowing it here would hide a
        // permission failure from the pre-open preflight.
        provider.cursorFactory = { throw SecurityException("no read grant") }
        val error = runCatching { subject.peek(uri("peek4/a")) }.exceptionOrNull()
        assertTrue("expected SecurityException, got $error", error is SecurityException)
    }

    @Test
    fun resolveAndOpenSurvivesAQueryThatThrowsAndFallsThroughToTheLaterSteps() = runTest {
        // A provider may refuse `query` yet allow `openInputStream`. Losing the name is
        // not a reason to lose the book.
        val target = uri("q1/anthology.epub")
        provider.cursorFactory = { throw SecurityException("no metadata for you") }
        serve(target, opaqueBytes())

        val pending = open(target)
        assertEquals(BookFormat.epub, pending.format)          // step 2 saved it
        pending.stream.close()
    }

    @Test
    fun resolveAndOpenSurvivesAGetTypeThatThrows() = runTest {
        val target = uri("q2/12345")
        serve(target, pdfBytes())
        ShadowContentResolver.registerProviderInternal(
            authority,
            object : ContentProvider() {
                override fun onCreate() = true
                override fun query(
                    u: Uri,
                    p: Array<out String>?,
                    s: String?,
                    a: Array<out String>?,
                    o: String?,
                ): Cursor? = null

                override fun getType(u: Uri): String = throw IllegalStateException("boom")
                override fun insert(u: Uri, v: ContentValues?): Uri? = null
                override fun delete(u: Uri, s: String?, a: Array<out String>?): Int = 0
                override fun update(
                    u: Uri,
                    v: ContentValues?,
                    s: String?,
                    a: Array<out String>?,
                ): Int = 0
            },
        )

        val pending = open(target)
        assertEquals(BookFormat.pdf, pending.format)           // the sniff still ran
        pending.stream.close()
    }

    // ---- sanitizeDisplayName ----------------------------------------------

    @Test
    fun sanitizeStripsControlCharactersIncludingNulCrAndLf() {
        assertEquals("ab.epub", IncomingBookResolver.sanitizeDisplayName("a\n\r\tb.epub"))
        assertEquals("ab.epub", IncomingBookResolver.sanitizeDisplayName("a" + cp(0x0000) + "b.epub"))
        assertEquals("ab.epub", IncomingBookResolver.sanitizeDisplayName("a" + cp(0x0007) + "b.epub"))
        assertEquals("ab.epub", IncomingBookResolver.sanitizeDisplayName("a" + cp(0x001B) + "b.epub"))
        assertEquals("ab.epub", IncomingBookResolver.sanitizeDisplayName("a" + cp(0x007F) + "b.epub"))
        assertEquals("ab.epub", IncomingBookResolver.sanitizeDisplayName("a" + cp(0x0085) + "b.epub"))
    }

    @Test
    fun sanitizeCollapsesWhitespaceRunsAndTrims() {
        assertEquals("a b.epub", IncomingBookResolver.sanitizeDisplayName("  a     b.epub  "))
        // Non-breaking, em, and ideographic spaces are whitespace runs too.
        val exotic = "a" + cp(0x00A0) + cp(0x2003) + cp(0x3000) + "b.epub"
        assertEquals("a b.epub", IncomingBookResolver.sanitizeDisplayName(exotic))
    }

    @Test
    fun sanitizePreservesCjkLetters() {
        assertEquals("三体·黑暗森林.epub", IncomingBookResolver.sanitizeDisplayName("三体·黑暗森林.epub"))
        assertEquals("こんにちは世界.txt", IncomingBookResolver.sanitizeDisplayName("こんにちは世界.txt"))
    }

    @Test
    fun sanitizePreservesRtlLetters() {
        // Stripping Arabic or Hebrew LETTERS would be a broken sanitizer, not a safe one.
        assertEquals("كتاب.epub", IncomingBookResolver.sanitizeDisplayName("كتاب.epub"))
        assertEquals("ספר.epub", IncomingBookResolver.sanitizeDisplayName("ספר.epub"))
        assertEquals("كتاب عربي.epub", IncomingBookResolver.sanitizeDisplayName("كتاب عربي.epub"))
    }

    @Test
    fun sanitizeStripsEachBidiControlIndividually() {
        // One stray bidi control is enough to reverse the RENDERED order of a name, so
        // each code point is asserted on its own — a strip set that covers most of them
        // still ships the spoof.
        val bidiControls = listOf(
            0x061C,                                     // ARABIC LETTER MARK
            0x200E, 0x200F,                             // LRM, RLM
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E,     // LRE, RLE, PDF, LRO, RLO
            0x2066, 0x2067, 0x2068, 0x2069,             // LRI, RLI, FSI, PDI
        )
        for (code in bidiControls) {
            val cleaned = IncomingBookResolver.sanitizeDisplayName("gpj." + cp(code) + "koob.epub")
            assertEquals("U+%04X was not stripped".format(code), "gpj.koob.epub", cleaned)
        }
    }

    @Test
    fun sanitizeKeepsJoinersThatRealScriptsNeed() {
        // ZWNJ (U+200C) and ZWJ (U+200D) are format characters like the bidi controls,
        // but they are ORTHOGRAPHIC in Persian and Indic scripts. Blanket-stripping the
        // whole Cf category would corrupt real names — which is why the strip set is
        // enumerated rather than categorical.
        val persian = "می" + cp(0x200C) + "خواهم.epub"
        assertEquals(persian, IncomingBookResolver.sanitizeDisplayName(persian))
    }

    @Test
    fun sanitizeNfcNormalizes() {
        // "e" + COMBINING ACUTE ACCENT must fold to the precomposed U+00E9.
        assertEquals(
            cp(0x00E9) + ".epub",
            IncomingBookResolver.sanitizeDisplayName("e" + cp(0x0301) + ".epub"),
        )
    }

    @Test
    fun sanitizeCapsLengthWhilePreservingTheExtension() {
        val cleaned = IncomingBookResolver.sanitizeDisplayName("a".repeat(10_000) + ".epub")
        assertTrue("length ${cleaned.length}", cleaned.length <= IncomingBookResolver.MAX_NAME_CHARS)
        assertTrue("extension lost: $cleaned", cleaned.endsWith(".epub"))
    }

    @Test
    fun sanitizeCapsLengthWhenThereIsNoUsableExtension() {
        assertEquals(
            IncomingBookResolver.MAX_NAME_CHARS,
            IncomingBookResolver.sanitizeDisplayName("b".repeat(10_000)).length,
        )
        // A 10k-char "extension" is not an extension; the cap still holds.
        assertTrue(
            IncomingBookResolver.sanitizeDisplayName("c." + "d".repeat(10_000)).length
                <= IncomingBookResolver.MAX_NAME_CHARS,
        )
    }

    @Test
    fun sanitizeDoesNotSplitASurrogatePair() {
        // Astral-plane characters truncated at an odd code-unit boundary would otherwise
        // leave a lone high surrogate at the tail. U+20B9F is a CJK extension-B ideograph.
        val cleaned = IncomingBookResolver.sanitizeDisplayName("x" + cp(0x20B9F).repeat(400))
        assertTrue("the name was not preserved at all: $cleaned", cleaned.startsWith("x" + cp(0x20B9F)))
        assertTrue(cleaned.length <= IncomingBookResolver.MAX_NAME_CHARS)
        assertTrue("lone high surrogate at the tail", !Character.isHighSurrogate(cleaned.last()))
    }

    @Test
    fun sanitizeFallsBackToUntitledPlusTheResolvedExtension() {
        assertEquals("Untitled", IncomingBookResolver.sanitizeDisplayName(null))
        assertEquals("Untitled", IncomingBookResolver.sanitizeDisplayName(""))
        assertEquals("Untitled", IncomingBookResolver.sanitizeDisplayName("   \n   "))
        assertEquals("Untitled", IncomingBookResolver.sanitizeDisplayName(cp(0x200F) + cp(0x202E)))
        assertEquals("Untitled.epub", IncomingBookResolver.sanitizeDisplayName(null, BookFormat.epub))
        assertEquals("Untitled.azw3", IncomingBookResolver.sanitizeDisplayName("  ", BookFormat.azw3))
    }

    @Test
    fun aTraversingDisplayNameYieldsATitleWithNoTraversal() = runTest {
        val target = uri("trav1/opaque-id")
        declare("../../etc/passwd.epub")
        serve(target, opaqueBytes())

        val pending = open(target)
        assertEquals(BookFormat.epub, pending.format)
        assertTrue("traversal survived: ${pending.displayName}", !pending.displayName.contains(".."))
        assertTrue("separator survived: ${pending.displayName}", !pending.displayName.contains('/'))
        assertEquals("passwd.epub", pending.displayName)
        pending.stream.close()
    }

    @Test
    fun sanitizeStripsPathSeparatorsAndBareDotSegments() {
        assertEquals("passwd.epub", IncomingBookResolver.sanitizeDisplayName("../../etc/passwd.epub"))
        assertEquals("passwd.epub", IncomingBookResolver.sanitizeDisplayName("..\\..\\etc\\passwd.epub"))
        assertEquals("Untitled", IncomingBookResolver.sanitizeDisplayName("../../.."))
        assertEquals("Untitled", IncomingBookResolver.sanitizeDisplayName("."))
    }

    // ---- sourceUri cap -----------------------------------------------------

    @Test
    fun theSourceUriIsCappedOnTheWayOut() = runTest {
        val target = uri("cap1/" + "z".repeat(4000) + ".epub")
        declare(null)
        serve(target, opaqueBytes())

        val pending = open(target)
        assertEquals(IncomingBookResolver.MAX_SOURCE_URI_CHARS, pending.sourceUri.length)
        assertTrue(target.toString().startsWith(pending.sourceUri))
        pending.stream.close()
    }

    @Test
    fun theCapsAreTheDocumentedValues() {
        assertEquals(200, IncomingBookResolver.MAX_NAME_CHARS)
        assertEquals(2048, IncomingBookResolver.MAX_SOURCE_URI_CHARS)
    }
}
