// Purpose: feature #155 WI-3 (plan D7) — last-resort format HINT from the leading bytes
// of an INBOUND stream. `ImportActivity` is exported, so any app on the device can hand
// VReader a hostile payload: this is a security boundary, not a convenience.
//
// SCOPE OF THE ANSWER: this is a bounded-prefix HINT, not validation. A verdict of `epub`
// means "the first 4096 bytes have an OCF-shaped stored `mimetype` header", NOT "this is a
// valid EPUB" — no 4096-byte prefix can prove a central directory exists. Real validation
// belongs to the reader that later opens the book. The hint is only ever used to fill a
// gap the file name and MIME type left (plan D3), and every other step of that chain
// already trusts an attacker-supplied declaration, so a false positive costs a failed open,
// never a privilege.
//
// Three properties are STRUCTURAL, not merely intended:
//   1. AT MOST [PROBE_BYTES] ARE READ. `fill` is the only reader in the file and it is
//      bounded by the probe array; classification then runs on that ByteArray and has no
//      access to the stream at all, so no crafted header can make it read more.
//   2. NOTHING IS EVER INFLATED. There is no ZIP/Inflater dependency anywhere in this file
//      — that STATIC fact is the real proof (a byte budget alone would not be: 4096
//      compressed bytes can still expand to gigabytes if handed to a decompressor). An
//      EPUB is hinted from the literal, STORED `mimetype` local file header only.
//   3. THE STREAM IS ALWAYS REWOUND, and a rewind that fails vetoes the verdict — the
//      caller is about to hash these bytes for the canonical key, so a consumed stream
//      would silently corrupt a book's identity.
//
// It NEVER returns `md`: Markdown has no magic and is indistinguishable from plain text,
// and guessing would split one book across two library rows (plan D3 / §12).
//
// @coordinates-with: IncomingBookResolver (step 4 of the resolution chain; it owns the
//   mark-support wrapping this file requires and closes the stream on every throw)
package com.vreader.app.imports

import vreader.contracts.BookFormat
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import kotlin.coroutines.cancellation.CancellationException

object BookMagicSniffer {
    /** The whole byte budget. Nothing in this file reads past it. */
    const val PROBE_BYTES = 4096

    private val PDF_MAGIC = "%PDF-".toByteArray(Charsets.US_ASCII)
    private val ZIP_LOCAL_FILE_HEADER = byteArrayOf(0x50, 0x4B, 0x03, 0x04)
    private val MOBI_MAGIC = "BOOKMOBI".toByteArray(Charsets.US_ASCII)
    private const val MOBI_MAGIC_OFFSET = 60

    /** OCF requires the first entry to be exactly this, STORED, unencrypted, no extra field. */
    private val OCF_ENTRY_NAME = "mimetype".toByteArray(Charsets.US_ASCII)
    private val OCF_MEDIA_TYPE = "application/epub+zip".toByteArray(Charsets.US_ASCII)
    private const val LOCAL_HEADER_SIZE = 30
    private const val METHOD_STORED = 0

    /** General-purpose bit 0 = encrypted, bit 3 = sizes deferred to a data descriptor. */
    private const val REJECTED_ZIP_FLAGS = 0x0009

    private val UTF8_BOM = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
    private val UTF16BE_BOM = byteArrayOf(0xFE.toByte(), 0xFF.toByte())
    private val UTF16LE_BOM = byteArrayOf(0xFF.toByte(), 0xFE.toByte())

    /** Why the probe read stopped — decoding needs to tell a real EOF from a full buffer. */
    private enum class ProbeEnd { FULL, EOF, ZERO }

    private class Probe(val length: Int, val end: ProbeEnd)

