package com.vreader.app.search

import com.vreader.app.data.Book
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import java.io.File

/**
 * Feature #133 WI-4 — [TxtMdInBookHitResolver]: maps a matched TXT/MD chunk (its `sectionIndex`) plus a
 * [RawOccurrence] (WI-3's raw-offset span) to a jumpable canonical [vreader.contracts.Locator] via the
 * DETERMINISTIC re-derivation the round-2 Critical-2 resolution relies on —
 * `charOffsetUTF16 = TxtDocument.offsetForChunk(sectionIndex) + rawOccurrence.startUtf16`. No stored offset
 * column: `TxtDocument.of(decodedText)` re-derives the SAME chunk boundaries the extractor used (TXT/MD
 * chunking is a pure function of the decoded source), so `chunkForOffset(resolvedOffset)` round-trips back
 * to the matched `sectionIndex`.
 *
 * Robolectric-run to match the sibling search suites' harness (the resolver itself is pure JVM; the runner
 * just keeps the source set uniform). CJK chars are written explicitly so the raw UTF-16 offset assertions
 * are unambiguous. The tests use the REAL [TxtDocument] / [TxtMdTextExtractor] / [RawOffsetMatcher] (no
 * stubs) so the extract->resolve round-trip is genuine.
 *
 * Invariants asserted:
 * - `charOffsetUTF16 == offsetForChunk(sectionIndex) + rawStart` (exact re-derivation).
 * - extract->resolve->`chunkForOffset` round-trips back to the matched chunk.
 * - `validatedOrNull()` is applied — a valid resolution is non-null and carries the correct `fingerprintKey`.
 * - CJK occurrences resolve to the EXACT UTF-16 char offset (not a byte / segmented offset).
 * - The first and last chunk boundaries resolve correctly (edge chunk).
 * - The canonical `Locator` carries the occurrence's raw span as `charRangeStart/End`.
 */
@RunWith(RobolectricTestRunner::class)
class TxtMdInBookHitResolverTest {

    // A valid identity triple (64-lowercase-hex sha) so the canonical key parses.
    private val sha = "a".repeat(64)
    private val byteCount = 4096L
    private val fpKey = "txt:$sha:$byteCount"

    private fun resolver(text: String, format: String = "txt"): TxtMdInBookHitResolver =
        TxtMdInBookHitResolver(
            contentSHA256 = sha,
            fileByteCount = byteCount,
            format = format,
            decodedText = text,
        )

    /** A collecting fake sink: records every emit (mirrors TxtMdTextExtractorTest.CollectingSink). */
    private class CollectingSink : SectionSink {
        val sections = mutableListOf<BookTextSection>()
        override suspend fun emit(section: BookTextSection) { sections.add(section) }
        override suspend fun flushRemaining() {}
    }

    private fun bookFor(file: File, format: BookFormat = BookFormat.txt) = Book(
        fingerprintKey = "${format.name}:$sha:$byteCount",
        title = "T", originalFormat = format, contentSHA256 = sha,
        fileByteCount = byteCount, localFilePath = file.absolutePath, addedAt = 1L,
    )

    private fun writeTemp(name: String, text: String): File {
        val f = File.createTempFile("wi4-$name", ".txt")
        f.writeBytes(text.toByteArray(Charsets.UTF_8))
        f.deleteOnExit()
        return f
    }

    // ── exact offset re-derivation ──────────────────────────────────────────────

    @Test
    fun charOffset_isChunkStartPlusRawStart() {
        // Three lines → three chunks (each ends after its LF); "needle" sits in the 2nd chunk.
        val text = "first line\nsecond needle line\nthird line\n"
        val doc = TxtDocument.of(text)
        val sectionIndex = 1
        val chunkStart = doc.offsetForChunk(sectionIndex)
        val chunkText = doc.textForChunk(sectionIndex).toString()
        val rawStart = chunkText.indexOf("needle")
        assertTrue("fixture sanity: needle in chunk 1", rawStart >= 0)

        val occ = RawOccurrence(startUtf16 = rawStart, endUtf16 = rawStart + "needle".length, occurrenceIndex = 0)
        val locator = resolver(text).resolve(sectionIndex, occ)

        assertNotNull(locator)
        assertEquals(chunkStart + rawStart, locator!!.charOffsetUTF16)
        // And it points at the absolute position of "needle" in the whole text.
        assertEquals(text.indexOf("needle"), locator.charOffsetUTF16)
    }

