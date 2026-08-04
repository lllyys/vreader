package com.vreader.app.reader.nav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #139 WI-5 — [txtTocIndexFor]: the offset analog of the EPUB chrome's
 * `ReaderChromeModel.tocIndexFor`, mapping a TXT/MD reader's live source offset to the Contents
 * row to highlight.
 *
 * The properties this suite exists to protect:
 *
 * - **The `-1`-vs-`0` contract is EXACTLY `tocIndexFor`'s.** `-1` means "there is no row to
 *   highlight", and that is true only when the TOC is empty. Once a TOC exists the answer is never
 *   `-1`: an offset before every entry highlights the first row, because a missing highlight is
 *   worse than a best-effort one. [emptyEntries_returnsMinusOne] and
 *   [offsetBeforeFirstEntry_returnsZero] pin the two halves against each other — an implementation
 *   that collapses them (returns `-1` when nothing is at-or-before) fails the second.
 * - **Every boundary is pinned, not just the interior.** An offset exactly AT an entry start
 *   belongs to THAT entry (not the previous one); an offset past the last entry stays on the last
 *   entry; a one-entry TOC always answers 0. These are the off-by-one seams a `<` / `<=` slip or a
 *   `found` / `lo` mix-up moves, and each has its own test.
 * - **The search is genuinely O(log n).** [isBinarySearch_not_linear_over50000Entries] does not
 *   time anything (timings are flaky and pass for a fast linear scan on a fast machine) — it
 *   COUNTS element reads through a [CountingIntList] at the real
 *   [TxtMdTocProvider.MAX_TOC_ENTRIES]-sized cap. A linear scan reads tens of thousands of
 *   elements and fails the bound; a binary search reads ~16.
 *
 * Precondition (NOT re-asserted here): [entryOffsets] are in document order, non-decreasing. That
 * invariant is produced and pinned upstream — `TxtTocRuleEngineTest` and `TxtMdTocProviderTest`
 * both assert the emitted offsets equal their own `sorted()`. This suite tests the consumer.
 *
 * Pure JVM — no Android runtime, no Robolectric, no emulator.
 */
class TxtTocIndexTest {

    private companion object {
        /** Three chapters at plausible source offsets; the workhorse fixture. */
        val THREE = listOf(100, 200, 300)
    }

    // ── The -1-vs-0 contract ────────────────────────────────────────────────────────────────

    @Test
    fun emptyEntries_returnsMinusOne() {
        // The ONLY input that may answer -1: no TOC, so there is no row to highlight.
        assertEquals(-1, txtTocIndexFor(0, emptyList()))
        assertEquals(-1, txtTocIndexFor(12_345, emptyList()))
        assertEquals(-1, txtTocIndexFor(Int.MAX_VALUE, emptyList()))
    }

    @Test
    fun offsetBeforeFirstEntry_returnsZero() {
        // A TOC exists but nothing is at-or-before → the FIRST row, never -1 (tocIndexFor's rule).
        assertEquals(0, txtTocIndexFor(0, THREE))
        assertEquals(0, txtTocIndexFor(99, THREE))
        // Stated as its own assertion so the -1/0 confusion can never pass silently.
        assertNotEquals(-1, txtTocIndexFor(0, THREE))
    }

    @Test
    fun negativeOffset_stillReturnsZero_neverMinusOne() {
        // Defensive: a not-yet-known reading position must not be mistaken for "no TOC".
        assertEquals(0, txtTocIndexFor(-1, THREE))
        assertEquals(0, txtTocIndexFor(Int.MIN_VALUE, THREE))
    }

    // ── Boundaries ──────────────────────────────────────────────────────────────────────────

    @Test
    fun offsetExactlyAtEntryStart_returnsThatEntry() {
        // At-or-before is inclusive: the heading line's own first code unit is INSIDE that chapter.
        assertEquals(0, txtTocIndexFor(100, THREE))
        assertEquals(1, txtTocIndexFor(200, THREE))
        assertEquals(2, txtTocIndexFor(300, THREE))
    }

    @Test
    fun offsetInsideChapter_returnsLastEntryAtOrBefore() {
        assertEquals(0, txtTocIndexFor(101, THREE))
        assertEquals(0, txtTocIndexFor(199, THREE))
        assertEquals(1, txtTocIndexFor(250, THREE))
        assertEquals(1, txtTocIndexFor(299, THREE))
    }

    @Test
    fun offsetPastLastEntry_returnsLastEntry() {
        assertEquals(2, txtTocIndexFor(301, THREE))
        assertEquals(2, txtTocIndexFor(9_999_999, THREE))
        assertEquals(2, txtTocIndexFor(Int.MAX_VALUE, THREE))
    }

