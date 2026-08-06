// Purpose: feature #152 WI-3 — synthetic PDB/MOBI byte builders for `MobiCoverParserTest` and
// `MobiCoverResultClassificationTest`.
//
// Why synthetic rather than a real book (AGENTS.md "real books first" + its stated exceptions):
// these suites assert THIRTEEN STRUCTURAL FAILURE MODES — a truncated PDB header, a record table
// that runs past EOF, an EXTH record count of 4 billion, a record-table entry of 0x7FFFFFF0. None
// of those exist in any real book; they have to be constructed byte-exactly. That is the
// "deterministic tiny structure a real book cannot give cheaply" exception, and it is also the
// CI-unit-test exception (the JVM lane cannot read the gitignored `test-books/` tree). Same
// reasoning, same wording, as `imports/BookMagicSnifferTest.kt`.
//
// The real-book happy path is NOT covered here — see the erratum in the WI-3 HANDOFF: the asset
// the plan names (`androidTest/assets/foliate-spike/book.azw3`) is itself gitignored, so no
// committed test can consume it.
//
// Every integer this builder writes is big-endian, matching the MOBI spec and
// `vreader/Services/AZW3/MOBICoverExtractor.swift`.
package com.vreader.app.library.covers

import java.io.File

/** One EXTH record: `{type: u32, length: u32 (counts this 8-byte header), payload}`. */
internal data class ExthRecord(val type: Long, val payload: ByteArray, val lengthOverride: Long? = null) {
    val encodedLength: Long get() = lengthOverride ?: (8L + payload.size)
}

/** A 4-byte big-endian EXTH payload — the shape of a 201/202 cover-offset record. */
internal fun exthOffset(type: Long, value: Long): ExthRecord {
    val payload = ByteArray(4)
    putUInt32BE(payload, 0, value)
    return ExthRecord(type, payload)
}

internal fun putUInt16BE(buf: ByteArray, offset: Int, value: Int) {
    buf[offset] = ((value ushr 8) and 0xFF).toByte()
    buf[offset + 1] = (value and 0xFF).toByte()
}

internal fun putUInt32BE(buf: ByteArray, offset: Int, value: Long) {
    buf[offset] = ((value ushr 24) and 0xFF).toByte()
    buf[offset + 1] = ((value ushr 16) and 0xFF).toByte()
    buf[offset + 2] = ((value ushr 8) and 0xFF).toByte()
    buf[offset + 3] = (value and 0xFF).toByte()
}

internal fun putAscii(buf: ByteArray, offset: Int, text: String) {
    text.forEachIndexed { i, c -> buf[offset + i] = c.code.toByte() }
}

/**
 * Builds a record 0 (PalmDOC header + MOBI header + optional EXTH block).
 *
 * Field offsets are byte offsets into record 0 and match the Swift reference exactly:
 * `"MOBI"` at 16, MOBI header length at 20, firstImageIndex at 108 (= 16 + 92),
 * EXTH flags at 128 (= 16 + 112), EXTH block at 16 + mobiHeaderLength.
 */
internal fun buildRecord0(
    mobiMagic: String = "MOBI",
    mobiHeaderLength: Long = 232,
    firstImageIndex: Long = 2,
    exthFlags: Long = 0x40,
    exthMagic: String = "EXTH",
    exthRecords: List<ExthRecord>? = listOf(exthOffset(201, 0)),
    exthLengthOverride: Long? = null,
    exthRecordCountOverride: Long? = null,
    sizeOverride: Int? = null,
): ByteArray {
    val exthStart = (16L + mobiHeaderLength).toInt()
    val exthBody = exthRecords.orEmpty().fold(ByteArray(0)) { acc, rec ->
        val encoded = ByteArray(8 + rec.payload.size)
        putUInt32BE(encoded, 0, rec.type)
        putUInt32BE(encoded, 4, rec.encodedLength)
        rec.payload.copyInto(encoded, 8)
        acc + encoded
    }
    val exthTotal = if (exthRecords == null) 0 else 12 + exthBody.size
    val size = sizeOverride ?: (exthStart + exthTotal)
    val buf = ByteArray(size)

    putAscii(buf, 16, mobiMagic)
    putUInt32BE(buf, 20, mobiHeaderLength)
    putUInt32BE(buf, 108, firstImageIndex)
    putUInt32BE(buf, 128, exthFlags)

    if (exthRecords != null && exthStart + 12 <= size) {
        putAscii(buf, exthStart, exthMagic)
        putUInt32BE(buf, exthStart + 4, exthLengthOverride ?: exthTotal.toLong())
        putUInt32BE(buf, exthStart + 8, exthRecordCountOverride ?: exthRecords.size.toLong())
        val bodyRoom = minOf(exthBody.size, size - (exthStart + 12))
        if (bodyRoom > 0) exthBody.copyInto(buf, exthStart + 12, 0, bodyRoom)
    }
    return buf
}