    // ── extract → resolve → chunkForOffset round-trip ───────────────────────────

    @Test
    fun roundTrip_resolvedOffsetMapsBackToMatchedChunk() {
        // A newline-dense body so chunking splits on line boundaries (deterministic pure function).
        val body = (0 until 12).joinToString("\n") { "line $it has some searchable body text here" } + "\n"
        val doc = TxtDocument.of(body)
        assertTrue("fixture sanity: multiple chunks", doc.chunkCount >= 3)
        val resolver = resolver(body)

        // For EVERY chunk, resolve an occurrence at the chunk's local offset 0 and assert the
        // resolved absolute offset maps back (via chunkForOffset) to the SAME chunk.
        for (sectionIndex in 0 until doc.chunkCount) {
            val occ = RawOccurrence(startUtf16 = 0, endUtf16 = 4, occurrenceIndex = 0)
            val locator = resolver.resolve(sectionIndex, occ)
            assertNotNull("chunk $sectionIndex resolves", locator)
            val backChunk = doc.chunkForOffset(locator!!.charOffsetUTF16!!)
            assertEquals("chunk $sectionIndex round-trips", sectionIndex, backChunk)
        }
    }

    @Test
    fun roundTrip_matchesRealExtractorBoundaries() = runTest {
        // Drive the REAL TxtMdTextExtractor.extract() over a real temp file, then resolve an occurrence
        // located within EACH emitted BookTextSection and assert the resolved offset maps back (via the
        // resolver's independently re-derived TxtDocument) to the SAME sectionIndex the extractor emitted.
        // This proves the resolver's re-derivation matches what the FTS index was built from — no drift.
        val body = (0 until 8).joinToString("\n") { "chapter $it needle paragraph with words" } + "\n"
        val file = writeTemp("extract", body)
        val sink = CollectingSink()
        val result = TxtMdTextExtractor().extract(bookFor(file), sink)
        assertTrue("extraction succeeded", result is ExtractResult.Success)
        assertTrue("multiple sections emitted", sink.sections.size >= 3)

        val resolver = resolver(body)
        val doc = TxtDocument.of(body)
        assertEquals("resolver chunk count == extractor section count", sink.sections.size, doc.chunkCount)

        for (section in sink.sections) {
            // Locate "needle" INSIDE the extractor-emitted section text, resolve it, and round-trip.
            val rawStart = section.text.indexOf("needle")
            assertTrue("needle in section ${section.sectionIndex}", rawStart >= 0)
            val occ = RawOccurrence(rawStart, rawStart + "needle".length, occurrenceIndex = 0)
            val locator = resolver.resolve(section.sectionIndex, occ)
            assertNotNull("section ${section.sectionIndex} resolves", locator)
            // The resolved offset maps back to the SAME section the extractor emitted.
            assertEquals(
                "section ${section.sectionIndex} round-trips",
                section.sectionIndex,
                doc.chunkForOffset(locator!!.charOffsetUTF16!!),
            )
            // And it equals the extractor's own chunk-start + the raw offset (exact re-derivation).
            assertEquals(doc.offsetForChunk(section.sectionIndex) + rawStart, locator.charOffsetUTF16)
        }
    }

    // ── validation + fingerprint identity ───────────────────────────────────────

    @Test
    fun validResolution_isNonNull_withCorrectFingerprint() {
        val text = "alpha beta gamma\n"
        val occ = RawOccurrence(startUtf16 = 6, endUtf16 = 10, occurrenceIndex = 0)  // "beta"
        val locator = resolver(text).resolve(0, occ)

        assertNotNull(locator)
        assertEquals(fpKey, locator!!.fingerprintKey)
        assertNull("valid resolution passes validatedOrNull", locator.validate())
        assertEquals(sha, locator.contentSHA256)
        assertEquals(byteCount, locator.fileByteCount)
        assertEquals("txt", locator.format)
    }

