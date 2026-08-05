package com.vreader.app.reader.nav

import com.vreader.app.reader.foliate.FoliateTocParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import kotlin.random.Random

/**
 * Feature #140 WI-4 — [foliateTocIndexFor]: the AZW3 Contents sheet's current-chapter highlight,
 * mapping foliate's own `relocate.tocHref` to the row to highlight.
 *
 * The properties this suite exists to protect:
 *
 * - **The `-1`-vs-`0` contract is EXACTLY `ReaderChromeModel.tocIndexFor`'s** (and
 *   [txtTocIndexFor]'s). `-1` means "there is no row to highlight" and is legal ONLY for an empty
 *   TOC. Once a TOC exists the answer is never `-1`: an unknown or unmatched href highlights the
 *   FIRST row, because a missing highlight is worse than a best-effort one.
 *   [emptyEntries_returnsMinusOne] pins one half, [noMatch_butTocExists_returnsZero] and
 *   [nullHref_butTocExists_returnsZero] the other; an implementation that collapses the two states
 *   fails whichever side it collapsed onto.
 * - **A duplicate href resolves to the LAST match, not the first.** A parent and its first child
 *   legitimately share one href in a real NCX; the deepest row is the one the reader is actually in.
 *   [duplicateHrefs_returnsTheLastMatch] uses runs whose first and last members sit at DIFFERENT
 *   indices, and asserts the index — a fixture with one shared href, or an assertion that "something
 *   matched", cannot tell first-match from last-match apart.
 * - **Matching is EXACT STRING EQUALITY — no trimming, no case folding, no percent-decoding, no
 *   fragment or query stripping, no Unicode normalization** (the plan's "byte-exact"; precisely,
 *   `String.equals` over the already-JSON-decoded strings).
 *   WI-2 preserves hrefs byte-for-byte precisely so this comparison works, and
 *   two rows differing only by `#fragment` / `?query` / the KF8 `:off:` segment are DISTINCT rows
 *   that must not collapse onto one another. Every normalization has its own killer fixture, each
 *   built so the normalizing implementation returns a DIFFERENT index rather than merely a
 *   coincidentally-equal one.
 * - **Behaviour is pinned differentially, not by fixtures alone.**
 *   [differentialAgainstLastIndexOfReference_acrossSizesToTheCap] compares every answer against a
 *   `lastIndexOf` reference (stdlib mechanics, not the loop under test) over seeded random shapes
 *   from size 0 to [FoliateTocParser.MAX_TOC_ENTRIES], so a size-keyed or shape-keyed mutant cannot
 *   hide in whatever size the fixtures missed.
 *
 * Pure JVM — no Android runtime, no Robolectric, no emulator.
 */
class FoliateTocIndexTest {

    private companion object {
        /** The workhorse fixture: three distinct chapter hrefs. */
        val THREE = listOf("p1.xhtml", "c1.xhtml", "c2.xhtml")

        /** Fixed so the differential sweep is reproducible, never flaky. */
        const val DIFFERENTIAL_SEED = 20_260_805L
    }

    // ── The -1-vs-0 contract ────────────────────────────────────────────────────────────────

    @Test
    fun emptyEntries_returnsMinusOne() {
        // The ONLY input that may answer -1: no TOC, so there is no row to highlight.
        assertEquals(-1, foliateTocIndexFor("c1.xhtml", emptyList()))
        assertEquals(-1, foliateTocIndexFor(null, emptyList()))
        assertEquals(-1, foliateTocIndexFor("", emptyList()))
    }

    @Test
    fun noMatch_butTocExists_returnsZero() {
        // A TOC exists but the reader's href names no row → the FIRST row, never -1.
        assertEquals(0, foliateTocIndexFor("nowhere.xhtml", THREE))
        assertEquals(0, foliateTocIndexFor("", THREE))
        // Stated separately so the -1/0 confusion can never pass silently.
        assertNotEquals(-1, foliateTocIndexFor("nowhere.xhtml", THREE))
    }

    @Test
    fun nullHref_butTocExists_returnsZero() {
        // No position known yet (or foliate had no `tocItem`) is NOT "no TOC".
        assertEquals(0, foliateTocIndexFor(null, THREE))
        assertNotEquals(-1, foliateTocIndexFor(null, THREE))
        // A null query must not "match" a null ENTRY href either — the fallback is row 0, and this
        // fixture makes the two answers differ.
        assertEquals(0, foliateTocIndexFor(null, listOf("a.xhtml", null, "b.xhtml")))
    }

