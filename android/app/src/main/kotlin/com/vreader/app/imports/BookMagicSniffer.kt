// Purpose: feature #155 WI-3 (plan D7) — last-resort format detection from the leading
// bytes of an INBOUND stream. `ImportActivity` is exported, so any app on the device can
// hand VReader a hostile payload: this is a security boundary, not a convenience.
//
// Three properties are STRUCTURAL, not merely intended:
//   1. AT MOST [PROBE_BYTES] ARE READ. `fill` is the only reader in the file and it is
//      bounded by the probe array; classification then runs on that ByteArray and has no
//      access to the stream at all, so no crafted header can make it read more.
//   2. NOTHING IS EVER INFLATED. There is no ZIP/Inflater dependency here by design: an
//      EPUB is recognised from the OCF local file header's literal, STORED `mimetype`
//      entry. A zip bomb is impossible to trigger because nothing decompresses.
//   3. THE STREAM IS ALWAYS REWOUND, and a rewind that fails vetoes the verdict — the
//      caller is about to hash these bytes for the canonical key, so a consumed stream
//      would silently corrupt a book's identity.
//
// It NEVER returns `md`: Markdown has no magic and is indistinguishable from plain text,
// and guessing would split one book across two library rows (plan D3 / §12).
//
// @coordinates-with: IncomingBookResolver (step 4 of the resolution chain; it owns the
//   mark-support wrapping this file requires)
package com.vreader.app.imports

import vreader.contracts.BookFormat
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

object BookMagicSniffer {
    /** The whole byte budget. Nothing in this file reads past it. */
    const val PROBE_BYTES = 4096

    private val PDF_MAGIC = "%PDF-".toByteArray(Charsets.US_ASCII)
    private val ZIP_LOCAL_FILE_HEADER = byteArrayOf(0x50, 0x4B, 0x03, 0x04)
    private val MOBI_MAGIC = "BOOKMOBI".toByteArray(Charsets.US_ASCII)
    private const val MOBI_MAGIC_OFFSET = 60

    /** OCF requires the first entry to be exactly this, STORED, with no extra field. */
    private val OCF_ENTRY_NAME = "mimetype".toByteArray(Charsets.US_ASCII)
    private val OCF_MEDIA_TYPE = "application/epub+zip".toByteArray(Charsets.US_ASCII)
    private const val LOCAL_HEADER_SIZE = 30
    private const val METHOD_STORED = 0

    private val UTF8_BOM = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
    private val UTF16BE_BOM = byteArrayOf(0xFE.toByte(), 0xFF.toByte())
    private val UTF16LE_BOM = byteArrayOf(0xFF.toByte(), 0xFE.toByte())

