// Purpose: feature #152 WI-3 — `MobiCoverParser`'s STRUCTURAL failure modes: the shapes a file can
// take that make it unparseable, and the bounds that must hold before a single byte is allocated.
// The index/EXTH semantics (which record is the cover, and how the fields decode) live in
// `MobiCoverParserIndexTest`; the `None`-vs-`Failed` split lives in
// `MobiCoverResultClassificationTest`.
//
// This is the riskiest code in the feature: it parses ATTACKER-CONTROLLED binary (a book file can
// come from anywhere) with no format library behind it. The property that matters most here is that
// NOTHING is allocated from a span the file cannot back. A record-table entry of 0x7FFFFFF0
// computes a 2,147,138,052-byte length; allocating it throws `OutOfMemoryError`, which is an `Error`
// and therefore escapes `catch (Exception)` — killing the app-scope cover backfill for the whole
// library rather than failing one book.
//
// Fixtures are synthetic by necessity; see the header of `MobiFixtures.kt` for which AGENTS.md
// "real books first" exception applies and why.
package com.vreader.app.library.covers

import org.junit.Assert.assertArrayEquals
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

    /** The happy path, so every negative below proves DISCRIMINATION rather than blanket failure. */
    @Test
    fun `a cover bearing book yields the exact bytes of the target image record`() {
        val cover = jpegLike(512)
        val bytes = assertArtBytes(parse(buildCoverBook(coverBytes = cover)), "happy path")
        assertArrayEquals("the parser returns the record's bytes verbatim", cover, bytes)
    }

    // ---- ① … ⑨ malformed containers -----------------------------------------------------------

    @Test
    fun `① a file shorter than the 78-byte PDB header is None`() {
        assertNoneResult(parse(ByteArray(77)), "77-byte file")
        assertNoneResult(parse(ByteArray(0)), "empty file")
    }

    @Test
    fun `② numRecords of zero is None`() {
        assertNoneResult(parse(buildPdb(listOf(buildRecord0()), numRecordsOverride = 0)), "numRecords == 0")
    }

    @Test
    fun `③ a record table running past EOF is None`() {
        // The header claims 4000 records (a 32,000-byte table) in a file of a few hundred bytes.
        assertNoneResult(
            parse(buildPdb(listOf(buildRecord0(), jpegLike(16)), numRecordsOverride = 4000)),
            "record table beyond EOF",
        )
    }

    @Test
    fun `④ a record 0 shorter than 132 bytes is None`() {
        assertNoneResult(parse(buildPdb(listOf(ByteArray(131), jpegLike(16)))), "record 0 of 131 bytes")
    }

    @Test
    fun `⑤ a record 0 without the MOBI magic is None`() {
        assertNoneResult(
            parse(buildPdb(listOf(buildRecord0(mobiMagic = "TPZ0"), jpegLike(16)))),
            "wrong MOBI magic",
        )
    }

    @Test
    fun `⑥ a clear EXTH flag bit is None`() {
        assertNoneResult(parse(coverBookWithRecord0(buildRecord0(exthFlags = 0x00))), "EXTH bit clear")
        // 0x50 (the shape `divider-azw3.azw3` carries) HAS bit 0x40 — it must NOT be rejected here.
        val withBit = parse(coverBookWithRecord0(buildRecord0(exthFlags = 0x50)))
        assertTrue("0x50 sets bit 0x40, so the scan must proceed", withBit is MobiCoverParseResult.Art)
    }

    @Test
    fun `⑦ an EXTH block carrying neither 201 nor 202 is None`() {
        assertNoneResult(
            parse(coverBookWithRecord0(buildRecord0(exthRecords = listOf(exthOffset(100, 7))))),
            "no 201 and no 202",
        )
        assertNoneResult(
            parse(coverBookWithRecord0(buildRecord0(exthRecords = emptyList()))),
            "an empty EXTH block",
        )
    }

    @Test
    fun `⑨ a target record index at or past numRecords is None`() {
        assertNoneResult(
            parse(coverBookWithRecord0(buildRecord0(exthRecords = listOf(exthOffset(201, 5))))),
            "firstImageIndex + rel == 7 in a 3-record file",
        )
    }

    // ---- ⑪ … ⑬ spans the file cannot back ------------------------------------------------------

    @Test
    fun `⑪ a record whose END runs past EOF is None and allocates nothing`() {
        // The C-1 Critical, constructed exactly as it was measured: the entry for the record AFTER
        // the cover is set to 0x7FFFFFF0, so the cover's computed span is ~2 GiB.
        val bytes = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64), ByteArray(8)),
            offsetOverrides = mapOf(3 to 0x7FFFFFF0L),
        )
        val impliedSpan = 0x7FFFFFF0L - (78L + 4 * 8 + buildRecord0().size + 32)
        assertTrue(
            "the fixture must imply a span larger than this JVM's entire heap " +
                "(${Runtime.getRuntime().maxMemory()} B), so allocating it could only " +
                "OutOfMemoryError — implied span was $impliedSpan B",
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
        assertNoneResult(result, "record end beyond EOF")
    }

    @Test
    fun `a span past EOF but under the cap is rejected WITHOUT allocating it`() {
        // Isolates the `end > fileLength` guard from the MAX_RECORD_BYTES cap. Both reject the ~2 GiB
        // C-1 span, so ⑪ alone cannot tell which guard is doing the work — removing
        // `end > fileLength` leaves ⑪ green. Here the implied span is ~60 MiB: UNDER the cap, so
        // only the file-length guard rejects it, and past EOF, so the return value is `None` either
        // way. The observable difference is therefore the ALLOCATION, and that is what is asserted.
        val recordStart = 78L + 4 * 8 + buildRecord0().size + 32
        val impliedEnd = recordStart + 60L * 1024 * 1024
        val bytes = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64), ByteArray(8)),
            offsetOverrides = mapOf(3 to impliedEnd),
        )
        assertTrue(
            "the span must sit under the cap for this test to isolate the guard",
            impliedEnd - recordStart < MobiCoverParser.MAX_RECORD_BYTES,
        )

        val file = writeFixture(temp.root, "under-cap-past-eof.azw3", bytes)
        MobiCoverParser.parse(file)                                   // warm the code path
        val before = threadAllocatedBytes()
        val result = MobiCoverParser.parse(file)
        val allocated = threadAllocatedBytes() - before

        assertNoneResult(result, "span past EOF but under the cap")
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
        assertNoneResult(parse(bytes), "record start beyond EOF")
    }

    @Test
    fun `⑬ a span exceeding MAX_RECORD_BYTES is None even though the file backs it`() {
        // A sparse file large enough that the span is genuinely readable — only the 64 MiB cap
        // rejects it. Guards against "the file-length check is sufficient": it is not, since a
        // 300 MB book with a corrupt table would otherwise buffer 300 MB.
        val fileLength = MobiCoverParser.MAX_RECORD_BYTES + 16L * 1024 * 1024
        assertNoneResult(parse(buildCoverBook(), extendTo = fileLength), "span over the 64 MiB cap")
    }

    @Test
    fun `non-monotonic record offsets are None`() {
        val bytes = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64), ByteArray(8)),
            offsetOverrides = mapOf(3 to 4L),   // record 3 starts before record 2 → end <= start
        )
        assertNoneResult(parse(bytes), "end <= start")
    }

    /**
     * Cumulative bytes allocated by this thread, GARBAGE INCLUDED — which is what makes it the right
     * probe: the oversized array a missing guard would create is discarded immediately, so any
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
