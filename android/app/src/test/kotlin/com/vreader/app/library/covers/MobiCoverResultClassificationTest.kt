// Purpose: feature #152 WI-3 — the `None`-vs-`Failed` split, asserted AS A CONTRACT rather than
// incidentally through whichever structural case happens to exercise it (Gate-2 finding H-2).
//
// The line is drawn on CONTENT vs ACCESS, not on exception type:
//
//   None   = the file was reachable and structurally parsed, and yields no cover — including
//            because it is truncated, malformed, out of range, or hit EOF during a bounded read.
//            A re-read cannot change the answer, so the coordinator MEMOISES it.
//   Failed = the file could not be accessed at all (missing, permission-denied, device I/O error
//            on open). A later attempt plausibly succeeds, so the coordinator RETRIES.
//
// Why this needs its own suite: moving from iOS's memory-mapped `Data` to `RandomAccessFile` turns
// what were bounds COMPARISONS into `EOFException`s, which are `IOException`s. Classify those as
// `Failed` and every truncated book in the library is re-opened and re-parsed on EVERY app start,
// forever — the exact cost the memoisation exists to prevent. 6 of 39 mutated files diverged this
// way when the spec was measured. The boundary is pinned at the OPEN: the open maps to `Failed`,
// every subsequent bounded read maps `EOFException` to `None`.
package com.vreader.app.library.covers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class MobiCoverResultClassificationTest {

    @get:Rule
    val temp = TemporaryFolder()

    private var fixtureCount = 0

    private fun parse(bytes: ByteArray, extendTo: Long? = null): MobiCoverParseResult =
        MobiCoverParser.parse(writeFixture(temp.root, "class-${fixtureCount++}.azw3", bytes, extendTo))

    // ---- CONTENT → None (memoise) --------------------------------------------------------------

    @Test
    fun `a truncated file is None, not Failed`() {
        // ① — the record table read runs off the end of the file.
        assertEquals(MobiCoverParseResult.None, parse(ByteArray(40)))
    }

    @Test
    fun `a file truncated mid-record-table is None, not Failed`() {
        // ③ — the classic EOF-during-a-bounded-read case. Under a naive
        // `catch (e: IOException) -> Failed` this returns Failed and is re-parsed forever.
        val full = buildCoverBook()
        assertEquals(MobiCoverParseResult.None, parse(full.copyOf(90)))
    }

    @Test
    fun `a file truncated mid-cover-record is None, not Failed`() {
        // The cover must NOT be the last record here: a record's span ends at the next record's
        // offset, so truncating the file only shortens the LAST record rather than invalidating it.
        // With a trailing record present, truncation puts the cover's end past EOF — the case that
        // returns `Failed` under a naive `catch (IOException) -> Failed`.
        val full = buildCoverBook(coverBytes = jpegLike(4096), trailingRecords = listOf(ByteArray(8)))
        assertEquals(MobiCoverParseResult.None, parse(full.copyOf(full.size - 2048)))
    }

    @Test
    fun `truncating the final record yields its surviving bytes, exactly as iOS does`() {
        // Documented, not accidental: iOS defines the last record's end as `data.count`, so a book
        // truncated inside its final record produces a SHORT image record rather than a parse
        // failure. Those bytes then fail to decode, and the adapter classifies that `None` — so the
        // outcome the coordinator sees is still "memoise", reached one step later.
        val full = buildCoverBook(coverBytes = jpegLike(4096))
        val result = parse(full.copyOf(full.size - 2048))
        assertTrue("expected the surviving prefix, got $result", result is MobiCoverParseResult.Art)
        assertEquals("only the bytes the file still backs", 2048, (result as MobiCoverParseResult.Art).bytes.size)
    }

    @Test
    fun `an out-of-range target index is None, not Failed`() {
        // ⑨
        assertEquals(
            MobiCoverParseResult.None,
            parse(buildPdb(listOf(buildRecord0(exthRecords = listOf(exthOffset(201, 9))), jpegLike(32)))),
        )
    }

    @Test
    fun `all three unbacked-span rejections are None, not Failed`() {
        // ⑪ end past EOF, ⑫ start past EOF, ⑬ over the 64 MiB cap — a rejected span is a
        // structurally-parsed file that yields no image, never an access failure.
        val endPastEof = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64), ByteArray(8)),
            offsetOverrides = mapOf(3 to 0x7FFFFFF0L),
        )
        assertEquals("record end past EOF", MobiCoverParseResult.None, parse(endPastEof))

        val startPastEof = buildPdb(
            listOf(buildRecord0(), ByteArray(32) { 0x41 }, jpegLike(64)),
            offsetOverrides = mapOf(2 to 0x0FFFFFFFL),
        )
        assertEquals("record start past EOF", MobiCoverParseResult.None, parse(startPastEof))

        val overCap = buildCoverBook()
        assertEquals(
            "span over the 64 MiB cap",
            MobiCoverParseResult.None,
            parse(overCap, extendTo = MobiCoverParser.MAX_RECORD_BYTES + 16L * 1024 * 1024),
        )
    }

    @Test
    fun `an empty file is None, not Failed`() {
        assertEquals(MobiCoverParseResult.None, parse(ByteArray(0)))
    }

    @Test
    fun `a directory in place of a book is not classified as content`() {
        // A directory opens but cannot be read as a file. It is an ACCESS problem, not a book that
        // structurally lacks a cover — so it must not be memoised as None.
        val dir = temp.newFolder("a-directory.azw3")
        assertEquals(MobiCoverParseResult.Failed, MobiCoverParser.parse(dir))
    }

    @Test
    fun `a file that shrinks mid-parse is None, not Failed`() {
        // The ONLY route to `EOFException` inside the parser. On a stable file every span is
        // validated against `length()` before it is read, so EOF is unreachable by construction —
        // which is why this case needs a handle that over-reports its length to reach it. That is
        // not a contrivance: a book on removable storage, or a cloud-backed SAF document being
        // re-downloaded, really can shrink between the bound check and the read.
        //
        // Without this case the `EOFException -> None` mapping is dead code, and flipping it to
        // `Failed` — the exact H-2 regression — passes every other test in this file.
        val file = writeFixture(temp.root, "shrinking.azw3", buildCoverBook())
        val lyingHandle = object : java.io.RandomAccessFile(file, "r") {
            override fun length(): Long = super.length() + 4096
        }
        lyingHandle.use {
            assertEquals(MobiCoverParseResult.None, MobiCoverParser.classify(it))
        }
    }

    // ---- ACCESS → Failed (retry) ---------------------------------------------------------------

    @Test
    fun `a file that does not exist is Failed, not None`() {
        val missing = File(temp.root, "never-written.azw3")
        assertTrue("precondition", !missing.exists())
        assertEquals(MobiCoverParseResult.Failed, MobiCoverParser.parse(missing))
    }

    @Test
    fun `an unreadable file is Failed, not None`() {
        val locked = writeFixture(temp.root, "locked.azw3", buildCoverBook())
        // Asserted, never assumed: a skip exits 0 exactly like a pass (bug #369), so an environment
        // that cannot revoke read permission (running as root) must say so loudly, not quietly
        // report this branch as covered.
        assertTrue(
            "could not make the fixture unreadable — this test cannot validate the permission " +
                "branch when the test JVM ignores the read bit (are you running as root?)",
            locked.setReadable(false, false) && !locked.canRead(),
        )
        try {
            assertEquals(MobiCoverParseResult.Failed, MobiCoverParser.parse(locked))
        } finally {
            locked.setReadable(true, false)
        }
    }

    @Test
    fun `the classification never throws for any of these inputs`() {
        // The "no extractor throws" contract, restated at the parser boundary.
        val inputs = listOf(
            ByteArray(0),
            ByteArray(77),
            buildCoverBook(),
            buildCoverBook().copyOf(90),
            buildPdb(listOf(buildRecord0()), numRecordsOverride = 0),
            buildPdb(
                listOf(buildRecord0(), ByteArray(32), jpegLike(64), ByteArray(8)),
                offsetOverrides = mapOf(3 to 0x7FFFFFF0L),
            ),
        )
        inputs.forEachIndexed { i, bytes ->
            val result = parse(bytes)
            assertTrue(
                "input $i produced $result, which is not one of the three declared outcomes",
                result is MobiCoverParseResult.Art ||
                    result is MobiCoverParseResult.None ||
                    result is MobiCoverParseResult.Failed,
            )
        }
    }
}
