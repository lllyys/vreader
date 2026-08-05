// Purpose: feature #155 WI-3 — `BookMagicSniffer.sniff`, the last-resort format
// detector that runs on ATTACKER-CONTROLLED bytes (any app on the device can send
// VReader an intent, and ImportActivity is exported). The sniffer is a security
// boundary, so its three structural properties are asserted on EVERY input this file
// feeds it, not just on the interesting ones:
//
//   1. it reads at most PROBE_BYTES (4096) — proven by a counting stream, which is
//      also what proves "never inflates": you cannot inflate bytes you never read;
//   2. it always rewinds — proven by reading the stream to EOF afterwards and
//      comparing to the original bytes;
//   3. it never throws — every malformed shape returns null.
//
// `assertSniff` enforces all three; individual tests only state the expected format.
//
// Every negative case ALSO re-asserts that a VALID stored-mimetype EPUB still sniffs
// as `epub`. Without that pairing a sniffer that threw on everything and caught
// broadly would pass all seven negatives while silently rejecting real books — the
// negatives must prove DISCRIMINATION, not blanket failure.
//
// Fixtures are synthetic by necessity: this is a CI JVM unit test and cannot read the
// gitignored `test-books/` tree (the "real books first" exception for CI unit tests),
// and the ZIP-header negatives need byte-exact local headers no real EPUB provides.
package com.vreader.app.imports

import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.FilterInputStream
import java.io.InputStream

class BookMagicSnifferTest {

    // ---- harness -----------------------------------------------------------

    /** Counts every byte the sniffer actually pulls; mark/reset delegate to the source. */
    private class CountingInputStream(source: InputStream) : FilterInputStream(source) {
        var bytesRead = 0L
            private set

        override fun read(): Int {
            val b = super.read()
            if (b >= 0) bytesRead++
            return b
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            val n = super.read(b, off, len)
            if (n > 0) bytesRead += n
            return n
        }
    }

    /**
     * Sniffs [bytes] and asserts the three structural properties before returning the
     * verdict. Every test in this file goes through here.
     */
    private fun assertSniff(bytes: ByteArray): BookFormat? {
        val counting = CountingInputStream(ByteArrayInputStream(bytes))
        val verdict = BookMagicSniffer.sniff(counting)
        assertTrue(
            "sniff read ${counting.bytesRead} bytes, past the ${BookMagicSniffer.PROBE_BYTES}-byte probe",
            counting.bytesRead <= BookMagicSniffer.PROBE_BYTES,
        )
        assertArrayEquals("sniff did not rewind the stream", bytes, counting.readBytes())
        return verdict
    }

    // ---- ZIP local-file-header fixtures ------------------------------------

    private fun ByteArrayOutputStream.u16(value: Int) {
        write(value and 0xFF); write((value ushr 8) and 0xFF)
    }

    private fun ByteArrayOutputStream.u32(value: Long) {
        write((value and 0xFF).toInt()); write(((value ushr 8) and 0xFF).toInt())
        write(((value ushr 16) and 0xFF).toInt()); write(((value ushr 24) and 0xFF).toInt())
    }

    /**
     * A ZIP local file header, field by field, so each negative can vary exactly one
     * field away from a valid OCF `mimetype` entry.
     */
    private fun zipHeader(
        signature: ByteArray = byteArrayOf(0x50, 0x4B, 0x03, 0x04),
        method: Int = 0,
        compressed: Long = 20,
        uncompressed: Long = 20,
        name: String = "mimetype",
        nameLenOverride: Int? = null,
        extra: ByteArray = ByteArray(0),
        extraLenOverride: Int? = null,
        content: ByteArray = "application/epub+zip".toByteArray(Charsets.US_ASCII),
        trailing: ByteArray = ByteArray(64) { 0x41 },
    ): ByteArray = ByteArrayOutputStream().apply {
        write(signature)
        u16(0x0A)                  // @4  version needed
        u16(0)                     // @6  general purpose flags
        u16(method)                // @8  compression method
        u16(0); u16(0)             // @10 mod time / date
        u32(0)                     // @14 crc32
        u32(compressed)            // @18 compressed size
        u32(uncompressed)          // @22 uncompressed size
        u16(nameLenOverride ?: name.toByteArray(Charsets.US_ASCII).size)   // @26
        u16(extraLenOverride ?: extra.size)                                // @28
        write(name.toByteArray(Charsets.US_ASCII))
        write(extra)
        write(content)
        write(trailing)
    }.toByteArray()

    private fun validEpub(): ByteArray = zipHeader()

    /** Every negative must coexist with a working positive, or it proves nothing. */
    private fun assertAValidEpubStillSniffsAsEpub() {
        assertEquals(
            "the negative passed but a VALID epub is also rejected — blanket failure, not discrimination",
            BookFormat.epub,
            assertSniff(validEpub()),
        )
    }

