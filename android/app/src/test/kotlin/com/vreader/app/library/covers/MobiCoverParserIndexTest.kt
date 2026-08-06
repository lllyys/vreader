// Purpose: feature #152 WI-3 — how `MobiCoverParser` decides WHICH record is the cover: the EXTH
// scan, the 201-over-202 preference, the relative-to-firstImageIndex arithmetic, and the three
// decoding traps a Kotlin port of `vreader/Services/AZW3/MOBICoverExtractor.swift` falls into.
// Structural failure modes live in `MobiCoverParserTest`.
//
// The traps, each with a case here that a mutation of the fix would fail:
//
//   1. Every big-endian read is MASKED. Kotlin's `ByteArray[i]` is signed, and the real 6.3 MB CJK
//      AZW3's `numRecords` field is `00 99` — an unmasked read yields -103, so an unmasked port
//      fails on the FIRST field it reads, on a real book.
//   2. 32-bit fields are `Long`, not `Int`. The "not set" sentinel 0xFFFFFFFF is -1 as an `Int`,
//      which compares as SET against a Long bound and resolves the cover to `firstImageIndex - 1`:
//      a text record. Silently wrong bytes, not an error.
//   3. EXTH 201/202 are RELATIVE to `firstImageIndex`, not absolute record indices. The happy path
//      cannot discriminate the two (on the real book `135 + 0 == 135`), so the case here uses a
//      deliberately non-zero relative index.
package com.vreader.app.library.covers

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MobiCoverParserIndexTest {

    @get:Rule
    val temp = TemporaryFolder()

    private var fixtureCount = 0

    private fun parse(bytes: ByteArray, extendTo: Long? = null): MobiCoverParseResult =
        MobiCoverParser.parse(writeFixture(temp.root, "index-${fixtureCount++}.azw3", bytes, extendTo))

    /** The happy path, so every negative below proves DISCRIMINATION rather than blanket failure. */
    @Test
    fun `the 201 target resolves to the cover record`() {
        val cover = jpegLike(256)
        assertArrayEquals(cover, assertArtBytes(parse(buildCoverBook(coverBytes = cover)), "happy path"))
    }

    // ---- the sentinel ---------------------------------------------------------------------------

    @Test
    fun `⑧ a 0xFFFFFFFF cover offset falls through to the thumbnail, and both unset is None`() {
        // THE `Int`-vs-`Long` DISCRIMINATOR. Read as `Int`, 0xFFFFFFFF is -1, which compares as SET
        // against a Long bound and resolves to firstImageIndex - 1 = record 1 (text, not an image).
        val fellThrough = assertArtBytes(
            parse(
                coverBookWithRecord0(
                    buildRecord0(exthRecords = listOf(exthOffset(201, 0xFFFFFFFFL), exthOffset(202, 0))),
                ),
            ),
            "201 unset, 202 set",
        )
        assertEquals("fell through to the 202 thumbnail record, not to record 1", 64, fellThrough.size)
        assertEquals("and it is the image record, not the text record", 0xFF.toByte(), fellThrough[0])

        assertNoneResult(
            parse(
                coverBookWithRecord0(
                    buildRecord0(
                        exthRecords = listOf(
                            exthOffset(201, 0xFFFFFFFFL),
                            exthOffset(202, 0xFFFFFFFFL),
                        ),
                    ),
                ),
            ),
            "both 201 and 202 unset",
        )
    }

    @Test
    fun `a firstImageIndex of 0xFFFFFFFF is None even when a valid EXTH 201 is present`() {
        // M-8: the committed iOS fixture `divider-azw3.azw3` has exactly this shape —
        // rec0[108..111] = FF FF FF FF with exthFlag 0x50.
        //
        // NOTE, measured: with the `Long` reads in place this case is ALSO rejected by the
        // `target >= numRecords` range check, because `numRecords` is a u16 and 0xFFFFFFFF always
        // exceeds it. Removing the dedicated sentinel check therefore fails no test. The check is
        // kept as intent (and as the guard that would still hold if the read were narrowed back to
        // `Int`); this case pins the OUTCOME, not the mechanism.
        assertNoneResult(
            parse(
                coverBookWithRecord0(
                    buildRecord0(firstImageIndex = 0xFFFFFFFFL, exthRecords = listOf(exthOffset(201, 0))),
                ),
            ),
            "firstImageIndex sentinel",
        )
    }

    // ---- masking --------------------------------------------------------------------------------

    @Test
    fun `a high bit in a field's LOW byte does not read as a negative number`() {
        // Both fields carry the REAL 6.3 MB CJK book's shape: numRecords is 0x009B and
        // firstImageIndex is 0x0099 — each with 0x80 set in its LOW byte, which is precisely where
        // the real book's `00 99` fails an unmasked port (`b[77].toInt() == -103`).
        val cover = jpegLike(96)
        val filler = List(151) { ByteArray(1) { 0x2E } }          // records 2 … 152
        val records = listOf(buildRecord0(firstImageIndex = 153), ByteArray(32) { 0x41 }) +
            filler + listOf(cover, ByteArray(4))                  // cover at index 153
        assertEquals("the fixture must place the cover at record 153", 153, records.size - 2)
        assertEquals("and declare 155 records (0x009B)", 155, records.size)

        assertArrayEquals(
            "resolved record 153 through both masked reads",
            cover,
            assertArtBytes(parse(buildPdb(records)), "low-byte high bit"),
        )
    }

    @Test
    fun `a high bit in numRecords' HIGH byte does not read as a negative number`() {
        // numRecords = 0x8003 (32,771). Unmasked, `b[76] shl 8` is -32,768 and the count goes
        // negative, so the record table is never read. Complements the low-byte case above: a
        // partially-masked UInt16 reader passes one and fails the other.
        val cover = jpegLike(64)
        val filler = List(32_768) { ByteArray(1) { 0x2E } }
        val records = listOf(buildRecord0(), ByteArray(32) { 0x41 }, cover) + filler
        assertEquals("numRecords must have bit 15 set", 0x8003, records.size)

        assertArrayEquals(
            "resolved record 2 with numRecords = 0x8003",
            cover,
            assertArtBytes(parse(buildPdb(records)), "high-byte high bit"),
        )
    }

    @Test
    fun `a record offset with bit 31 set resolves rather than reading as negative`() {
        // The 32-bit analogue: a record offset of 0x80000000 is -2,147,483,648 read as a signed
        // `Int`, which the `start < 0` guard would reject as `None`. Only a masked `Long` read
        // reaches the bytes. The file is SPARSE, so a 2 GiB offset costs nothing on disk.
        val cover = jpegLike(64)
        val offset = 0x8000_0000L
        assertTrue("the offset must have bit 31 set", offset > Int.MAX_VALUE)
        val file = writeSparseHighOffsetBook(temp.root, "high-offset.azw3", offset, cover)

        assertArrayEquals(
            "read the cover from beyond the signed-Int boundary",
            cover,
            assertArtBytes(MobiCoverParser.parse(file), "record offset 0x80000000"),
        )
    }

    // ---- relative indexing ------------------------------------------------------------------------

    @Test
    fun `the EXTH cover offset is RELATIVE to firstImageIndex, not an absolute record index`() {
        val decoy = ByteArray(48) { 0x5A }
        val cover = jpegLike(72)
        val records = listOf(
            buildRecord0(firstImageIndex = 2, exthRecords = listOf(exthOffset(201, 1))),
            ByteArray(32) { 0x41 },
            decoy,      // record 2 — where an ABSOLUTE reading of firstImageIndex would land
            cover,      // record 3 = firstImageIndex(2) + rel(1)
        )
        assertArrayEquals(
            "target = firstImageIndex + rel = 3",
            cover,
            assertArtBytes(parse(buildPdb(records)), "relative EXTH index"),
        )
    }

    @Test
    fun `a 201 record is preferred over a 202 record`() {
        val cover = jpegLike(64)
        val thumb = ByteArray(24) { 0x33 }
        val records = listOf(
            buildRecord0(firstImageIndex = 2, exthRecords = listOf(exthOffset(202, 1), exthOffset(201, 0))),
            ByteArray(32) { 0x41 },
            cover,      // record 2 = 201's target
            thumb,      // record 3 = 202's target
        )
        assertArrayEquals(
            "201 wins even when 202 appears first in the block",
            cover,
            assertArtBytes(parse(buildPdb(records)), "201 over 202"),
        )
    }

    // ---- EXTH scan bounds -------------------------------------------------------------------------

    @Test
    fun `an absurd EXTH record count terminates the scan instead of running away`() {
        assertNoneResult(
            parse(
                coverBookWithRecord0(
                    buildRecord0(
                        exthRecords = listOf(exthOffset(100, 1)),
                        exthRecordCountOverride = 0xFFFFFFFFL,
                    ),
                ),
            ),
            "EXTH recordCount of 4 billion",
        )
    }

    @Test
    fun `an EXTH length overrunning record 0 is None`() {
        assertNoneResult(
            parse(coverBookWithRecord0(buildRecord0(exthLengthOverride = 0xFFFFFF00L))),
            "EXTH length past the end of record 0",
        )
    }

    @Test
    fun `an EXTH length smaller than its own 12-byte header is None`() {
        assertNoneResult(
            parse(coverBookWithRecord0(buildRecord0(exthLengthOverride = 8))),
            "EXTH length below its own header size",
        )
    }

    @Test
    fun `records past the DECLARED EXTH end are not honoured`() {
        // A block that understates its length while a real-looking 201 record sits immediately
        // after it. Bounding the walk by record 0's end — which the Swift reference does — would
        // read that record and point the cover wherever the malformed file says. Bounding by the
        // declared end stops at the block.
        assertNoneResult(
            parse(
                coverBookWithRecord0(
                    buildRecord0(
                        exthRecords = listOf(exthOffset(201, 0)),
                        exthLengthOverride = 12,      // declares an EMPTY block; the 201 follows it
                    ),
                ),
            ),
            "a 201 record past the declared EXTH end",
        )
    }

    @Test
    fun `an EXTH record with a length below 8 terminates the scan instead of looping forever`() {
        val record0 = buildRecord0(
            exthRecords = listOf(
                ExthRecord(type = 100, payload = ByteArray(4), lengthOverride = 0),
                exthOffset(201, 0),
            ),
        )
        assertNoneResult(parse(coverBookWithRecord0(record0)), "EXTH record length 0")
    }

    // ---- bounded reads ----------------------------------------------------------------------------

    @Test
    fun `a one gigabyte book parses without loading the file into the heap`() {
        // 1 GiB is twice this JVM's default test heap, so any implementation that reads the file
        // whole — `file.readBytes()`, a full mapping, a growing buffer — dies here instead of
        // returning the 64-byte cover. The file is sparse, so it costs nothing to create.
        val oneGiB = 1024L * 1024 * 1024
        assertTrue(
            "the fixture must exceed the JVM heap for this assertion to mean anything",
            oneGiB > Runtime.getRuntime().maxMemory(),
        )
        val cover = jpegLike(64)
        // A trailing record keeps the cover's span small; the LAST record is the one running to EOF.
        val bytes = buildCoverBook(coverBytes = cover, trailingRecords = listOf(ByteArray(8)))
        val result = try {
            parse(bytes, extendTo = oneGiB)
        } catch (e: OutOfMemoryError) {
            org.junit.Assert.fail("the parser loaded the file into the heap instead of reading bounded spans")
            return
        }
        assertArrayEquals("only the cover record was read", cover, assertArtBytes(result, "1 GiB book"))
    }
}
