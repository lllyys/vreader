package com.vreader.app.diagnostics

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/**
 * Feature #164 WI-3 — [CompositeDiagnosticsSource].
 *
 * Two contracts carry the whole design and are asserted in BOTH directions:
 *
 *  1. **Merge, don't choose.** Whenever the primary (logcat) is `Available` — INCLUDING
 *     `Available(emptyList())` — the ring's entries are merged in, never hidden. The rejected v1
 *     "primary else floor" design failed exactly here: a sparse-but-readable logcat suppressed the
 *     ring entirely.
 *  2. **Dedupe on identity, never on text.** The key is the VLog sequence id. Deduping on
 *     `(time, tag, message)` would collapse two genuinely distinct events that happen to share
 *     byte-identical text and timestamp — a realistic shape for a repeated handled condition in a
 *     tight loop. Both halves are asserted: the twin appears once, the look-alikes both survive.
 */
class CompositeDiagnosticsSourceTest {

    private fun entry(
        time: Long,
        message: String,
        sequenceId: Long? = null,
        category: String = "Reader",
        level: DiagnosticsLevel = DiagnosticsLevel.WARN,
    ) = DiagnosticsLogEntry(time, level, category, message, sequenceId)

    private class FakeSource(
        private val result: SourceResult = SourceResult.Available(emptyList()),
        private val error: Throwable? = null,
    ) : DiagnosticsLogSource {
        var calls = 0
        var lastSince: Long? = null
        var lastLimit: Int = Int.MIN_VALUE

        override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult {
            calls++
            lastSince = sinceMillis
            lastLimit = limit
            error?.let { throw it }
            return result
        }
    }

    private fun available(vararg entries: DiagnosticsLogEntry) = SourceResult.Available(entries.toList())

    private suspend fun merge(
        primary: DiagnosticsLogSource,
        secondary: DiagnosticsLogSource,
        sinceMillis: Long? = null,
        limit: Int = 1_000,
    ): SourceResult = CompositeDiagnosticsSource(primary, secondary).recentEntries(sinceMillis, limit)

    private fun SourceResult.entries(): List<DiagnosticsLogEntry> {
        assertTrue("expected Available, got $this", this is SourceResult.Available)
        return (this as SourceResult.Available).entries
    }

    // ---------------------------------------------------------------- merge semantics

    @Test
    fun mergesBothSourcesWhenThePrimaryIsAvailable() = runTest {
        val logcat = FakeSource(available(entry(200, "from logcat")))
        val ring = FakeSource(available(entry(100, "from ring", sequenceId = 1L)))

        assertEquals(
            listOf("from ring", "from logcat"),
            merge(logcat, ring).entries().map { it.message },
        )
    }

    /** The v1-design regression: a readable-but-empty logcat must NOT hide the ring. */
    @Test
    fun anEmptyButAvailablePrimaryStillYieldsTheRingEntries() = runTest {
        val logcat = FakeSource(SourceResult.Available(emptyList()))
        val ring = FakeSource(available(entry(100, "breadcrumb", sequenceId = 1L)))

        assertEquals(listOf("breadcrumb"), merge(logcat, ring).entries().map { it.message })
    }

    /** The other half of the same regression: a SPARSE logcat must not hide the ring either. */
    @Test
    fun aPartiallyPopulatedPrimaryDoesNotHideRingEntries() = runTest {
        val logcat = FakeSource(available(entry(50, "framework line")))
        val ring = FakeSource(
            available(entry(60, "ours a", sequenceId = 1L), entry(70, "ours b", sequenceId = 2L)),
        )

        assertEquals(
            listOf("framework line", "ours a", "ours b"),
            merge(logcat, ring).entries().map { it.message },
        )
    }

    @Test
    fun returnsOnlySecondaryWhenThePrimaryIsUnavailable() = runTest {
        val logcat = FakeSource(SourceResult.Unavailable("exec denied"))
        val ring = FakeSource(available(entry(100, "floor", sequenceId = 1L)))

        assertEquals(listOf("floor"), merge(logcat, ring).entries().map { it.message })
    }

    @Test
    fun returnsOnlyPrimaryWhenTheSecondaryIsUnavailable() = runTest {
        val logcat = FakeSource(available(entry(100, "platform")))
        val ring = FakeSource(SourceResult.Unavailable("no sink"))

        assertEquals(listOf("platform"), merge(logcat, ring).entries().map { it.message })
    }

    @Test
    fun bothUnavailableReportsUnavailableCitingBothReasons() = runTest {
        val result = merge(
            FakeSource(SourceResult.Unavailable("logcat: denied")),
            FakeSource(SourceResult.Unavailable("ring: absent")),
        )

        assertTrue("expected Unavailable, got $result", result is SourceResult.Unavailable)
        val reason = (result as SourceResult.Unavailable).reason
        assertTrue(reason, reason.contains("logcat: denied"))
        assertTrue(reason, reason.contains("ring: absent"))
    }

    // ---------------------------------------------------------------- dedupe (identity, not text)

    @Test
    fun anEventPresentInBothSourcesAppearsExactlyOnce() = runTest {
        val twinTime = 1_000L
        val logcat = FakeSource(available(entry(twinTime, "[PdfDocument] corrupt", sequenceId = 42L)))
        val ring = FakeSource(available(entry(twinTime, "[PdfDocument] corrupt", sequenceId = 42L)))

        val merged = merge(logcat, ring).entries()
        assertEquals(1, merged.size)
        assertEquals(42L, merged.single().sequenceId)
    }