    @Test
    fun singleEntry_alwaysReturnsZero() {
        val one = listOf(500)
        assertEquals(0, txtTocIndexFor(0, one))       // before it
        assertEquals(0, txtTocIndexFor(499, one))     // just before it
        assertEquals(0, txtTocIndexFor(500, one))     // exactly at it
        assertEquals(0, txtTocIndexFor(501, one))     // just after it
        assertEquals(0, txtTocIndexFor(Int.MAX_VALUE, one))
    }

    @Test
    fun firstEntryAtOffsetZero_isSelectedAtOffsetZero() {
        // A document whose very first line is a heading: offset 0 is a real at-entry hit, not the
        // nothing-at-or-before fallback. Both paths answer 0, so this pins the fixture where they
        // differ — entry 0 at offset 0 must still be beaten by a later entry once passed.
        val fromZero = listOf(0, 50, 120)
        assertEquals(0, txtTocIndexFor(0, fromZero))
        assertEquals(0, txtTocIndexFor(49, fromZero))
        assertEquals(1, txtTocIndexFor(50, fromZero))
        assertEquals(2, txtTocIndexFor(120, fromZero))
    }

    @Test
    fun duplicateOffsets_returnTheLastEntryAtThatOffset() {
        // Two headings can share a line start (e.g. an MD setext title re-detected at the same
        // line). tocIndexFor keeps the LAST such row (its exact-href loop overwrites), so does this.
        val dupes = listOf(0, 100, 100, 100, 300)
        assertEquals(3, txtTocIndexFor(100, dupes))
        assertEquals(3, txtTocIndexFor(299, dupes))
        assertEquals(4, txtTocIndexFor(300, dupes))
        assertEquals(0, txtTocIndexFor(0, dupes))
    }

    @Test
    fun everyOffsetInARange_agreesWithTheLinearReference() {
        // Exhaustive cross-check of the whole domain around a small TOC against the plain-English
        // rule ("last entry at-or-before, else 0"), so no single hand-picked probe can hide a gap.
        val entries = listOf(3, 7, 8, 15, 16, 23, 42)
        for (offset in -5..50) {
            val expected = entries.indexOfLast { it <= offset }.let { if (it >= 0) it else 0 }
            assertEquals("offset=$offset", expected, txtTocIndexFor(offset, entries))
        }
    }

    // ── Complexity ──────────────────────────────────────────────────────────────────────────

    @Test
    fun isBinarySearch_not_linear_over50000Entries() {
        // The real cap (TxtMdTocProvider.MAX_TOC_ENTRIES) + 1, i.e. the largest list that can ever
        // reach this function. Entries every 10 code units so offsets and indices differ.
        val size = TxtMdTocProvider.MAX_TOC_ENTRIES + 1
        val backing = IntArray(size) { it * 10 }
        val list = CountingIntList(backing)

        // ceil(log2(50002)) == 16, so a correct binary search reads ~16 elements. 32 leaves 2x
        // headroom for an extra probe/early-out while staying ~1500x below a linear scan's 50001.
        val maxReads = 32

        // Worst-case-ish queries spread across the list, INCLUDING both ends and a miss-before-first.
        val queries = listOf(-1, 0, 5, 250_000, 250_005, size * 10, Int.MAX_VALUE)
        for (query in queries) {
            list.resetReads()
            val index = txtTocIndexFor(query, list)

            // The probe must also prove the answer is RIGHT — a function that returns a constant
            // without reading anything would otherwise "pass" the read-count bound for free.
            val expected = when {
                query < 0 -> 0
                query / 10 >= size -> size - 1
                else -> query / 10
            }
            assertEquals("index for offset=$query", expected, index)
            assertTrue(
                "offset=$query read ${list.reads} of $size elements; a binary search reads <= $maxReads " +
                    "(a linear scan would read ~$size)",
                list.reads <= maxReads,
            )
            assertTrue("offset=$query read nothing — the answer cannot have been searched for", list.reads > 0)
        }
    }

    /**
     * A `List<Int>` that counts element reads. Every traversal shape lands on [get] — indexing
     * directly, `forEachIndexed`, and iteration (`kotlin.collections.AbstractList`'s iterator is
     * implemented in terms of [get]) — so a linear implementation cannot dodge the counter.
     */
    private class CountingIntList(private val backing: IntArray) : AbstractList<Int>() {
        var reads: Int = 0
            private set

        override val size: Int get() = backing.size

        override fun get(index: Int): Int {
            reads++
            return backing[index]
        }

        fun resetReads() {
            reads = 0
        }
    }
}
