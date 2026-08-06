// Purpose: feature #152 WI-3 — locates the embedded cover image inside a MOBI/AZW3 file by parsing
// the PDB record table, the MOBI header, and the EXTH records. Pure JVM: no Android imports, no
// WebView, no NDK. A Kotlin port of `vreader/Services/AZW3/MOBICoverExtractor.swift`, which is the
// reference implementation for the field offsets.
//
// Pipeline: open -> PDB header (numRecords) -> record offset table -> record 0 (PalmDOC + MOBI
// header) -> EXTH scan for type 201/202 -> slice the target image record -> raw bytes.
// `MobiCoverExtractor` is the adapter that decodes those bytes into a Bitmap.
//
// Key decisions — the three places a naive Kotlin port of the Swift goes wrong:
//
// 1. **Every big-endian read is MASKED.** Kotlin's `ByteArray[i]` is signed. The real 6.3 MB CJK
//    AZW3's `numRecords` field is `00 99`, so an unmasked read yields -103: an unmasked port fails
//    on the FIRST field it reads, on a real book.
// 2. **32-bit fields are `Long`, not `Int`.** The MOBI "not set" sentinel is 0xFFFFFFFF, which is -1
//    as a Kotlin `Int` and therefore compares as SET against a Long bound. The result is not an
//    error but silently wrong bytes: the target resolves to `firstImageIndex - 1`, a text record.
// 3. **Spans are validated BEFORE allocating.** iOS reads a memory-mapped `Data` whose `count` is an
//    implicit ceiling; a `RandomAccessFile` has none. The record's end comes straight from the
//    attacker-controlled record table, and a table entry of 0x7FFFFFF0 computes a 2,147,138,052-byte
//    length. `OutOfMemoryError` is an `Error`, not an `Exception`, so it would escape the
//    "no extractor throws" contract entirely and kill the app-scope backfill for the whole library.
//    [sliceRecord] therefore rejects unbacked and oversized spans before `ByteArray` is ever sized.
//
// Failure classification — CONTENT vs ACCESS, not exception type (see `CoverResult`): the OPEN maps
// to `Failed`; every subsequent bounded read maps `EOFException` (the file is shorter than its own
// table claims — a structural property) to `None`, and any other `IOException` (a genuine device
// read error) to `Failed`.
//
// Known limitation: a combined MOBI6+KF8 `.azw3` has two parts and this parser reads record 0 of the
// FIRST part only, exactly as iOS does. If a book's art lives solely in the KF8 part the result is
// `None` — a fallback cover, never a crash. No fixture in this repo's corpus is dual-part, so the
// limitation ships untested; it is recorded as a named residual rather than silently omitted.
//
// @coordinates-with: MobiCoverExtractor.kt, CoverResult.kt
package com.vreader.app.library.covers

import java.io.EOFException
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.io.RandomAccessFile

/** What [MobiCoverParser] found. Mirrors [CoverResult] but carries bytes, so it stays Android-free. */
sealed interface MobiCoverParseResult {

    /**
     * The bytes of the record the EXTH cover/thumbnail offset points at.
     *
     * Located, not validated: the payload may still not be a decodable image (DRM), which is the
     * adapter's call to make.
     */
    class Art(val bytes: ByteArray) : MobiCoverParseResult

    /** Reachable and structurally parsed; no usable cover record. */
    data object None : MobiCoverParseResult

    /** The file could not be accessed at all. */
    data object Failed : MobiCoverParseResult
}

object MobiCoverParser {

    /**
     * A single record larger than this is rejected unread. A cover this large is not a cover, and
     * the cap is what bounds the allocation on a genuinely huge file, where the file-length check
     * alone would still permit buffering hundreds of megabytes.
     */
    const val MAX_RECORD_BYTES: Long = 64L * 1024 * 1024

    private const val PDB_HEADER_SIZE = 78
    private const val RECORD_ENTRY_SIZE = 8
    private const val NUM_RECORDS_OFFSET = 76

    /** 16-byte PalmDOC header + enough MOBI header to reach the EXTH flags at 128. */
    private const val MIN_RECORD0_SIZE = 132
    private const val MOBI_MAGIC_OFFSET = 16
    private const val MOBI_HEADER_LENGTH_OFFSET = 20
    private const val FIRST_IMAGE_INDEX_OFFSET = 108      // 16 + 92
    private const val EXTH_FLAGS_OFFSET = 128             // 16 + 112