    @Test
    fun locator_carriesOccurrenceRangeAsCharRange() {
        val text = "the quick brown fox\n"
        val chunkStart = TxtDocument.of(text).offsetForChunk(0)  // 0
        val occ = RawOccurrence(startUtf16 = 4, endUtf16 = 9, occurrenceIndex = 0)  // "quick"
        val locator = resolver(text).resolve(0, occ)!!

        assertEquals(chunkStart + 4, locator.charOffsetUTF16)
        assertEquals(chunkStart + 4, locator.charRangeStartUTF16)
        assertEquals(chunkStart + 9, locator.charRangeEndUTF16)
        assertNull("range is well-formed", locator.validate())
    }

    // ── CJK exact UTF-16 offset (not byte / segmented) ──────────────────────────

    @Test
    fun cjk_resolvesToExactUtf16Offset() {
        // 关于\n编程的书\n很好\n — the "编程" phrase sits in chunk 1 at local UTF-16 offset 0.
        val guanYu = "关于"      // 关于
        val bianCheng = "编程"   // 编程
        val deShu = "的书"       // 的书
        val henHao = "很好"      // 很好
        val text = "$guanYu\n$bianCheng$deShu\n$henHao\n"
        val doc = TxtDocument.of(text)
        val sectionIndex = 1
        val chunkText = doc.textForChunk(sectionIndex).toString()
        val rawStart = chunkText.indexOf(bianCheng)   // 0 — start of the 2nd chunk
        assertEquals(0, rawStart)

        val occ = RawOccurrence(startUtf16 = rawStart, endUtf16 = rawStart + bianCheng.length, occurrenceIndex = 0)
        val locator = resolver(text).resolve(sectionIndex, occ)!!

        // 关于 = 2 UTF-16 units + '\n' = 3 → chunk 1 starts at UTF-16 offset 3.
        assertEquals(3, doc.offsetForChunk(sectionIndex))
        assertEquals(3, locator.charOffsetUTF16)
        // Exactly the absolute UTF-16 index of 编程 in the whole string (NOT a byte offset).
        assertEquals(text.indexOf(bianCheng), locator.charOffsetUTF16)
        // Sanity: the byte offset would be larger (each CJK char = 3 UTF-8 bytes) — prove we're NOT byte-based.
        assertTrue("resolved offset is char-based, not byte-based", locator.charOffsetUTF16!! < 3 * 3)
    }

    @Test
    fun cjk_endToEnd_viaRealMatcher() {
        // Drive the WHOLE TXT/MD track for a CJK query: extract chunks, MATCH via the real matcher, resolve.
        val guanYu = "关于"      // 关于
        val bianCheng = "编程"   // 编程
        val deShu = "的书"       // 的书
        val text = "$guanYu\n$guanYu$bianCheng$deShu\n"   // "编程" only in chunk 1
        val doc = TxtDocument.of(text)
        val query = SearchQueryBuilder.structuredQuery(bianCheng)!!
        val resolver = resolver(text)

        // The matched chunk is chunk 1 (contains 编程).
        val sectionIndex = 1
        val chunkText = doc.textForChunk(sectionIndex).toString()
        val slice = RawOffsetMatcher.occurrences(chunkText, query, fromOccurrenceIndex = 0, maxThisPage = 10)
        assertEquals(1, slice.occurrences.size)
        val occ = slice.occurrences.first()

        val locator = resolver.resolve(sectionIndex, occ)!!
        // 关于 in chunk 1 is 2 units before 编程; chunk 1 starts after "关于\n" = 3 units.
        assertEquals(text.indexOf(bianCheng), locator.charOffsetUTF16)
        assertEquals(sectionIndex, doc.chunkForOffset(locator.charOffsetUTF16!!))
    }

    // ── edge chunks (first + last boundary) ─────────────────────────────────────

    @Test
    fun edgeChunk_firstChunkStartsAtZero() {
        val text = "opening chunk\nmiddle chunk\nfinal chunk\n"
        val occ = RawOccurrence(startUtf16 = 0, endUtf16 = 7, occurrenceIndex = 0)  // "opening"
        val locator = resolver(text).resolve(0, occ)!!
        assertEquals(0, locator.charOffsetUTF16)
        assertEquals(0, TxtDocument.of(text).chunkForOffset(0))
    }