    /**
     * Classifies [input] from its first [PROBE_BYTES] bytes and leaves the stream exactly
     * where it found it. Returns null for anything unrecognised, malformed, empty, or not
     * mark-supporting.
     *
     * Malformed bytes and ordinary stream I/O failures return null rather than throwing.
     * The two deliberate exceptions: [CancellationException] is rethrown (structured
     * concurrency is never a "this looks like binary" answer) and JVM `Error`s propagate
     * (pretending an OOM is a format verdict would be worse than crashing). The caller
     * closes the stream on any throw, so a cancellation that skips the rewind is harmless.
     *
     * A non-mark-supporting stream is REFUSED WITHOUT READING A BYTE: consuming bytes that
     * cannot be put back would corrupt the caller's hash. Wrapping is the caller's job.
     */
    fun sniff(input: InputStream): BookFormat? {
        if (guarded { input.markSupported() } != true) return null

        val buffer = ByteArray(PROBE_BYTES)
        val probe = guarded {
            input.mark(PROBE_BYTES + 1)
            fill(input, buffer)
        }

        // Rewind unconditionally, whatever happened above, and let its success gate the
        // verdict: a stream we could not restore is one the caller must not import.
        val rewound = guarded { input.reset(); true } == true
        if (probe == null || !rewound) return null

        return guarded { classify(buffer, probe) }
    }

    /** Ordinary failures become null; cancellation and JVM errors keep propagating. */
    private inline fun <T> guarded(block: () -> T): T? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    /**
     * Fills [buffer] from [input] and reports why it stopped. The only read loop in this
     * file; `buffer.size` is the hard ceiling. A stream that returns 0 for a non-empty
     * request violates the InputStream contract and would spin forever, so it terminates
     * the loop rather than hanging an exported entry point — and is reported as [ProbeEnd.ZERO]
     * so decoding does not extend it the benefit of the doubt given to a real probe boundary.
     */
    private fun fill(input: InputStream, buffer: ByteArray): Probe {
        var total = 0
        while (total < buffer.size) {
            val read = input.read(buffer, total, buffer.size - total)
            if (read < 0) return Probe(total, ProbeEnd.EOF)
            if (read == 0) return Probe(total, ProbeEnd.ZERO)
            total += read
        }
        return Probe(total, ProbeEnd.FULL)
    }

    private fun classify(buffer: ByteArray, probe: Probe): BookFormat? {
        val length = probe.length
        return when {
            length <= 0 -> null
            startsWith(buffer, length, PDF_MAGIC) -> BookFormat.pdf
            // A ZIP is either an OCF EPUB or nothing; it never falls through to the text test.
            startsWith(buffer, length, ZIP_LOCAL_FILE_HEADER) -> sniffOcfZip(buffer, length)
            matchesAt(buffer, length, MOBI_MAGIC_OFFSET, MOBI_MAGIC) -> BookFormat.azw3
            decodesAsText(buffer, probe) -> BookFormat.txt
            else -> null
        }
    }

    /**
     * Reads the ZIP local file header FROM THE BUFFER ONLY and hints `epub` solely for a
     * literal OCF `mimetype` entry.
     *
     * The size and extra-length checks are OCF requirements AND the load-bearing safety
     * property: once the name length is pinned to 8 and the extra length to 0, the media
     * type's position is the CONSTANT 30 + 8 + 0. No field the input declares can steer
     * that offset, so a crafted header cannot walk the read out of the probe.
     */
    private fun sniffOcfZip(buffer: ByteArray, length: Int): BookFormat? {
        if (length < LOCAL_HEADER_SIZE) return null

        val flags = readU16(buffer, 6)
        val method = readU16(buffer, 8)
        val compressedSize = readU32(buffer, 18)
        val uncompressedSize = readU32(buffer, 22)
        val nameLength = readU16(buffer, 26)
        val extraLength = readU16(buffer, 28)

        if (flags and REJECTED_ZIP_FLAGS != 0) return null   // OCF: never encrypted, sizes inline
        if (method != METHOD_STORED) return null             // never inflate; STORED or nothing
        if (extraLength != 0) return null
        if (nameLength != OCF_ENTRY_NAME.size) return null
        if (compressedSize != OCF_MEDIA_TYPE.size.toLong()) return null
        if (uncompressedSize != OCF_MEDIA_TYPE.size.toLong()) return null

        val nameStart = LOCAL_HEADER_SIZE
        val mediaTypeStart = nameStart + OCF_ENTRY_NAME.size
        if (!matchesAt(buffer, length, nameStart, OCF_ENTRY_NAME)) return null
        if (!matchesAt(buffer, length, mediaTypeStart, OCF_MEDIA_TYPE)) return null
        return BookFormat.epub
    }