    /**
     * The assertion that a `(time, tag, message)` dedupe cannot pass. Two distinct events, same
     * text, same timestamp, different ids — both must survive.
     */
    @Test
    fun twoDistinctEntriesWithByteIdenticalTextAndTimestampBothSurvive() = runTest {
        val t = 5_000L
        val text = "[SearchIndexCoordinator] terminal-state write failed; skipping"
        val logcat = FakeSource(available(entry(t, text, sequenceId = 7L), entry(t, text, sequenceId = 8L)))
        val ring = FakeSource(SourceResult.Available(emptyList()))

        val merged = merge(logcat, ring).entries()
        assertEquals(2, merged.size)
        assertEquals(listOf(7L, 8L), merged.mapNotNull { it.sequenceId })
    }

    @Test
    fun entriesWithoutASequenceIdAreNeverCollapsedEvenWhenIdentical() = runTest {
        val t = 900L
        val logcat = FakeSource(available(entry(t, "chromium said no"), entry(t, "chromium said no")))
        val ring = FakeSource(available(entry(t, "chromium said no")))

        assertEquals(3, merge(logcat, ring).entries().size)
    }

    /**
     * logd truncates an over-long payload at 4068 bytes; the ring holds the entry intact. When the
     * same id arrives from both, the RING copy wins — deduping to the truncated twin would lose
     * exactly the tail of a stack trace, which is the part worth having.
     */
    @Test
    fun theRingCopyWinsACollisionSoTruncationIsNotInherited() = runTest {
        val full = "[FoliateBridge] " + "z".repeat(5_000)
        val logcat = FakeSource(available(entry(10L, full.take(4_068), sequenceId = 3L)))
        val ring = FakeSource(available(entry(10L, full, sequenceId = 3L)))

        assertEquals(full, merge(logcat, ring).entries().single().message)
    }

    @Test
    fun aRingEntryWhoseLogcatTwinWasDroppedStillSurfaces() = runTest {
        val logcat = FakeSource(available(entry(10L, "kept", sequenceId = 1L)))
        val ring = FakeSource(available(entry(10L, "kept", sequenceId = 1L), entry(20L, "dropped by logd", sequenceId = 2L)))

        assertEquals(listOf("kept", "dropped by logd"), merge(logcat, ring).entries().map { it.message })
    }

    // ---------------------------------------------------------------- ordering + limits

    @Test
    fun mergedOutputIsOrderedOldestToNewestAcrossSources() = runTest {
        val logcat = FakeSource(available(entry(30, "c"), entry(10, "a")))
        val ring = FakeSource(available(entry(20, "b", sequenceId = 1L), entry(40, "d", sequenceId = 2L)))

        assertEquals(listOf("a", "b", "c", "d"), merge(logcat, ring).entries().map { it.message })
    }

    @Test
    fun limitClampsTheMergedResultToTheMostRecentEntries() = runTest {
        val logcat = FakeSource(available(entry(10, "a"), entry(30, "c")))
        val ring = FakeSource(available(entry(20, "b", sequenceId = 1L), entry(40, "d", sequenceId = 2L)))

        assertEquals(listOf("c", "d"), merge(logcat, ring, limit = 2).entries().map { it.message })
    }

    @Test
    fun zeroAndNegativeLimitYieldEmptyWithoutThrowing() = runTest {
        val logcat = FakeSource(available(entry(10, "a")))
        val ring = FakeSource(available(entry(20, "b", sequenceId = 1L)))

        assertEquals(emptyList<DiagnosticsLogEntry>(), merge(logcat, ring, limit = 0).entries())
        assertEquals(emptyList<DiagnosticsLogEntry>(), merge(logcat, ring, limit = -3).entries())
    }

    @Test
    fun sinceMillisAndLimitAreForwardedToBothSources() = runTest {
        val logcat = FakeSource(available())
        val ring = FakeSource(available())

        merge(logcat, ring, sinceMillis = 12_345L, limit = 77)

        assertEquals(1, logcat.calls)
        assertEquals(1, ring.calls)
        assertEquals(12_345L, logcat.lastSince)
        assertEquals(12_345L, ring.lastSince)
        assertEquals(77, logcat.lastLimit)
        assertEquals(77, ring.lastLimit)
    }

    // ---------------------------------------------------------------- failure containment

    @Test
    fun aThrowingPrimaryIsTreatedAsUnavailableAndNeverPropagates() = runTest {
        val logcat = FakeSource(error = IOException("logcat exploded"))
        val ring = FakeSource(available(entry(10L, "floor", sequenceId = 1L)))

        assertEquals(listOf("floor"), merge(logcat, ring).entries().map { it.message })
    }

    @Test
    fun aThrowingSecondaryIsTreatedAsUnavailableAndNeverPropagates() = runTest {
        val logcat = FakeSource(available(entry(10L, "platform")))
        val ring = FakeSource(error = IllegalStateException("ring exploded"))

        assertEquals(listOf("platform"), merge(logcat, ring).entries().map { it.message })
    }

    @Test
    fun bothThrowingReportsUnavailableRatherThanCrashing() = runTest {
        val result = merge(
            FakeSource(error = IOException("a")),
            FakeSource(error = IOException("b")),
        )
        assertTrue("expected Unavailable, got $result", result is SourceResult.Unavailable)
    }

    /**
     * Cancellation is NOT a source failure: swallowing it would break structured concurrency and
     * leave a cancelled viewer load looking like a successful empty read.
     */
    @Test
    fun cancellationStillPropagates() = runTest {
        val logcat = FakeSource(error = CancellationException("viewer closed"))
        val ring = FakeSource(available(entry(10L, "floor", sequenceId = 1L)))

        try {
            merge(logcat, ring)
            throw AssertionError("CancellationException must propagate")
        } catch (expected: CancellationException) {
            assertEquals("viewer closed", expected.message)
        }
    }
}