    @Test
    fun edgeChunk_lastChunkResolvesInRange() {
        val text = "opening chunk\nmiddle chunk\nfinal needle chunk\n"
        val doc = TxtDocument.of(text)
        val lastIndex = doc.chunkCount - 1
        val chunkText = doc.textForChunk(lastIndex).toString()
        val rawStart = chunkText.indexOf("needle")
        assertTrue(rawStart >= 0)

        val occ = RawOccurrence(startUtf16 = rawStart, endUtf16 = rawStart + "needle".length, occurrenceIndex = 0)
        val locator = resolver(text).resolve(lastIndex, occ)!!

        assertEquals(text.indexOf("needle"), locator.charOffsetUTF16)
        assertEquals(lastIndex, doc.chunkForOffset(locator.charOffsetUTF16!!))
        // In range: past the last chunk start, before EOF.
        assertTrue(locator.charOffsetUTF16!! >= doc.offsetForChunk(lastIndex))
        assertTrue(locator.charOffsetUTF16!! < text.length)
    }

    // ── md format parity ────────────────────────────────────────────────────────

    @Test
    fun md_format_resolvesSameWay() {
        val text = "# Heading\nsome markdown needle body\n"
        val doc = TxtDocument.of(text)
        val sectionIndex = 1
        val chunkText = doc.textForChunk(sectionIndex).toString()
        val rawStart = chunkText.indexOf("needle")
        val occ = RawOccurrence(startUtf16 = rawStart, endUtf16 = rawStart + "needle".length, occurrenceIndex = 0)

        val locator = resolver(text, format = "md").resolve(sectionIndex, occ)!!
        assertEquals("md:$sha:$byteCount", locator.fingerprintKey)
        assertEquals(text.indexOf("needle"), locator.charOffsetUTF16)
    }

    // ── out-of-range / corrupt inputs are rejected (→ null, never a clamped bogus jump) ──

    @Test
    fun negativeOffset_isRejected() {
        // A corrupt occurrence with a negative raw offset → null (structurally invalid).
        val text = "body text\n"
        val occ = RawOccurrence(startUtf16 = -5, endUtf16 = -1, occurrenceIndex = 0)
        assertNull("negative offset rejected", resolver(text).resolve(0, occ))
    }

    @Test
    fun negativeSectionIndex_isRejected() {
        // offsetForChunk CLAMPS -1 to chunk 0 — the resolver must reject it BEFORE that clamp, not
        // silently resolve against the first chunk.
        val text = "first line\nsecond line\n"
        val occ = RawOccurrence(startUtf16 = 0, endUtf16 = 4, occurrenceIndex = 0)
        assertNull("negative sectionIndex rejected", resolver(text).resolve(-1, occ))
    }

    @Test
    fun sectionIndexPastChunkCount_isRejected() {
        // offsetForChunk CLAMPS an oversized index to the LAST chunk — the resolver must reject it.
        val text = "first line\nsecond line\n"
        val doc = TxtDocument.of(text)
        val occ = RawOccurrence(startUtf16 = 0, endUtf16 = 4, occurrenceIndex = 0)
        assertNull("out-of-range sectionIndex rejected", resolver(text).resolve(doc.chunkCount, occ))
    }

    @Test
    fun occurrenceEndPastChunkLength_isRejected() {
        // An end offset past the chunk's own text length would map OUTSIDE the chunk, breaking the
        // chunkForOffset round-trip — validatedOrNull alone would NOT catch it (it only checks
        // non-negativity + ordering), so the resolver bounds-checks the span against the chunk length.
        val text = "first line\nsecond line\n"
        val sectionIndex = 0
        val chunkLength = TxtDocument.of(text).textForChunk(sectionIndex).length
        val occ = RawOccurrence(startUtf16 = 0, endUtf16 = chunkLength + 5, occurrenceIndex = 0)
        assertNull("span past chunk length rejected", resolver(text).resolve(sectionIndex, occ))
    }

    @Test
    fun invertedSpan_isRejected() {
        // end < start is a corrupt span → null.
        val text = "the quick brown fox\n"
        val occ = RawOccurrence(startUtf16 = 9, endUtf16 = 4, occurrenceIndex = 0)
        assertNull("inverted span rejected", resolver(text).resolve(0, occ))
    }
}