    // ---- positives ---------------------------------------------------------

    @Test
    fun pdfMagicAtOffsetZero() {
        assertEquals(BookFormat.pdf, assertSniff("%PDF-1.7\n%âãÏÓ".toByteArray(Charsets.ISO_8859_1)))
    }

    @Test
    fun storedMimetypeZipIsEpub() {
        assertEquals(BookFormat.epub, assertSniff(validEpub()))
    }

    @Test
    fun bookmobiAtOffsetSixty() {
        val bytes = ByteArray(60) { 0x20 } + "BOOKMOBI".toByteArray(Charsets.US_ASCII) + ByteArray(32)
        assertEquals(BookFormat.azw3, assertSniff(bytes))
    }

    @Test
    fun bookmobiAnywhereElseIsNotAzw3() {
        // The offset is part of the signature: MOBI's magic lives at 60, and a stray
        // "BOOKMOBI" earlier in a file must not be enough.
        val bytes = "BOOKMOBI".toByteArray(Charsets.US_ASCII) + ByteArray(120) { 0x00 }
        assertNull(assertSniff(bytes))
    }

    @Test
    fun utf8TextIsTxt() {
        assertEquals(BookFormat.txt, assertSniff("Call me Ishmael.\nSome years ago...".toByteArray()))
    }

    @Test
    fun utf8CjkTextIsTxt() {
        assertEquals(BookFormat.txt, assertSniff("第一章 天地玄黄，宇宙洪荒。\n日月盈昃，辰宿列张。".toByteArray()))
    }

    @Test
    fun utf8RtlTextIsTxt() {
        assertEquals(BookFormat.txt, assertSniff("مرحبا بالعالم\nשלום עולם".toByteArray()))
    }

    @Test
    fun utf16LeWithBomIsTxt() {
        assertEquals(BookFormat.txt, assertSniff("Hello, 世界".toByteArray(Charsets.UTF_16LE).let { byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + it }))
    }

    @Test
    fun utf16BeWithBomIsTxt() {
        assertEquals(BookFormat.txt, assertSniff("Hello, 世界".toByteArray(Charsets.UTF_16BE).let { byteArrayOf(0xFE.toByte(), 0xFF.toByte()) + it }))
    }

    @Test
    fun aTextFileLongerThanTheProbeIsStillTxtAndOnlyTheProbeIsRead() {
        val bytes = "lorem ipsum dolor sit amet ".repeat(4000).toByteArray()
        assertTrue(bytes.size > BookMagicSniffer.PROBE_BYTES * 4)
        assertEquals(BookFormat.txt, assertSniff(bytes))
    }

    @Test
    fun aMultiByteCharSplitByTheProbeBoundaryIsNotAFalseNegative() {
        // The probe cuts at a fixed 4096 bytes, which lands mid-character for CJK text.
        // A truncated trailing sequence is "more input needed", not "malformed".
        val bytes = "漢".repeat(4000).toByteArray()   // 3 bytes each => 4096 splits a char
        assertTrue(bytes.size > BookMagicSniffer.PROBE_BYTES)
        assertEquals(BookFormat.txt, assertSniff(bytes))
    }

    // ---- negatives: each one its own test, each paired with a valid epub ----

