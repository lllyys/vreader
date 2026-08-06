// Purpose: feature #152 WI-3 — the thirteen structural failure modes of `MobiCoverParser`, plus the
// three decoding traps a Kotlin port of `vreader/Services/AZW3/MOBICoverExtractor.swift` falls into.
//
// This is the riskiest code in the feature: it parses ATTACKER-CONTROLLED binary (a book file can
// come from anywhere) with no format library behind it. Three properties matter more than the happy
// path and each has its own case here:
//
//   1. NOTHING is allocated from a span the file cannot back. A record-table entry of 0x7FFFFFF0
//      computes a 2,147,138,052-byte length; allocating it throws OutOfMemoryError, which is an
//      `Error` and therefore escapes `catch (Exception)` — killing the whole app-scope backfill.
//   2. Every big-endian read is MASKED. Kotlin's `ByteArray[i]` is signed, so the real 6.3 MB CJK
//      book's `numRecords = 00 99` reads as -103 unmasked — an unmasked port fails on the FIRST
//      field it reads, on a real book.
//   3. 32-bit fields are `Long`, not `Int`. The MOBI "not set" sentinel 0xFFFFFFFF is -1 as an Int,
//      which compares as SET against a Long bound and silently resolves to `firstImageIndex - 1` —
//      a non-image record. Wrong bytes, not an error.
//
// Fixtures are synthetic by necessity; see the header of `MobiFixtures.kt` for which AGENTS.md
// "real books first" exception applies and why.
package com.vreader.app.library.covers

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class MobiCoverParserTest {

    @get:Rule
    val temp = TemporaryFolder()

    private var fixtureCount = 0

    private fun parse(bytes: ByteArray, extendTo: Long? = null): MobiCoverParseResult =
        MobiCoverParser.parse(writeFixture(temp.root, "fixture-${fixtureCount++}.azw3", bytes, extendTo))

    private fun assertNone(result: MobiCoverParseResult, what: String) {
        if (result !is MobiCoverParseResult.None) fail("$what: expected None but got $result")
    }

    private fun assertArt(result: MobiCoverParseResult, what: String): ByteArray {
        if (result !is MobiCoverParseResult.Art) fail("$what: expected Art but got $result")
        return (result as MobiCoverParseResult.Art).bytes
    }

    // ---- the happy path, so every negative below proves DISCRIMINATION, not blanket failure ----

    @Test
    fun `cover bearing book yields the exact bytes of the target image record`() {
        val cover = jpegLike(512)
        val bytes = assertArt(parse(buildCoverBook(coverBytes = cover)), "happy path")
        assertArrayEquals("the parser returns the record's bytes verbatim", cover, bytes)
    }

    // ---- ① … ⑬ the structural failure modes -------------------------------------------------

    @Test
    fun `① a file shorter than the 78-byte PDB header is None`() {
        assertNone(parse(ByteArray(77)), "77-byte file")
        assertNone(parse(ByteArray(0)), "empty file")
    }

    @Test
    fun `② numRecords of zero is None`() {
        assertNone(parse(buildPdb(listOf(buildRecord0()), numRecordsOverride = 0)), "numRecords == 0")
    }

    @Test
    fun `③ a record table running past EOF is None`() {
        // The header claims 4000 records (a 32,000-byte table) in a file of a few hundred bytes.
        assertNone(
            parse(buildPdb(listOf(buildRecord0(), jpegLike(16)), numRecordsOverride = 4000)),
            "record table beyond EOF",
        )
    }

    @Test
    fun `④ a record 0 shorter than 132 bytes is None`() {
        assertNone(
            parse(buildPdb(listOf(ByteArray(131), jpegLike(16)))),
            "record 0 of 131 bytes",
        )
    }

    @Test
    fun `⑤ a record 0 without the MOBI magic is None`() {
        assertNone(
            parse(buildPdb(listOf(buildRecord0(mobiMagic = "TPZ0"), jpegLike(16)))),
            "wrong MOBI magic",
        )
    }

    @Test
    fun `⑥ a clear EXTH flag bit is None`() {
        assertNone(
            parse(buildCoverBookWithRecord0(buildRecord0(exthFlags = 0x00))),
            "EXTH flag bit 0x40 clear",
        )
        // 0x50 (the shape `divider-azw3.azw3` carries) HAS the bit — it must NOT be rejected here.
        val withBit = parse(buildCoverBookWithRecord0(buildRecord0(exthFlags = 0x50)))
        assertTrue("0x50 sets bit 0x40, so the scan must proceed", withBit is MobiCoverParseResult.Art)
    }

    @Test
    fun `⑦ an EXTH block carrying neither 201 nor 202 is None`() {
        assertNone(
            parse(buildCoverBookWithRecord0(buildRecord0(exthRecords = listOf(exthOffset(100, 7))))),
            "no 201 and no 202",
        )
        assertNone(
            parse(buildCoverBookWithRecord0(buildRecord0(exthRecords = emptyList()))),
            "an empty EXTH block",
        )
    }

    @Test
    fun `⑧ a 0xFFFFFFFF cover offset falls through to the thumbnail, and both unset is None`() {
        // THE `Int`-vs-`Long` DISCRIMINATOR. Read as Int, 0xFFFFFFFF is -1, which compares as SET
        // against a Long bound and resolves to firstImageIndex - 1 = record 1 (text, not an image).
        val fellThrough = assertArt(
            parse(
                buildCoverBookWithRecord0(
                    buildRecord0(exthRecords = listOf(exthOffset(201, 0xFFFFFFFFL), exthOffset(202, 0))),
                ),
            ),
            "201 unset, 202 set",
        )
        assertEquals("fell through to the 202 thumbnail record, not to record 1", 64, fellThrough.size)
        assertEquals("and it is the image record, not the text record", 0xFF.toByte(), fellThrough[0])

        assertNone(
            parse(
                buildCoverBookWithRecord0(
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
    fun `⑨ a target record index at or past numRecords is None`() {
        assertNone(
            parse(buildCoverBookWithRecord0(buildRecord0(exthRecords = listOf(exthOffset(201, 5))))),
            "firstImageIndex + rel == 7 in a 3-record file",
        )
    }

    @Test
    fun `⑪ a record whose END runs past EOF is None and allocates nothing`() {
        // The C-1 Critical, constructed exactly as it was measured: entry for the record AFTER the
        // cover is set to 0x7FFFFFF0, so the cover's computed span is ~2 GiB.
        val bytes = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64), ByteArray(8)),
            offsetOverrides = mapOf(3 to 0x7FFFFFF0L),
        )
        val impliedSpan = 0x7FFFFFF0L - (78L + 4 * 8 + buildRecord0().size + 32)
        assertTrue(
            "the fixture must imply a span larger than this JVM's entire heap (${Runtime.getRuntime().maxMemory()} B), " +
                "so allocating it could only OutOfMemoryError — implied span was $impliedSpan B",
            impliedSpan > Runtime.getRuntime().maxMemory(),
        )

        val result = try {
            parse(bytes)
        } catch (e: OutOfMemoryError) {
            fail(
                "OutOfMemoryError escaped the parser. It is an Error, not an Exception, so no " +
                    "`catch (e: Exception)` upstream can contain it: it would kill the app-scope " +
                    "cover backfill for the entire library. Guard the span BEFORE allocating.",
            )
            return
        }
        assertNone(result, "record end beyond EOF")
    }

    @Test
    fun `a span past EOF but under the cap is rejected WITHOUT allocating it`() {
        // Isolates the `end > fileLength` guard from the MAX_RECORD_BYTES cap. Both reject the ~2 GiB
        // C-1 span, so ⑪ alone cannot tell whether either guard is doing the work — removing
        // `end > fileLength` leaves ⑪ green. Here the implied span is ~60 MiB: UNDER the cap, so
        // only the file-length guard rejects it, and past EOF, so the return value is `None` either
        // way. The observable difference is therefore the ALLOCATION, and that is what is asserted.
        val recordStart = 78L + 4 * 8 + buildRecord0().size + 32
        val impliedEnd = recordStart + 60L * 1024 * 1024
        val bytes = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64), ByteArray(8)),
            offsetOverrides = mapOf(3 to impliedEnd),
        )
        assertTrue("the span must sit under the cap for this test to isolate the guard",
            impliedEnd - recordStart < MobiCoverParser.MAX_RECORD_BYTES)

        val file = writeFixture(temp.root, "under-cap-past-eof.azw3", bytes)
        MobiCoverParser.parse(file)                                   // warm the code path
        val before = threadAllocatedBytes()
        val result = MobiCoverParser.parse(file)
        val allocated = threadAllocatedBytes() - before

        assertNone(result, "span past EOF but under the cap")
        assertTrue(
            "parsing allocated $allocated bytes; a span the file cannot back must be rejected " +
                "before the ByteArray is sized, not after it is filled",
            allocated < 1L * 1024 * 1024,
        )
    }

    @Test
    fun `⑫ a record whose START runs past EOF is None`() {
        val bytes = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64)),
            offsetOverrides = mapOf(2 to 0x0FFFFFFFL),
        )
        assertNone(parse(bytes), "record start beyond EOF")
    }

    @Test
    fun `⑬ a span exceeding MAX_RECORD_BYTES is None even though the file backs it`() {
        // A sparse file large enough that the span is genuinely readable — only the 64 MiB cap
        // rejects it. Guards against "the file length check is sufficient" (it is not: a 300 MB
        // book with a corrupt table would otherwise buffer 300 MB).
        val fileLength = MobiCoverParser.MAX_RECORD_BYTES + 16L * 1024 * 1024
        val bytes = buildCoverBook(coverBytes = jpegLike(64))
        assertNone(parse(bytes, extendTo = fileLength), "span over the 64 MiB cap")
    }

    @Test
    fun `non-monotonic record offsets are None`() {
        val bytes = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64), ByteArray(8)),
            offsetOverrides = mapOf(3 to 4L),   // record 3 starts before record 2 → end <= start
        )
        assertNone(parse(bytes), "end <= start")
    }

    // ---- the three decoding traps -----------------------------------------------------------

    @Test
    fun `every big-endian field is masked, so a high bit does not read as a negative number`() {
        // Both fields carry the REAL 6.3 MB CJK book's shape: numRecords is 0x009B and
        // firstImageIndex is 0x0099 — each has 0x80 set in its LOW byte, which is precisely where
        // the real book's `00 99` fails an unmasked port (b[77].toInt() == -103).
        val cover = jpegLike(96)
        val filler = List(151) { ByteArray(1) { 0x2E } }          // records 2 … 152
        val records = listOf(buildRecord0(firstImageIndex = 153), ByteArray(32) { 0x41 }) +
            filler + listOf(cover, ByteArray(4))                  // cover at index 153
        assertEquals("the fixture must place the cover at record 153", 153, records.size - 2)
        assertEquals("and declare 155 records (0x009B)", 155, records.size)

        val bytes = assertArt(parse(buildPdb(records)), "high-bit numRecords + firstImageIndex")
        assertArrayEquals("resolved record 153 through both masked reads", cover, bytes)
    }

    @Test
    fun `the EXTH cover offset is RELATIVE to firstImageIndex, not an absolute record index`() {
        // Discriminator for "treat 201 as absolute": the happy path cannot tell the two apart
        // (135 + 0 == 135), so the relative index here is deliberately non-zero.
        val decoy = ByteArray(48) { 0x5A }
        val cover = jpegLike(72)
        val records = listOf(
            buildRecord0(firstImageIndex = 2, exthRecords = listOf(exthOffset(201, 1))),
            ByteArray(32) { 0x41 },
            decoy,      // record 2 — what an ABSOLUTE reading of `rel = 1`... would not pick either
            cover,      // record 3 = firstImageIndex(2) + rel(1)
        )
        val bytes = assertArt(parse(buildPdb(records)), "relative EXTH index")
        assertArrayEquals("target = firstImageIndex + rel = 3", cover, bytes)
    }

    @Test
    fun `a firstImageIndex of 0xFFFFFFFF is None even when a valid EXTH 201 is present`() {
        // M-8: the committed iOS fixture `divider-azw3.azw3` has exactly this shape —
        // rec0[108..111] = FF FF FF FF with exthFlag 0x50. The sentinel must be checked BEFORE the
        // EXTH scan, so a valid 201 cannot resurrect it.
        assertNone(
            parse(
                buildCoverBookWithRecord0(
                    buildRecord0(firstImageIndex = 0xFFFFFFFFL, exthRecords = listOf(exthOffset(201, 0))),
                ),
            ),
            "firstImageIndex sentinel",
        )
    }

    // ---- EXTH scan bounds --------------------------------------------------------------------

    @Test
    fun `an absurd EXTH record count terminates the scan instead of running away`() {
        assertNone(
            parse(
                buildCoverBookWithRecord0(
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
        assertNone(
            parse(
                buildCoverBookWithRecord0(
                    buildRecord0(exthLengthOverride = 0xFFFFFF00L),
                ),
            ),
            "EXTH length past the end of record 0",
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
        assertNone(parse(buildCoverBookWithRecord0(record0)), "EXTH record length 0")
    }

    @Test
    fun `a 201 record is preferred over a 202 record`() {
        val cover = jpegLike(64)
        val thumb = ByteArray(24) { 0x33 }
        val records = listOf(
            buildRecord0(
                firstImageIndex = 2,
                exthRecords = listOf(exthOffset(202, 1), exthOffset(201, 0)),
            ),
            ByteArray(32) { 0x41 },
            cover,      // record 2 = 201's target
            thumb,      // record 3 = 202's target
        )
        val bytes = assertArt(parse(buildPdb(records)), "201 over 202")
        assertArrayEquals("201 wins even when 202 appears first in the block", cover, bytes)
    }

    // ---- bounded reads ------------------------------------------------------------------------

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
        // A trailing record keeps the cover's span small; the LAST record is the one that runs to EOF.
        val bytes = buildCoverBook(coverBytes = cover, trailingRecords = listOf(ByteArray(8)))
        val result = try {
            parse(bytes, extendTo = oneGiB)
        } catch (e: OutOfMemoryError) {
            fail("the parser loaded the file into the heap instead of reading bounded spans")
            return
        }
        assertArrayEquals("only the cover record was read", cover, assertArt(result, "1 GiB book"))
    }

    // ---- helpers ------------------------------------------------------------------------------

    /** A 3-record cover book whose record 0 is [record0], so a single field can be varied. */
    private fun buildCoverBookWithRecord0(record0: ByteArray): ByteArray =
        buildPdb(listOf(record0, ByteArray(32) { 0x41 }, jpegLike(64)))

    /**
     * Cumulative bytes allocated by this thread, GARBAGE INCLUDED — which is what makes it the right
     * probe here: the oversized array a missing guard would create is discarded immediately, so any
     * heap-occupancy measurement would miss it.
     *
     * Reached reflectively because `java.lang.management` is not on the Android unit-test compile
     * classpath (android.jar shadows it), though it is present at runtime on the desktop JVM these
     * tests actually execute on. A missing class throws and FAILS the test — never a silent skip.
     */
    private fun threadAllocatedBytes(): Long {
        val bean = Class.forName("java.lang.management.ManagementFactory")
            .getMethod("getThreadMXBean")
            .invoke(null)
        val method = Class.forName("com.sun.management.ThreadMXBean")
            .getMethod("getThreadAllocatedBytes", Long::class.javaPrimitiveType)
        return method.invoke(bean, Thread.currentThread().id) as Long
    }
}