    private const val EXTH_PRESENT_BIT = 0x40L
    private const val EXTH_COVER_TYPE = 201L
    private const val EXTH_THUMBNAIL_TYPE = 202L
    private const val EXTH_OFFSET_RECORD_LENGTH = 12L

    /** The MOBI/EXTH "not set" sentinel. `Long` deliberately — as an `Int` this is -1. */
    private const val NOT_SET = 0xFFFF_FFFFL

    fun parse(file: File): MobiCoverParseResult {
        val handle = try {
            RandomAccessFile(file, "r")
        } catch (e: FileNotFoundException) {
            return MobiCoverParseResult.Failed          // missing, unreadable, or not a regular file
        } catch (e: SecurityException) {
            return MobiCoverParseResult.Failed
        }
        return handle.use { classify(it) }
    }

    /**
     * Runs the parse and maps read failures onto the content-vs-access split.
     *
     * On a STABLE file `EOFException` is unreachable: every span is checked against `raf.length()`
     * before it is read, which is the point — a bound is validated, never discovered by exception.
     * It becomes reachable when the file SHRINKS mid-parse (removable storage, a cloud-backed SAF
     * document being re-downloaded), and that is a structural property of the bytes now present, so
     * it classifies `None` like every other short-file case. Any other `IOException` is a genuine
     * device read error → `Failed`, retry.
     *
     * Internal rather than private so a test can drive it with a handle that over-reports its
     * length, which is the shrink-mid-parse race made deterministic.
     */
    internal fun classify(raf: RandomAccessFile): MobiCoverParseResult =
        try {
            parseOpened(raf)
        } catch (e: EOFException) {
            MobiCoverParseResult.None
        } catch (e: IOException) {
            MobiCoverParseResult.Failed
        }

    private fun parseOpened(raf: RandomAccessFile): MobiCoverParseResult {
        val fileLength = raf.length()
        if (fileLength < PDB_HEADER_SIZE) return MobiCoverParseResult.None

        val header = read(raf, 0, PDB_HEADER_SIZE)
        val numRecords = readUInt16BE(header, NUM_RECORDS_OFFSET)
        if (numRecords <= 0) return MobiCoverParseResult.None

        val tableBytes = numRecords.toLong() * RECORD_ENTRY_SIZE
        if (PDB_HEADER_SIZE + tableBytes > fileLength) return MobiCoverParseResult.None

        val table = read(raf, PDB_HEADER_SIZE.toLong(), tableBytes.toInt())
        val offsets = LongArray(numRecords) { readUInt32BE(table, it * RECORD_ENTRY_SIZE) }

        val record0 = sliceRecord(raf, offsets, 0, fileLength) ?: return MobiCoverParseResult.None
        if (record0.size < MIN_RECORD0_SIZE) return MobiCoverParseResult.None
        if (!matchesAscii(record0, MOBI_MAGIC_OFFSET, "MOBI")) return MobiCoverParseResult.None

        // The image records start at an ABSOLUTE record index; EXTH 201/202 are RELATIVE to it.
        // The committed iOS fixture `divider-azw3.azw3` carries the unset sentinel here (FF FF FF FF)
        // WITH EXTH present, so the case is real.
        //
        // The check below is REDUNDANT while the read above is `Long`, and provably so: `numRecords`
        // is a u16, so `0xFFFFFFFF + rel` always exceeds it and the range check would reject the
        // target anyway. It is kept deliberately — it states the intent at the field it belongs to,
        // it costs one comparison, and it is the guard that would still hold if the read were ever
        // narrowed back to `Int` (where the sentinel becomes -1 and resolves to a real, wrong
        // record). Measured: mutating it away fails no test, which is why this note exists rather
        // than a test that cannot be written.
        val firstImageIndex = readUInt32BE(record0, FIRST_IMAGE_INDEX_OFFSET)
        if (firstImageIndex == NOT_SET) return MobiCoverParseResult.None

        val exthFlags = readUInt32BE(record0, EXTH_FLAGS_OFFSET)
        if (exthFlags and EXTH_PRESENT_BIT == 0L) return MobiCoverParseResult.None

        val mobiHeaderLength = readUInt32BE(record0, MOBI_HEADER_LENGTH_OFFSET)
        val relativeIndex = scanExthForImageIndex(record0, MOBI_MAGIC_OFFSET + mobiHeaderLength)
            ?: return MobiCoverParseResult.None

        // Both operands are at most 0xFFFFFFFE, so the sum cannot overflow a Long.
        val target = firstImageIndex + relativeIndex
        if (target >= numRecords) return MobiCoverParseResult.None

        val image = sliceRecord(raf, offsets, target.toInt(), fileLength)
            ?: return MobiCoverParseResult.None
        return MobiCoverParseResult.Art(image)
    }