    @Test
    fun randomBinaryIsNull() {
        // Deterministic, and deliberately opens with an invalid UTF-8 continuation
        // (0x80) plus embedded NULs so the verdict never depends on chance.
        val rng = kotlin.random.Random(20260804)
        val bytes = byteArrayOf(0x80.toByte(), 0x81.toByte(), 0x00, 0x00) + ByteArray(512) { rng.nextInt().toByte() }
        assertNull(assertSniff(bytes))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun deflatedFirstEntryIsNull() {
        assertNull(assertSniff(zipHeader(method = 8)))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun firstEntryNotNamedMimetypeIsNull() {
        assertNull(assertSniff(zipHeader(name = "META-INF")))          // same length, wrong name
        assertNull(assertSniff(zipHeader(name = "mimetypeX")))         // longer
        assertNull(assertSniff(zipHeader(name = "mime")))              // shorter
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun nonZeroExtraLengthIsNull() {
        // OCF forbids an extra field on the mimetype entry, and the check is also what
        // keeps the content offset a constant instead of attacker-chosen arithmetic.
        //
        // The first fixture SMUGGLES the media type into the extra field, so the bytes at
        // the constant offset 30+8 spell "application/epub+zip" and the DECLARED entry
        // content does not. Only the extra-length check rejects it — a plain
        // four-zero-bytes extra field would be rejected by the offset arithmetic anyway
        // and would therefore prove nothing about this check.
        val smuggled = zipHeader(
            extra = "application/epub+zip".toByteArray(Charsets.US_ASCII),
            content = ByteArray(20) { 0x00 },
        )
        assertNull(assertSniff(smuggled))
        assertNull(assertSniff(zipHeader(extra = ByteArray(4) { 0x00 })))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun declaredSizeOtherThanTwentyIsNull() {
        assertNull(assertSniff(zipHeader(compressed = 21, uncompressed = 21)))
        assertNull(assertSniff(zipHeader(compressed = 0, uncompressed = 0)))
        assertNull(assertSniff(zipHeader(compressed = 20, uncompressed = 21)))
        assertNull(assertSniff(zipHeader(compressed = 21, uncompressed = 20)))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun truncatedLocalHeaderIsNull() {
        val full = validEpub()
        // Every truncation point inside the header, plus one just short of the content.
        for (cut in intArrayOf(4, 10, 20, 29, 30, 37, 45, 57)) {
            assertNull("truncation at $cut byte(s) must be null", assertSniff(full.copyOf(cut)))
        }
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun aCraftedHeaderCannotSteerTheReadPastTheProbe() {
        // A declared filename or extra length far beyond the buffer is the classic
        // out-of-bounds-read lure. It must be rejected, never trusted as an offset.
        assertNull(assertSniff(zipHeader(nameLenOverride = 60_000)))
        assertNull(assertSniff(zipHeader(extraLenOverride = 60_000)))
        assertNull(assertSniff(zipHeader(nameLenOverride = 65_535, extraLenOverride = 65_535)))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun contentBytesOtherThanTheEpubMediaTypeIsNull() {
        assertNull(assertSniff(zipHeader(content = "application/zip+xxxx".toByteArray(Charsets.US_ASCII))))
        assertNull(assertSniff(zipHeader(content = ByteArray(20) { 0x00 })))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun aZipBombShapedInputIsNeverInflated() {
        // A DEFLATE entry declaring a 4 GiB expansion. The proof that nothing is
        // inflated is the byte budget assertSniff enforces: the sniffer pulls at most
        // 4096 bytes and hands them to no decompressor.
        val bomb = zipHeader(
            method = 8,
            compressed = 1024,
            uncompressed = 0xFFFFFFFFL,
            content = ByteArray(1024) { 0x00 },
            trailing = ByteArray(64 * 1024) { 0x00 },
        )
        assertTrue(bomb.size > BookMagicSniffer.PROBE_BYTES)
        assertNull(assertSniff(bomb))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun aWrongZipSignatureIsNotTreatedAsAZip() {
        // "PK\x05\x06" (end-of-central-directory) and "PK\x07\x08" are not local headers.
        assertNull(assertSniff(zipHeader(signature = byteArrayOf(0x50, 0x4B, 0x05, 0x06), trailing = ByteArray(64))))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun zeroByteInputIsNull() {
        assertNull(assertSniff(ByteArray(0)))
        assertAValidEpubStillSniffsAsEpub()
    }

    @Test
    fun inputShorterThanTheProbeWindowIsHandled() {
        assertEquals(BookFormat.txt, assertSniff("hi".toByteArray()))
        assertEquals(BookFormat.pdf, assertSniff("%PDF-".toByteArray()))
        assertNull(assertSniff(byteArrayOf(0x50, 0x4B, 0x03, 0x04)))   // bare zip magic
        assertNull(assertSniff(byteArrayOf(0x00)))                     // a lone NUL is not text
    }

    @Test
    fun theSnifferNeverReturnsMd() {
        // Markdown has no magic (plan D3/§12): it is text, so it sniffs as txt. A
        // sniffer that guessed `md` would mint a second library row for a file already
        // imported as txt, and vice versa.
        val markdown = "# Chapter One\n\n* a bullet\n\n> a quote\n\n```kotlin\nval x = 1\n```\n"
        assertEquals(BookFormat.txt, assertSniff(markdown.toByteArray()))
    }

    // ---- stream discipline -------------------------------------------------

    @Test
    fun aNonMarkSupportingStreamIsRejectedWithoutConsumingAByte() {
        // The sniffer cannot rewind such a stream, so consuming even one byte would
        // corrupt the hash the caller is about to take. Wrapping is the RESOLVER's job.
        val source = object : InputStream() {
            var reads = 0
            override fun read(): Int { reads++; return -1 }
            override fun markSupported(): Boolean = false
        }
        assertNull(BookMagicSniffer.sniff(source))
        assertEquals(0, source.reads)
    }

    @Test
    fun theProbeBudgetIsFourKilobytes() {
        assertEquals(4096, BookMagicSniffer.PROBE_BYTES)
    }
}