    @Test
    fun nullEntryHrefs_neverMatch_andDoNotBreakLaterRows() {
        // A row with no href can reach here (Locator.href is nullable); it simply never matches, and
        // must not shift or short-circuit the rows after it.
        val withNulls = listOf("a.xhtml", null, "b.xhtml", null)
        assertEquals(0, foliateTocIndexFor("a.xhtml", withNulls))
        assertEquals(2, foliateTocIndexFor("b.xhtml", withNulls))
        // All-null entries: a TOC still exists, so the fallback is 0 rather than -1.
        assertEquals(0, foliateTocIndexFor("a.xhtml", listOf(null, null)))
    }

    // ── Exact match + duplicate resolution ──────────────────────────────────────────────────

    @Test
    fun exactMatch_returnsThatIndex() {
        assertEquals(0, foliateTocIndexFor("p1.xhtml", THREE))
        assertEquals(1, foliateTocIndexFor("c1.xhtml", THREE))
        assertEquals(2, foliateTocIndexFor("c2.xhtml", THREE))
        // Single-row TOC.
        assertEquals(0, foliateTocIndexFor("only.xhtml", listOf("only.xhtml")))
    }

    @Test
    fun duplicateHrefs_returnsTheLastMatch() {
        // A part and its first chapter legitimately point at the same file in a real NCX. The LAST
        // (deepest) row is the one the user is actually in; first-match would highlight the container.
        val parentThenChild = listOf("p1.xhtml", "p1.xhtml", "c2.xhtml")
        assertEquals(1, foliateTocIndexFor("p1.xhtml", parentThenChild))
        assertNotEquals(0, foliateTocIndexFor("p1.xhtml", parentThenChild))

        // A run of three in the MIDDLE of the list: first-match answers 1, last-match answers 3, and
        // neither is the list's first or last index — so no positional accident can produce it.
        val run = listOf("a.xhtml", "b.xhtml", "b.xhtml", "b.xhtml", "c.xhtml")
        assertEquals(3, foliateTocIndexFor("b.xhtml", run))
        assertEquals(0, foliateTocIndexFor("a.xhtml", run))
        assertEquals(4, foliateTocIndexFor("c.xhtml", run))

        // Non-adjacent duplicates (a TOC that revisits a file later) resolve to the later row too.
        val revisited = listOf("x.xhtml", "y.xhtml", "x.xhtml", "z.xhtml")
        assertEquals(2, foliateTocIndexFor("x.xhtml", revisited))
    }

    // ── Byte-exact matching (no normalization of any kind) ──────────────────────────────────

    @Test
    fun matchIsByteExact_noNormalization_noTrimming() {
        // Indices 0-3 are trim/case twins of one another: an implementation that trims or folds case
        // collapses them and answers the LAST twin instead of the exact row, so those assertions are
        // its killers. The percent-encoded (4) and blank (5) rows are NOT twins of index 0 — they are
        // killed separately, by the assertions at the end of this test, which is why each fixture is
        // chosen so a normalizing implementation returns a DIFFERENT index rather than the same one
        // by luck.
        val twins = listOf(
            "c1.xhtml",      // 0 — the canonical form
            " c1.xhtml",     // 1 — leading space
            "c1.xhtml ",     // 2 — trailing space
            "C1.XHTML",      // 3 — case
            "c1%20a.xhtml",  // 4 — percent-encoded
            "   ",           // 5 — blank, which is NOT "unknown" at this layer
        )
        assertEquals(0, foliateTocIndexFor("c1.xhtml", twins)) // an impl that trims + folds answers 3
        assertEquals(1, foliateTocIndexFor(" c1.xhtml", twins))
        assertEquals(2, foliateTocIndexFor("c1.xhtml ", twins))
        assertEquals(3, foliateTocIndexFor("C1.XHTML", twins))
        assertEquals(4, foliateTocIndexFor("c1%20a.xhtml", twins))
        // A blank current href is not treated as "position unknown": it matches its own row exactly.
        assertEquals(5, foliateTocIndexFor("   ", twins))

        // The decoded twin of index 4 is a DIFFERENT href and must not match it.
        assertNotEquals(4, foliateTocIndexFor("c1 a.xhtml", twins))
        assertEquals(0, foliateTocIndexFor("c1 a.xhtml", twins)) // → the no-match fallback
    }