    /**
     * Classifies [input] from its first [PROBE_BYTES] bytes and leaves the stream exactly
     * where it found it. Returns null — never throws — for anything unrecognised,
     * malformed, empty, or not mark-supporting.
     *
     * A non-mark-supporting stream is REFUSED WITHOUT READING A BYTE: consuming bytes that
     * cannot be put back would corrupt the caller's hash. Wrapping is the caller's job.
     */
    fun sniff(input: InputStream): BookFormat? {
        if (!input.markSupported()) return null

        val probe = ByteArray(PROBE_BYTES)
        val length = try {
            input.mark(PROBE_BYTES + 1)
            fill(input, probe)
        } catch (e: Exception) {
            -1
        }

        // Rewind unconditionally, whatever happened above, and let its success gate the
        // verdict: a stream we could not restore is one the caller must not import.
        val rewound = try {
            input.reset()
            true
        } catch (e: Exception) {
            false
        }
        if (length < 0 || !rewound) return null

        return try {
            classify(probe, length)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Fills [buffer] from [input], returning how many bytes arrived. The only read loop in
     * this file; `buffer.size` is the hard ceiling. A stream that returns 0 for a non-empty
     * request violates the InputStream contract and would spin forever, so it terminates
     * the loop rather than hanging an exported entry point.
     */
    private fun fill(input: InputStream, buffer: ByteArray): Int {
        var total = 0
        while (total < buffer.size) {
            val read = input.read(buffer, total, buffer.size - total)
            if (read <= 0) break
            total += read
        }
        return total
    }

    private fun classify(probe: ByteArray, length: Int): BookFormat? = when {
        length <= 0 -> null
        startsWith(probe, length, PDF_MAGIC) -> BookFormat.pdf
        // A ZIP is either an OCF EPUB or nothing; it never falls through to the text test.
        startsWith(probe, length, ZIP_LOCAL_FILE_HEADER) -> sniffOcfZip(probe, length)
        matchesAt(probe, length, MOBI_MAGIC_OFFSET, MOBI_MAGIC) -> BookFormat.azw3
        decodesAsText(probe, length) -> BookFormat.txt
        else -> null
    }

    /**
     * Reads the ZIP local file header FROM THE BUFFER ONLY and accepts `epub` solely for a
     * literal OCF `mimetype` entry.
     *
     * The size and extra-length checks are OCF requirements AND the load-bearing safety
     * property: once the name length is pinned to 8 and the extra length to 0, the media
     * type's position is the CONSTANT 30 + 8 + 0. No field the input declares can steer
     * that offset, so a crafted header cannot walk the read out of the probe.
     */
    private fun sniffOcfZip(probe: ByteArray, length: Int): BookFormat? {
        if (length < LOCAL_HEADER_SIZE) return null

        val method = readU16(probe, 8)
        val compressedSize = readU32(probe, 18)
        val uncompressedSize = readU32(probe, 22)
        val nameLength = readU16(probe, 26)
        val extraLength = readU16(probe, 28)

        if (method != METHOD_STORED) return null            // never inflate; STORED or nothing
        if (extraLength != 0) return null
        if (nameLength != OCF_ENTRY_NAME.size) return null
        if (compressedSize != OCF_MEDIA_TYPE.size.toLong()) return null
        if (uncompressedSize != OCF_MEDIA_TYPE.size.toLong()) return null

        val nameStart = LOCAL_HEADER_SIZE
        val mediaTypeStart = nameStart + OCF_ENTRY_NAME.size
        if (!matchesAt(probe, length, nameStart, OCF_ENTRY_NAME)) return null
        if (!matchesAt(probe, length, mediaTypeStart, OCF_MEDIA_TYPE)) return null
        return BookFormat.epub
    }

    /**
     * True when the probe decodes cleanly as UTF-8 or BOM-marked UTF-16.
     *
     * Two deliberate strictness choices, both of which only ever NARROW `txt`:
     * a trailing multi-byte sequence cut by the probe boundary is treated as "more input
     * needed" rather than malformed (otherwise every CJK file over 4 KiB would be a false
     * negative); and a NUL or other non-whitespace C0 control makes it binary, which is
     * what turns "random bytes are not text" into a structural answer instead of a
     * probabilistic one.
     */
    private fun decodesAsText(probe: ByteArray, length: Int): Boolean = when {
        startsWith(probe, length, UTF16BE_BOM) ->
            decodes(probe, 2, length - 2, StandardCharsets.UTF_16BE)
        startsWith(probe, length, UTF16LE_BOM) ->
            decodes(probe, 2, length - 2, StandardCharsets.UTF_16LE)
        startsWith(probe, length, UTF8_BOM) ->
            decodes(probe, 3, length - 3, StandardCharsets.UTF_8)
        else -> decodes(probe, 0, length, StandardCharsets.UTF_8)
    }

    private fun decodes(bytes: ByteArray, offset: Int, count: Int, charset: Charset): Boolean {
        if (count <= 0) return false
        val decoder = charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val output = CharBuffer.allocate(count + 1)   // decoded chars can never exceed bytes
        // endOfInput = false: a sequence truncated by the probe boundary is UNDERFLOW.
        val result = decoder.decode(ByteBuffer.wrap(bytes, offset, count), output, false)
        if (!result.isUnderflow) return false
        output.flip()
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

    private fun startsWith(probe: ByteArray, length: Int, magic: ByteArray): Boolean =
        matchesAt(probe, length, 0, magic)

    private fun matchesAt(probe: ByteArray, length: Int, offset: Int, magic: ByteArray): Boolean {
        if (offset < 0 || length < offset + magic.size) return false
        for (i in magic.indices) {
            if (probe[offset + i] != magic[i]) return false
        }
        return true
    }

    private fun readU16(probe: ByteArray, offset: Int): Int =
        (probe[offset].toInt() and 0xFF) or ((probe[offset + 1].toInt() and 0xFF) shl 8)

    private fun readU32(probe: ByteArray, offset: Int): Long =
        (readU16(probe, offset).toLong()) or (readU16(probe, offset + 2).toLong() shl 16)
}
