package com.vreader.app.reader.nav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

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
 *   [TxtMdTocProvider.MAX_TOC_ENTRIES]-sized cap, over both an evenly-spaced and a heavily skewed
 *   offset distribution. A linear scan reads tens of thousands of elements and fails the bound; a
 *   binary search reads ~16 on either shape.
 * - **No size- or shape-keyed special case can hide.** Three tests sweep an independent
 *   `indexOfLast` oracle across the whole offset domain:
 *   [everyOffsetAndShape_agreesWithTheLinearReference] over sizes 0..8 (duplicate runs, a TOC
 *   starting at offset 0), [intermediateAndCapSizes_agreeWithTheLinearReference] over 9..the
 *   production cap, and [randomizedMonotonicShapes_agreeWithTheLinearReference] over 300 seeded
 *   random shapes. Successive Gate-4 rounds each built a mutant living in whatever size gap the
 *   fixtures left — first `size <= 2`, then `size in 9..MAX_TOC_ENTRIES` — so the answer is a
 *   continuum plus randomization, not one more hand-listed size.
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

        /** The element-read ceiling the complexity probe enforces — see its own comment. */
        const val MAX_READS = 64
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
    fun twoEntries_secondBoundaryAndDuplicateRightBias() {
        // The size-2 shape specifically. It is the smallest list where "always answer 0" stops being
        // correct, so a suite that jumps from 1 entry to 3 leaves a hole a size-keyed fast path
        // (`if (size <= 2) return 0`) slips through — correct for one entry, wrong for two.
        val two = listOf(100, 200)
        assertEquals(0, txtTocIndexFor(99, two))
        assertEquals(0, txtTocIndexFor(199, two))
        assertEquals(1, txtTocIndexFor(200, two))
        assertEquals(1, txtTocIndexFor(Int.MAX_VALUE, two))
        // Right-bias with exactly two equal offsets.
        assertEquals(1, txtTocIndexFor(100, listOf(100, 100)))
    }

    @Test
    fun everyOffsetAndShape_agreesWithTheLinearReference() {
        // Exhaustive cross-check of the whole offset domain against the plain-English rule ("last
        // entry at-or-before, else 0; -1 only when empty") across MANY SHAPES AND SIZES — not one
        // fixture. Sweeping sizes 0..8, duplicate runs, and a list starting at offset 0 is what
        // closes the door on size- or shape-keyed special casing, which any single-fixture suite
        // (however dense in the offset dimension) cannot see. The oracle is `indexOfLast`, which
        // shares no mechanics with the binary search under test, so this is not a tautology.
        val shapes = listOf(
            emptyList(),
            listOf(3),
            listOf(3, 7),
            listOf(0, 1),
            listOf(4, 4),
            listOf(3, 7, 8),
            listOf(5, 5, 5),
            listOf(3, 7, 8, 15),
            listOf(0, 4, 4, 9, 9, 9, 12),
            listOf(3, 7, 8, 15, 16, 23, 42),
            listOf(0, 1, 2, 3, 4, 5, 6, 7),
        )
        for (entries in shapes) {
            for (offset in -5..50) {
                val expected = if (entries.isEmpty()) {
                    -1
                } else {
                    entries.indexOfLast { it <= offset }.let { if (it >= 0) it else 0 }
                }
                assertEquals("entries=$entries offset=$offset", expected, txtTocIndexFor(offset, entries))
            }
        }
    }

    @Test
    fun intermediateAndCapSizes_agreeWithTheLinearReference() {
        // The sizes BETWEEN the small shapes above and the complexity fixture below — including the
        // production cap itself, the largest TOC TxtMdTocProvider will ever emit. A Gate-4 round-3
        // mutant lived exactly in this hole (`if (size in 9..MAX_TOC_ENTRIES) return 0`), invisible
        // while the correctness shapes stopped at 8 and the only large fixture was cap + 1.
        val sizes = listOf(9, 16, 17, 33, 257, 1_000, TxtMdTocProvider.MAX_TOC_ENTRIES)
        for (size in sizes) {
            val backing = IntArray(size) { it * 7 }
            // Plant a duplicate run mid-list so right-bias is exercised at every size, not just the
            // hand-built small shapes. Still non-decreasing: the slot is lowered onto its predecessor.
            if (size >= 3) backing[size / 2] = backing[size / 2 - 1]
            val entries = backing.toList()

            val queries = listOf(
                -1, 0,
                backing[0], backing[0] + 1,
                backing[size / 2 - 1], backing[size / 2], backing[size / 2] + 1,
                backing[size - 2], backing[size - 1], backing[size - 1] + 1,
                Int.MAX_VALUE,
            )
            for (query in queries) {
                val expected = backing.indexOfLast { it <= query }.let { if (it >= 0) it else 0 }
                assertEquals("size=$size offset=$query", expected, txtTocIndexFor(query, entries))
            }
        }
    }

    @Test
    fun randomizedMonotonicShapes_agreeWithTheLinearReference() {
        // A SEEDED (deterministic — never flaky) sweep over many random sizes and random
        // non-decreasing offset shapes, each queried across its whole domain.
        //
        // Why this exists: no finite list of example shapes can rule out "special-case exactly the
        // sizes nobody tested" — two Gate-4 rounds each found a fresh size-keyed mutant in whatever
        // gap the previous fixtures left. Enumerating more sizes only moves the gap. This test
        // changes the shape of the argument: an implementation that survives hundreds of
        // pseudo-randomly sized and spaced shapes AND the cap-sized fixtures above is no longer
        // "untested at some size", it is one that special-cases nothing.
        val random = Random(seed = 1395L)
        repeat(300) {
            val size = 1 + random.nextInt(64)
            var next = random.nextInt(5)
            val entries = ArrayList<Int>(size)
            repeat(size) {
                entries.add(next)
                next += random.nextInt(4) // a 0 step plants duplicate offsets naturally
            }
            for (offset in -2..(entries.last() + 3)) {
                val expected = entries.indexOfLast { it <= offset }.let { if (it >= 0) it else 0 }
                assertEquals("entries=$entries offset=$offset", expected, txtTocIndexFor(offset, entries))
            }
        }
    }

    // ── Complexity ──────────────────────────────────────────────────────────────────────────

    @Test
    fun isBinarySearch_not_linear_over50000Entries() {
        // BOTH the production cap — TxtMdTocProvider REJECTS a document with more than
        // MAX_TOC_ENTRIES headings (it emits an empty TOC rather than truncating), so a 50 000-row
        // TOC is the largest list that can actually reach this function — and cap + 1 as a margin.
        val cap = TxtMdTocProvider.MAX_TOC_ENTRIES

        // TWO monotonic distributions per size. A single evenly-spaced fixture would let an
        // interpolation search look logarithmic here while degrading towards linear on a real book,
        // whose chapters are not evenly spaced: `skewed` packs all but the last 100 entries into a
        // narrow head and then jumps three orders of magnitude, its worst case.
        fun uniform(n: Int) = IntArray(n) { it * 10 }
        fun skewed(n: Int) = IntArray(n) { i -> if (i < n - 100) i * 2 else 500_000_000 + (i - (n - 100)) * 1_000 }

        val fixtures = listOf(
            "uniform@$cap" to uniform(cap),
            "uniform@${cap + 1}" to uniform(cap + 1),
            "skewed@$cap" to skewed(cap),
            "skewed@${cap + 1}" to skewed(cap + 1),
        )
        for ((shape, backing) in fixtures) {
            val size = backing.size
            val list = CountingIntList(backing)
            val queries = listOf(
                -1,                        // before everything
                backing[0],                // exactly the first
                backing[0] + 1,
                backing[size / 2],         // exactly a midpoint entry
                backing[size / 2] + 1,     // just inside it
                backing[size - 1],         // exactly the last
                Int.MAX_VALUE,             // past everything
            )
            for (query in queries) {
                list.resetReads()
                val index = txtTocIndexFor(query, list)
                val label = "$shape offset=$query"

                // The probe must also prove the answer is RIGHT — a function that returned a
                // constant without reading anything would otherwise pass the bound for free. The
                // oracle scans the raw IntArray (never the counted list), so it neither perturbs
                // the counter nor re-derives the fixture's arithmetic.
                val expected = backing.indexOfLast { it <= query }.let { if (it >= 0) it else 0 }
                assertEquals("index for $label", expected, index)

                // ceil(log2(50002)) == 16, so one probe per level reads ~16. MAX_READS = 64 leaves
                // 4x headroom, so a correct-but-constant-heavier O(log n) variant (e.g. two bound
                // searches plus endpoint probes, ~34 reads) cannot false-fail — while staying well
                // below sqrt-n jump search (~224), read-heavy O(log^2 n) (~256) and a linear scan
                // (50 001), all of which this bound still rejects.
                assertTrue(
                    "$label read ${list.reads} of $size elements; a logarithmic search reads " +
                        "<= $MAX_READS (a linear scan would read ~$size)",
                    list.reads <= MAX_READS,
                )
                assertTrue("$label read nothing — the answer cannot have been searched for", list.reads > 0)
            }
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