    @Test
    fun hrefsDifferingOnlyByFragment_areDistinctRows() {
        // Gate-2 R1 Low: a fragment-stripping implementation collapses all three onto the LAST row,
        // so the first two assertions are its killers.
        val fragments = listOf("c1.xhtml", "c1.xhtml#s1", "c1.xhtml#s2")
        assertEquals(0, foliateTocIndexFor("c1.xhtml", fragments))
        assertEquals(1, foliateTocIndexFor("c1.xhtml#s1", fragments))
        assertEquals(2, foliateTocIndexFor("c1.xhtml#s2", fragments))
        // An unlisted fragment of a listed file is a no-match → row 0, NOT the file's other rows.
        assertEquals(0, foliateTocIndexFor("c1.xhtml#s9", fragments))
        // A bare `#` and an empty fragment are still distinct strings.
        assertEquals(0, foliateTocIndexFor("c1.xhtml#", fragments))
    }

    @Test
    fun hrefWithQuerySuffix_matchesOnlyItself() {
        val queries = listOf("c1.xhtml?v=2", "c1.xhtml", "c1.xhtml?v=2#s1")
        assertEquals(0, foliateTocIndexFor("c1.xhtml?v=2", queries))
        assertEquals(1, foliateTocIndexFor("c1.xhtml", queries))
        assertEquals(2, foliateTocIndexFor("c1.xhtml?v=2#s1", queries))
        assertEquals(0, foliateTocIndexFor("c1.xhtml?v=3", queries)) // no-match fallback
    }

    @Test
    fun kf8PosUriHrefs_matchOnTheExactOffsetSegment() {
        // Real Kindle shapes: KF8 `kindle:pos:fid:…:off:…` and MOBI6 `filepos:NNNN`.
        val kindle = listOf(
            "kindle:pos:fid:0000:off:0000000000",
            "kindle:pos:fid:0001:off:0000000123",
            "kindle:pos:fid:0001:off:0000000456",
            "filepos:0000001234",
        )
        assertEquals(1, foliateTocIndexFor("kindle:pos:fid:0001:off:0000000123", kindle))
        assertEquals(2, foliateTocIndexFor("kindle:pos:fid:0001:off:0000000456", kindle))
        assertEquals(3, foliateTocIndexFor("filepos:0000001234", kindle))
        // Same fid, unlisted offset: distinct row, so the no-match fallback — never the sibling.
        assertEquals(0, foliateTocIndexFor("kindle:pos:fid:0001:off:0000000999", kindle))
        assertNotEquals(2, foliateTocIndexFor("kindle:pos:fid:0001:off:0000000999", kindle))
        // A prefix of a listed href is not a match (no startsWith matching).
        assertEquals(0, foliateTocIndexFor("kindle:pos:fid:0001", kindle))
    }

    @Test
    fun cjkHref_matches() {
        // decodeURI at foliate-bundle.js:1753 means non-ASCII hrefs really do reach Kotlin decoded.
        val cjk = listOf("序章.xhtml", "第二章.xhtml", "第二章.xhtml#节2", "📕.xhtml")
        assertEquals(0, foliateTocIndexFor("序章.xhtml", cjk))
        assertEquals(1, foliateTocIndexFor("第二章.xhtml", cjk))
        assertEquals(2, foliateTocIndexFor("第二章.xhtml#节2", cjk))
        // Astral plane: a surrogate pair is compared as part of the whole string — no code-point
        // vs code-unit slicing anywhere in the comparison.
        assertEquals(3, foliateTocIndexFor("📕.xhtml", cjk))
        assertEquals(0, foliateTocIndexFor("第三章.xhtml", cjk)) // no-match fallback
    }