/**
 * Assembles a PDB file from record payloads.
 *
 * @param numRecordsOverride writes a different count at file offset 76 than the table actually
 *   holds — the "record table truncated" and "numRecords == 0" modes.
 * @param offsetOverrides replaces the stored offset of record i WITHOUT moving its bytes — how the
 *   beyond-EOF, non-monotonic and over-cap spans are constructed.
 * @param truncateTo cuts the finished file short.
 * @param extendTo grows the file (sparsely, when written to disk) so the LAST record's span runs
 *   to the new EOF.
 */
internal fun buildPdb(
    records: List<ByteArray>,
    numRecordsOverride: Int? = null,
    offsetOverrides: Map<Int, Long> = emptyMap(),
    truncateTo: Int? = null,
): ByteArray {
    val declared = numRecordsOverride ?: records.size
    val headerSize = 78 + records.size * 8
    val offsets = LongArray(records.size)
    var cursor = headerSize.toLong()
    records.forEachIndexed { i, rec ->
        offsets[i] = cursor
        cursor += rec.size
    }

    val out = ByteArray(cursor.toInt())
    putAscii(out, 0, "vreader-fixture")
    putAscii(out, 60, "BOOK")
    putAscii(out, 64, "MOBI")
    putUInt16BE(out, 76, declared)
    records.indices.forEach { i ->
        putUInt32BE(out, 78 + i * 8, offsetOverrides[i] ?: offsets[i])
    }
    records.forEachIndexed { i, rec -> rec.copyInto(out, offsets[i].toInt()) }

    return if (truncateTo != null) out.copyOf(truncateTo) else out
}

/** A cover-bearing MOBI whose image record is [coverBytes], at absolute record index 2. */
internal fun buildCoverBook(
    coverBytes: ByteArray = jpegLike(64),
    firstImageIndex: Long = 2,
    exthRecords: List<ExthRecord>? = listOf(exthOffset(201, 0)),
    trailingRecords: List<ByteArray> = emptyList(),
): ByteArray = buildPdb(
    listOf(
        buildRecord0(firstImageIndex = firstImageIndex, exthRecords = exthRecords),
        ByteArray(32) { 0x41 },          // record 1 — text, never an image
        coverBytes,                      // record 2 — the cover
    ) + trailingRecords,
)

/** Bytes that begin with the JPEG SOI marker, so a decoder-shaped assertion is meaningful. */
internal fun jpegLike(size: Int): ByteArray = ByteArray(size).also {
    it[0] = 0xFF.toByte(); it[1] = 0xD8.toByte(); it[2] = 0xFF.toByte()
    for (i in 3 until size) it[i] = (i and 0x7F).toByte()
}

/** Writes [bytes] to a new file, optionally extending it SPARSELY to [extendTo] total bytes. */
internal fun writeFixture(dir: File, name: String, bytes: ByteArray, extendTo: Long? = null): File {
    val file = File(dir, name)
    file.writeBytes(bytes)
    if (extendTo != null) {
        java.io.RandomAccessFile(file, "rw").use { it.setLength(extendTo) }
    }
    return file
}