    /**
     * True when the probe decodes cleanly as UTF-8 or BOM-marked UTF-16 AND yields at
     * least one character.
     *
     * A trailing sequence cut by the 4096-byte boundary is "more input needed" rather than
     * malformed — otherwise every CJK file over 4 KiB would be a false negative. That
     * benefit of the doubt applies ONLY when the buffer actually filled: at a real EOF (or
     * a contract-violating zero-length read) an incomplete sequence is exactly what it
     * looks like, binary. Without that distinction the single byte `C2` would sniff as
     * text, decoding to nothing at all.
     *
     * A NUL or other non-whitespace C0 control also makes it binary, which is what turns
     * "random bytes are not text" into a structural answer instead of a probabilistic one.
     * Both rules only ever NARROW `txt`.
     */
    private fun decodesAsText(buffer: ByteArray, probe: Probe): Boolean {
        val length = probe.length
        val complete = probe.end != ProbeEnd.FULL
        return when {
            startsWith(buffer, length, UTF16BE_BOM) ->
                decodes(buffer, 2, length - 2, StandardCharsets.UTF_16BE, complete)
            startsWith(buffer, length, UTF16LE_BOM) ->
                decodes(buffer, 2, length - 2, StandardCharsets.UTF_16LE, complete)
            startsWith(buffer, length, UTF8_BOM) ->
                decodes(buffer, 3, length - 3, StandardCharsets.UTF_8, complete)
            else -> decodes(buffer, 0, length, StandardCharsets.UTF_8, complete)
        }
    }

    private fun decodes(
        bytes: ByteArray,
        offset: Int,
        count: Int,
        charset: Charset,
        endOfInput: Boolean,
    ): Boolean {
        if (count <= 0) return false
        val decoder = charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val output = CharBuffer.allocate(count + 1)   // decoded chars can never exceed bytes
        val result = decoder.decode(ByteBuffer.wrap(bytes, offset, count), output, endOfInput)
        if (!result.isUnderflow) return false
        output.flip()
        if (!output.hasRemaining()) return false      // decoded to nothing: not text
        while (output.hasRemaining()) {
            if (!isTextCharacter(output.get())) return false
        }
        return true
    }

    /** Tab, newline, vertical tab, form feed and carriage return are text; other C0 is not. */
    private fun isTextCharacter(ch: Char): Boolean = when {
        ch.code >= 0x20 && ch.code != 0x7F -> true
        ch == '\t' || ch == '\n' || ch == '\r' -> true
        ch.code == 0x0B || ch.code == 0x0C -> true
        else -> false
    }

    private fun startsWith(buffer: ByteArray, length: Int, magic: ByteArray): Boolean =
        matchesAt(buffer, length, 0, magic)

    private fun matchesAt(buffer: ByteArray, length: Int, offset: Int, magic: ByteArray): Boolean {
        if (offset < 0 || length < offset + magic.size) return false
        for (i in magic.indices) {
            if (buffer[offset + i] != magic[i]) return false
        }
        return true
    }

    private fun readU16(buffer: ByteArray, offset: Int): Int =
        (buffer[offset].toInt() and 0xFF) or ((buffer[offset + 1].toInt() and 0xFF) shl 8)

    private fun readU32(buffer: ByteArray, offset: Int): Long =
        (readU16(buffer, offset).toLong()) or (readU16(buffer, offset + 2).toLong() shl 16)
}