    @Test
    fun canonicallyEquivalentHrefs_areDistinctRows() {
        // Gate-4 R1 Medium: NFC ("café") and NFD ("café") render identically and are
        // canonically equivalent, but they are DIFFERENT hrefs — an EPUB inside an AZW3 container can
        // carry either form, and foliate hands both back verbatim. A `Normalizer.normalize` inserted
        // before the comparison would collapse them onto one row and survive every other fixture in
        // this suite; these two rows sit at distinct non-zero indices so it cannot.
        val nfc = "café.xhtml"
        val nfd = "café.xhtml"
        // The fixture is only meaningful if the two literals really are different strings — assert
        // it, so a future editor/formatter that silently normalized this source file fails loudly
        // here instead of turning the whole test into a tautology.
        assertNotEquals(nfc, nfd)
        assertEquals(nfc.length + 1, nfd.length) // NFD carries the combining mark as its own unit

        val entries = listOf("a.xhtml", nfc, nfd, "z.xhtml")
        assertEquals(1, foliateTocIndexFor(nfc, entries))
        assertEquals(2, foliateTocIndexFor(nfd, entries))
        assertNotEquals(foliateTocIndexFor(nfc, entries), foliateTocIndexFor(nfd, entries))
        // Reversed order too, so the answer cannot be a normalizing impl's last-match by luck.
        val reversed = listOf("a.xhtml", nfd, nfc, "z.xhtml")
        assertEquals(2, foliateTocIndexFor(nfc, reversed))
        assertEquals(1, foliateTocIndexFor(nfd, reversed))
    }

    // ── Differential (the closure for size-/shape-keyed mutants) ────────────────────────────

    /**
     * A trivial reference: the documented contract restated over `lastIndexOf`, whose mechanics are
     * stdlib rather than the explicit indexed loop under test, so agreement is evidence and not a
     * tautology.
     */
    private fun referenceTocIndexFor(currentTocHref: String?, entryHrefs: List<String?>): Int {
        if (entryHrefs.isEmpty()) return -1
        if (currentTocHref == null) return 0
        val at = entryHrefs.lastIndexOf(currentTocHref)
        return if (at >= 0) at else 0
    }

    @Test
    fun differentialAgainstLastIndexOfReference_acrossSizesToTheCap() {
        // Sizes 0..64 exhaustively (where hand-written special cases actually live) plus the
        // production cap and its neighbours. Hrefs are drawn from a tiny alphabet so duplicates,
        // fragment twins and misses all occur densely; every href in the alphabet is queried against
        // every shape, plus null and an absent href.
        val random = Random(seed = DIFFERENTIAL_SEED)
        val alphabet = listOf(
            "a.xhtml", "a.xhtml#s1", "b.xhtml", "b.xhtml?v=1",
            "kindle:pos:fid:0001:off:0000000123", "第一章.xhtml", "", "   ",
        )
        val cap = FoliateTocParser.MAX_TOC_ENTRIES
        val sizes = (0..64).toList() + listOf(65, 128, 999, cap - 1, cap, cap + 1)

        for (size in sizes) {
            val entries = List<String?>(size) {
                // ~1 in 12 rows carries no href at all, mirroring a dropped-locator row.
                if (random.nextInt(12) == 0) null else alphabet[random.nextInt(alphabet.size)]
            }
            val probes: List<String?> = alphabet + listOf(null, "absent.xhtml", "A.XHTML", " a.xhtml")
            for (probe in probes) {
                assertEquals(
                    "size=$size probe=$probe (seed=$DIFFERENTIAL_SEED)",
                    referenceTocIndexFor(probe, entries),
                    foliateTocIndexFor(probe, entries),
                )
            }
        }
    }

    @Test
    fun differentialOverRandomShapes_withPlantedDuplicateRuns() {
        // Seeded random shapes whose duplicate runs are PLANTED at random positions (including the
        // head and tail), so last-match resolution is exercised at every position in the list rather
        // than only where a hand-written fixture put it.
        val random = Random(seed = DIFFERENTIAL_SEED + 1)
        repeat(400) {
            val size = 1 + random.nextInt(40)
            val entries = MutableList<String?>(size) { "h${random.nextInt(6)}.xhtml" }
            repeat(random.nextInt(3)) {
                val start = random.nextInt(size)
                val runLength = 1 + random.nextInt(4)
                val value = "dup${random.nextInt(2)}.xhtml"
                for (i in start until minOf(size, start + runLength)) entries[i] = value
            }
            if (size >= 2) entries[random.nextInt(size)] = null

            val probes = (0 until 6).map { "h$it.xhtml" } + listOf("dup0.xhtml", "dup1.xhtml", null, "miss.xhtml")
            for (probe in probes) {
                assertEquals(
                    "entries=$entries probe=$probe",
                    referenceTocIndexFor(probe, entries),
                    foliateTocIndexFor(probe, entries),
                )
            }
        }
    }
}