    /**
     * Scans the EXTH block for the cover (201) and thumbnail (202) offsets, preferring the cover.
     *
     * Returns the index RELATIVE to `firstImageIndex`, or null when the block is absent, malformed,
     * or carries neither offset set to anything but the sentinel. Every loop bound is derived from
     * `record0.size`, so a record count of four billion terminates at the end of the buffer rather
     * than running away.
     */
    private fun scanExthForImageIndex(record0: ByteArray, exthStart: Long): Long? {
        if (exthStart < 0 || exthStart + 12 > record0.size) return null
        val start = exthStart.toInt()
        if (!matchesAscii(record0, start, "EXTH")) return null

        val exthLength = readUInt32BE(record0, start + 4)
        val recordCount = readUInt32BE(record0, start + 8)
        if (exthStart + exthLength > record0.size) return null

        var cover: Long? = null
        var thumbnail: Long? = null
        var cursor = start + 12
        var seen = 0L

        while (seen < recordCount) {
            if (cursor + 8 > record0.size) break
            val type = readUInt32BE(record0, cursor)
            val length = readUInt32BE(record0, cursor + 4)
            // `length` counts its own 8-byte header, so anything below 8 is malformed — and
            // advancing by it would never terminate.
            if (length < 8) break
            if (cursor + length > record0.size) break

            if (length == EXTH_OFFSET_RECORD_LENGTH) {
                when (type) {
                    EXTH_COVER_TYPE -> cover = readUInt32BE(record0, cursor + 8)
                    EXTH_THUMBNAIL_TYPE -> thumbnail = readUInt32BE(record0, cursor + 8)
                }
            }
            cursor += length.toInt()
            seen++
        }

        return when {
            cover != null && cover < NOT_SET -> cover
            thumbnail != null && thumbnail < NOT_SET -> thumbnail
            else -> null
        }
    }

    /**
     * Reads record [index], which spans from its own offset to the next record's offset (or EOF for
     * the last record).
     *
     * Returns null — never throws, never allocates — for any span the file does not back or that
     * exceeds [MAX_RECORD_BYTES]. All three guards run BEFORE the `ByteArray` is sized; see the
     * file header for why that ordering is the whole point.
     */
    private fun sliceRecord(
        raf: RandomAccessFile,
        offsets: LongArray,
        index: Int,
        fileLength: Long,
    ): ByteArray? {
        if (index < 0 || index >= offsets.size) return null
        val start = offsets[index]
        val end = if (index + 1 < offsets.size) offsets[index + 1] else fileLength

        if (start < 0 || start > fileLength) return null      // start beyond EOF
        if (end <= start || end > fileLength) return null     // end beyond EOF, or non-monotonic
        if (end - start > MAX_RECORD_BYTES) return null       // implausible for a cover

        return read(raf, start, (end - start).toInt())
    }

    /** Reads exactly [length] bytes at [offset]. Throws `EOFException` if the file is shorter. */
    private fun read(raf: RandomAccessFile, offset: Long, length: Int): ByteArray {
        raf.seek(offset)
        val buffer = ByteArray(length)
        raf.readFully(buffer)
        return buffer
    }

    private fun readUInt16BE(buffer: ByteArray, offset: Int): Int =
        ((buffer[offset].toInt() and 0xFF) shl 8) or
            (buffer[offset + 1].toInt() and 0xFF)

    private fun readUInt32BE(buffer: ByteArray, offset: Int): Long =
        ((buffer[offset].toLong() and 0xFF) shl 24) or
            ((buffer[offset + 1].toLong() and 0xFF) shl 16) or
            ((buffer[offset + 2].toLong() and 0xFF) shl 8) or
            (buffer[offset + 3].toLong() and 0xFF)

    private fun matchesAscii(buffer: ByteArray, offset: Int, text: String): Boolean {
        if (offset < 0 || offset + text.length > buffer.size) return false
        return text.indices.all { (buffer[offset + it].toInt() and 0xFF) == text[it].code }
    }
}
