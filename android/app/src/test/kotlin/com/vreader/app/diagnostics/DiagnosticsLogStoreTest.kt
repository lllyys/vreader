package com.vreader.app.diagnostics

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

/**
 * Feature #164 WI-4 — [DiagnosticsLogStore].
 *
 * Three contracts carry this WI, and each is asserted so that the *obvious wrong implementation*
 * fails rather than passes:
 *
 *  1. **`Available(emptyList())` and `Unavailable` are DIFFERENT.** `lastLoadDegraded` is pinned in
 *     all four states (before any load, after an empty-but-healthy load, after an unavailable load,
 *     and after a recovery) — the "empty but healthy" case is the one the design's empty-state copy
 *     depends on, and a store that conflated the two would still satisfy a single-state test.
 *  2. **`categories()` is the RAW set, `DiagnosticsCategoryBounding.chips()` is the CHIP set.** The
 *     fixture is built so the two differ in SIZE *and* in MEMBERS, so an implementation that
 *     returned chips from `categories()` cannot pass both. (Gate-2 round-3 raised a High on exactly
 *     this conflation.)
 *  3. **Redaction is two-sided.** "the secret is absent" alone is satisfied by a store that drops
 *     the message entirely, so every redaction assertion also proves the surrounding diagnostic
 *     context — and the entry's timestamp/level/category — survived. Secrets are placed in MORE
 *     than one entry so a redactor applied to only the first (or only the last) is caught.
 *
 * On the deliberate overlap with `DiagnosticsCategoryBoundingTest` (WI-3, in `VLogTest.kt`): that
 * suite proves the bounding rule in isolation. WI-4's acceptance criterion 6 is about the
 * INTERACTION — that capping the chip row never makes a collapsed entry unreachable, measured on
 * the same fixture whose raw set this store reports. The two are not substitutes, and asserting
 * criterion 6 only in a collaborator's suite would leave WI-4's own contract unowned.
 */
class DiagnosticsLogStoreTest {

    // ---------------------------------------------------------------- fixtures

    /**
     * Deliberately IGNORES `limit` and returns its whole canned list. A fake that honoured the limit
     * would let a broken clamp pass unnoticed: the store's own bound is what these tests measure,
     * and [lastLimit] records what the store actually asked for.
     */
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

    /**
     * A source whose behaviour changes between loads, for multi-load sequences. Each step either
     * yields a [SourceResult] or throws, so one STORE can be driven through
     * degraded -> recovered -> cancelled without swapping instances.
     */
    private class ScriptedSource(private val steps: MutableList<Any>) : DiagnosticsLogSource {
        override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult =
            when (val step = steps.removeAt(0)) {
                is Throwable -> throw step
                else -> step as SourceResult
            }
    }

    /**
     * Each call takes the next (gate, result) pair and SUSPENDS on its gate, so two loads can be
     * genuinely in flight at once and released in an arbitrary completion order.
     */
    private class GatedSource(
        private val steps: List<Pair<CompletableDeferred<Unit>, SourceResult>>,
    ) : DiagnosticsLogSource {
        private val next = AtomicInteger(0)
        private val started = AtomicInteger(0)

        /** How many calls have entered and are waiting on (or past) their gate. */
        val inFlight: Int get() = started.get()

        override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult {
            val (gate, result) = steps[next.getAndIncrement()]
            started.incrementAndGet()
            gate.await()
            return result
        }
    }

    private fun entry(
        time: Long = 1_000L,
        message: String = "message",
        category: String = "Reader",
        level: DiagnosticsLevel = DiagnosticsLevel.WARN,
        sequenceId: Long? = null,
    ) = DiagnosticsLogEntry(time, level, category, message, sequenceId)

    private fun available(vararg entries: DiagnosticsLogEntry) = SourceResult.Available(entries.toList())

    private fun store(
        result: SourceResult = SourceResult.Available(emptyList()),
        maxEntries: Int = 2_000,
    ) = DiagnosticsLogStore(FakeSource(result), maxEntries)

    /** Lines emitted for an entry start at column 0 with an ISO-8601 UTC instant. */
    private val entryLine = Regex("""^\d{4}-\d{2}-\d{2}T[0-9:.]+Z \[[A-Z]+\]""")

    private fun bodyLines(export: String) =
        export.split("\n").drop(DiagnosticsLogStore.HEADER_LINE_COUNT)

    // ================================================================ load + availability

    @Test
    fun loadReturnsEmptyWithoutThrowingWhenTheSourceIsUnavailable() = runTest {
        val subject = store(SourceResult.Unavailable("logcat: exec denied; ring: absent"))

        assertEquals(emptyList<DiagnosticsLogEntry>(), subject.load())
    }

    @Test
    fun loadReturnsTheSourceEntriesInOrderWhenAvailable() = runTest {
        val subject = store(available(entry(10, "a"), entry(20, "b"), entry(30, "c")))

        assertEquals(listOf("a", "b", "c"), subject.load().map { it.message })
    }

    @Test
    fun lastLoadDegradedIsFalseBeforeAnyLoad() {
        assertFalse(store().lastLoadDegraded)
    }

    /**
     * The load-bearing case: an empty log from a HEALTHY source is not degraded. If this collapsed
     * into "degraded", the export would claim capture is broken every time the user opens a quiet
     * session, and the design's empty-state copy would be second-guessed for no reason.
     */
    @Test
    fun lastLoadDegradedIsFalseAfterAnAvailableButEmptyLoad() = runTest {
        val subject = store(SourceResult.Available(emptyList()))

        assertEquals(emptyList<DiagnosticsLogEntry>(), subject.load())
        assertFalse(subject.lastLoadDegraded)
    }

    @Test
    fun lastLoadDegradedIsTrueAfterAnUnavailableLoad() = runTest {
        val subject = store(SourceResult.Unavailable("capture dead"))

        subject.load()

        assertTrue(subject.lastLoadDegraded)
    }

    @Test
    fun lastLoadDegradedResetsWhenALaterLoadSucceeds() = runTest {
        val subject = DiagnosticsLogStore(
            ScriptedSource(
                mutableListOf<Any>(
                    SourceResult.Unavailable("capture dead"),
                    available(entry(10, "recovered")),
                ),
            ),
        )

        subject.load()
        assertTrue("first load must be degraded", subject.lastLoadDegraded)

        assertEquals(listOf("recovered"), subject.load().map { it.message })
        assertFalse("a successful load must clear the degraded flag", subject.lastLoadDegraded)
    }

    @Test
    fun aThrowingSourceIsContainedAsAnUnavailableDegradedLoad() = runTest {
        val throwing = DiagnosticsLogStore(FakeSource(error = IllegalStateException("reader blew up")))

        assertEquals(emptyList<DiagnosticsLogEntry>(), throwing.load())
        assertTrue(throwing.lastLoadDegraded)
    }

    /**
     * Cancellation is not a source failure: it must propagate (structured concurrency) and must NOT
     * fabricate an availability verdict. Driven through ONE store — a degraded load, then a
     * cancelled one — so an implementation that cleared its own flag before rethrowing is caught.
     * Asserting against a second, untouched store would be tautological.
     */
    @Test
    fun cancellationPropagatesAndLeavesTheDegradedFlagUntouched() = runTest {
        val subject = DiagnosticsLogStore(
            ScriptedSource(
                mutableListOf<Any>(
                    SourceResult.Unavailable("capture dead"),
                    CancellationException("viewer closed"),
                ),
            ),
        )
        subject.load()
        assertTrue(subject.lastLoadDegraded)

        try {
            subject.load()
            throw AssertionError("CancellationException must propagate")
        } catch (expected: CancellationException) {
            assertEquals("viewer closed", expected.message)
        }
        assertTrue("a cancelled load must not rewrite the recorded verdict", subject.lastLoadDegraded)
    }

    /**
     * The mirror image: a cancelled load must not invent a DEGRADED verdict either, so a store that
     * was healthy stays healthy.
     */
    @Test
    fun cancellationDoesNotFabricateADegradedVerdict() = runTest {
        val subject = DiagnosticsLogStore(
            ScriptedSource(
                mutableListOf<Any>(
                    available(entry(10, "healthy")),
                    CancellationException("viewer closed"),
                ),
            ),
        )
        subject.load()
        assertFalse(subject.lastLoadDegraded)

        try {
            subject.load()
            throw AssertionError("CancellationException must propagate")
        } catch (expected: CancellationException) {
            assertEquals("viewer closed", expected.message)
        }
        assertFalse(subject.lastLoadDegraded)
    }

    /**
     * An `Error` is NOT a source failure and must not be laundered into a degraded load — the
     * containment is `catch (Exception)`, deliberately not `catch (Throwable)`.
     */
    @Test
    fun anErrorFromTheSourcePropagatesRatherThanBecomingADegradedLoad() = runTest {
        val subject = DiagnosticsLogStore(FakeSource(error = StackOverflowError("fatal")))

        try {
            subject.load()
            throw AssertionError("an Error must propagate")
        } catch (expected: StackOverflowError) {
            assertEquals("fatal", expected.message)
        }
        assertFalse("an Error must not be recorded as a degraded capture", subject.lastLoadDegraded)
    }

    /**
     * [DiagnosticsLogStore.lastLoadDegraded] is a store-wide latch, not a property of one returned
     * batch: genuinely OVERLAPPING loads resolve LAST-TO-COMPLETE-WINS. WI-5 serialises loads, which
     * is the precondition the store documents; pinning the behaviour here keeps it specified rather
     * than accidental, so a future single-flight guard is a deliberate, test-breaking change.
     *
     * This test and its pair below use the SAME start order and the SAME two verdicts, and differ
     * only in RELEASE order — which is what makes them discriminating. Here the loads complete in
     * start order, so the healthy one lands last and the latch ends clean; an implementation where
     * the FIRST-STARTED load owned the latch would report degraded and fail.
     */
    @Test
    fun overlappingLoadsLetTheLastToCompleteOwnTheLatchWhenItIsTheHealthyOne() = runTest {
        val firstStarted = CompletableDeferred<Unit>()
        val secondStarted = CompletableDeferred<Unit>()
        val source = GatedSource(
            listOf(
                firstStarted to SourceResult.Unavailable("capture dead"),
                secondStarted to available(entry(10, "healthy")),
            ),
        )
        val subject = DiagnosticsLogStore(source)

        val first = async { subject.load() }
        val second = async { subject.load() }
        testScheduler.runCurrent()
        assertEquals("both loads must be in flight before either resolves", 2, source.inFlight)

        firstStarted.complete(Unit)
        testScheduler.runCurrent()
        secondStarted.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(emptyList<DiagnosticsLogEntry>(), first.await())
        assertEquals(listOf("healthy"), second.await().map { it.message })
        assertFalse("the load that completed LAST owns the latch", subject.lastLoadDegraded)
    }

    /**
     * The discriminating pair: identical start order and verdicts, released in REVERSE, so the
     * degraded load now completes last and must own the latch. An implementation where the
     * LAST-STARTED load owned it would report healthy and fail.
     */
    @Test
    fun overlappingLoadsLetTheLastToCompleteOwnTheLatchWhenItIsTheDegradedOne() = runTest {
        val firstStarted = CompletableDeferred<Unit>()
        val secondStarted = CompletableDeferred<Unit>()
        val source = GatedSource(
            listOf(
                firstStarted to SourceResult.Unavailable("capture dead"),
                secondStarted to available(entry(10, "healthy")),
            ),
        )
        val subject = DiagnosticsLogStore(source)

        val first = async { subject.load() }
        val second = async { subject.load() }
        testScheduler.runCurrent()
        assertEquals("both loads must be in flight before either resolves", 2, source.inFlight)

        secondStarted.complete(Unit)
        testScheduler.runCurrent()
        firstStarted.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(emptyList<DiagnosticsLogEntry>(), first.await())
        assertEquals(listOf("healthy"), second.await().map { it.message })
        assertTrue("the load that completed LAST owns the latch", subject.lastLoadDegraded)
    }

    // ================================================================ bounds + clamping

    @Test
    fun loadTrimsToTheMostRecentMaxEntries() = runTest {
        val many = (1..10).map { entry(it.toLong(), "e$it") }
        val subject = store(SourceResult.Available(many), maxEntries = 3)

        assertEquals(listOf("e8", "e9", "e10"), subject.load().map { it.message })
    }

    @Test
    fun loadWithoutALimitAsksTheSourceForMaxEntries() = runTest {
        val source = FakeSource(available(entry()))
        DiagnosticsLogStore(source, maxEntries = 250).load()

        assertEquals(250, source.lastLimit)
    }

    @Test
    fun aLimitAboveMaxEntriesIsClampedDownToMaxEntries() = runTest {
        val source = FakeSource(SourceResult.Available((1..9).map { entry(it.toLong(), "e$it") }))
        val subject = DiagnosticsLogStore(source, maxEntries = 4)

        assertEquals(listOf("e6", "e7", "e8", "e9"), subject.load(limit = 5_000).map { it.message })
        assertEquals(4, source.lastLimit)
    }

    @Test
    fun aLimitBelowMaxEntriesBoundsTheResultToTheMostRecentEntries() = runTest {
        val source = FakeSource(SourceResult.Available((1..9).map { entry(it.toLong(), "e$it") }))
        val subject = DiagnosticsLogStore(source, maxEntries = 100)

        assertEquals(listOf("e8", "e9"), subject.load(limit = 2).map { it.message })
        assertEquals(2, source.lastLimit)
    }

    /**
     * The ported iOS Gate-4 finding. A negative limit must clamp to 0 — both in what the store
     * RETURNS and in what it ASKS the source for. Without the `max(0, …)` half of the clamp, a
     * negative cap reaches the source (and `takeLast`), which is exactly the crash iOS fixed.
     */
    @Test
    fun aNegativeLimitYieldsEmptyAndForwardsZeroWithoutThrowing() = runTest {
        val source = FakeSource(available(entry(10, "a"), entry(20, "b")))
        val subject = DiagnosticsLogStore(source, maxEntries = 50)

        assertEquals(emptyList<DiagnosticsLogEntry>(), subject.load(limit = -7))
        assertEquals("the clamp must floor at zero, not pass a negative cap on", 0, source.lastLimit)
    }

    @Test
    fun aZeroLimitYieldsEmpty() = runTest {
        val subject = store(available(entry(10, "a")))

        assertEquals(emptyList<DiagnosticsLogEntry>(), subject.load(limit = 0))
    }

    @Test
    fun aNonPositiveMaxEntriesIsCoercedToAtLeastOne() = runTest {
        val zero = store(available(entry(10, "a"), entry(20, "b")), maxEntries = 0)
        val negative = store(available(entry(10, "a"), entry(20, "b")), maxEntries = -50)

        assertEquals(listOf("b"), zero.load().map { it.message })
        assertEquals(listOf("b"), negative.load().map { it.message })
    }

    @Test
    fun aLimitExactlyEqualToMaxEntriesIsHonouredWithoutClamping() = runTest {
        val source = FakeSource(SourceResult.Available((1..6).map { entry(it.toLong(), "e$it") }))
        val subject = DiagnosticsLogStore(source, maxEntries = 4)

        assertEquals(listOf("e3", "e4", "e5", "e6"), subject.load(limit = 4).map { it.message })
        assertEquals(4, source.lastLimit)
    }

    /** The integer extremes of the clamp — both ends saturate rather than overflow or throw. */
    @Test
    fun integerExtremeLimitsSaturateAtTheClampBoundaries() = runTest {
        val low = FakeSource(available(entry(10, "a"), entry(20, "b")))
        val high = FakeSource(available(entry(10, "a"), entry(20, "b")))

        assertEquals(emptyList<DiagnosticsLogEntry>(), DiagnosticsLogStore(low, 50).load(limit = Int.MIN_VALUE))
        assertEquals(0, low.lastLimit)

        assertEquals(
            listOf("a", "b"),
            DiagnosticsLogStore(high, 50).load(limit = Int.MAX_VALUE).map { it.message },
        )
        assertEquals(50, high.lastLimit)
    }

    @Test
    fun sinceMillisIsForwardedToTheSourceUnchanged() = runTest {
        val source = FakeSource(available())
        DiagnosticsLogStore(source).load(sinceMillis = 12_345L)

        assertEquals(1, source.calls)
        assertEquals(12_345L, source.lastSince)
    }

    @Test
    fun aNullSinceMillisIsForwardedAsNull() = runTest {
        val source = FakeSource(available())
        DiagnosticsLogStore(source).load()

        assertEquals(null, source.lastSince)
    }

    // ================================================================ categories: RAW, not chips

    /**
     * The fixture that makes criterion 5 and criterion 6 provably different. Seven distinct raw
     * tags collapse onto three chips, so the raw set and the chip set differ in size (7 vs 4) and
     * in membership (`All`/`Other` are chips only; `chromium`/`ziparchive`/`ART` are raw only).
     */
    private fun rawVsChipFixture() = listOf(
        entry(1, category = "Reader"),
        entry(2, category = "chromium"),
        entry(3, category = "SQLiteLog"),
        entry(4, category = "ziparchive"),
        entry(5, category = "ART"),
        entry(6, category = "BestClock"),
        entry(7, category = "libc"),
        entry(8, category = ""),
    )

    @Test
    fun categoriesReturnsTheRawDistinctNonEmptyTagsSorted() {
        val categories = store().categories(rawVsChipFixture())

        assertEquals(
            listOf("ART", "BestClock", "Reader", "SQLiteLog", "chromium", "libc", "ziparchive"),
            categories,
        )
    }

    @Test
    fun categoriesIsNotTheChipSet() {
        val fixture = rawVsChipFixture()
        val categories = store().categories(fixture)
        val chips = DiagnosticsCategoryBounding.chips(fixture)

        assertNotEquals(chips, categories)
        assertEquals("raw set size", 7, categories.size)
        assertEquals("chip set size", 4, chips.size)
        assertTrue("a raw framework tag belongs to the raw set", categories.contains("chromium"))
        assertFalse("a raw framework tag is never a chip", chips.contains("chromium"))
        assertFalse("`All` is a filter constant, never a raw category", categories.contains(DiagnosticsCategoryBounding.ALL))
        assertFalse(
            "the collapse bucket is a chip, never a raw category",
            categories.contains(DiagnosticsCategoryBounding.COLLAPSED_BUCKET),
        )
    }

    @Test
    fun categoriesDeduplicatesRepeatedTagsAndDropsEmptyOnes() {
        val categories = store().categories(
            listOf(
                entry(1, category = "Reader"),
                entry(2, category = "Reader"),
                entry(3, category = ""),
                entry(4, category = "Library"),
            ),
        )

        assertEquals(listOf("Library", "Reader"), categories)
    }

    /**
     * The contract is NON-EMPTY, not non-blank — pinned so `isNotBlank()` is a deliberate,
     * test-breaking change rather than a silent one. Unreachable in production (`LogcatLineParser`
     * trims the tag column, so a whitespace-only tag arrives as `""`), which is exactly why it
     * needs pinning: nothing else would notice the difference.
     */
    @Test
    fun aWhitespaceOnlyCategoryIsNonEmptyAndSurvivesAsARawCategory() {
        val categories = store().categories(listOf(entry(1, category = "   "), entry(2, category = "")))

        assertEquals(listOf("   "), categories)
    }

    @Test
    fun categoriesOfAnEmptyListIsEmpty() {
        assertEquals(emptyList<String>(), store().categories(emptyList()))
    }

    /**
     * The size contrast at production scale: 46 distinct raw tags, 8 chips. Deliberately asserted
     * HERE (a criterion-5 test) and not inside the chip-bounding test, so that a store returning
     * chips from `categories()` fails only the raw-set tests and leaves the bounding tests green —
     * which is what makes the two criteria independently diagnostic.
     */
    @Test
    fun theRawSetIsUnboundedWhereTheChipSetIsCapped() {
        val fixture = manyRawTagFixture()

        assertEquals(46, store().categories(fixture).size)
        assertEquals(8, DiagnosticsCategoryBounding.chips(fixture).size)
    }

    // ================================================================ chip bounding (criterion 6)

    /** 40 unknown library tags + one entry per designed category, with distinct counts for ranking. */
    private fun manyRawTagFixture(): List<DiagnosticsLogEntry> {
        val unknown = (0 until 40).map {
            entry(it.toLong(), category = "lib-tag-" + it.toString().padStart(2, '0'))
        }
        val designed = listOf(
            DiagnosticsCategory.LIBRARY to 6,
            DiagnosticsCategory.PERSISTENCE to 5,
            DiagnosticsCategory.READER to 4,
            DiagnosticsCategory.AI to 3,
            DiagnosticsCategory.SYNC to 2,
            DiagnosticsCategory.DEBUG_BRIDGE to 1,
        ).flatMap { (category, count) ->
            (0 until count).map { entry(100L + it, category = category.tag) }
        }
        return unknown + designed
    }

    @Test
    fun fortyDistinctRawTagsStillYieldABoundedChipRowRankedByCount() {
        val fixture = manyRawTagFixture()

        val chips = DiagnosticsCategoryBounding.chips(fixture)

        assertEquals("`All` always leads the row", DiagnosticsCategoryBounding.ALL, chips.first())
        assertTrue(
            "chip row must stay capped at the designed maximum, got ${chips.size - 1}",
            chips.size - 1 <= DiagnosticsCategoryBounding.MAX_CATEGORY_CHIPS,
        )
        assertEquals(
            listOf("All", "Other", "Library", "Persistence", "Reader", "AI", "Sync", "DebugBridge"),
            chips,
        )
        assertFalse("no raw library tag reaches the chip row", chips.contains("lib-tag-07"))
    }

    /**
     * The other half of the bounding contract: capping the CHIPS must never make data unreachable.
     * An entry whose raw tag collapsed into the bucket is still selected by filtering on the bucket.
     */
    @Test
    fun anEntryWhoseRawTagCollapsedIsStillReachableThroughTheBucketFilter() {
        val fixture = manyRawTagFixture()

        val inBucket = fixture.filter {
            DiagnosticsCategoryBounding.chipFor(it.category) == DiagnosticsCategoryBounding.COLLAPSED_BUCKET
        }

        assertEquals("every unknown tag collapses into the one bucket", 40, inBucket.size)
        assertTrue(
            "a collapsed entry must remain reachable through its bucket",
            inBucket.any { it.category == "lib-tag-07" },
        )
    }

    // ================================================================ export: redaction

    private fun secretBearingEntries() = listOf(
        DiagnosticsLogEntry(
            1_754_000_000_000L,
            DiagnosticsLevel.ERROR,
            "Sync",
            "[WebDavClient] PROPFIND failed; Authorization: Basic dXNlcjpwYXNzd29yZA== -> HTTP 401",
        ),
        DiagnosticsLogEntry(
            1_754_000_001_000L,
            DiagnosticsLevel.WARN,
            "AI",
            "[AiClient] provider rejected apiKey=sk-proj-ABCDEF1234567890 status=502",
        ),
        DiagnosticsLogEntry(
            1_754_000_002_000L,
            DiagnosticsLevel.INFO,
            "Library",
            "[BackupService] upload denied password=hunter2super",
        ),
    )

    /**
     * Two-sided, and across EVERY entry. "the secret is gone" alone would also be satisfied by a
     * store that dropped the message, so the surrounding context and the entry's non-message fields
     * are asserted present. Three entries means a redactor wired to only the first — or only the
     * last — is caught.
     */
    @Test
    fun exportTextRedactsEveryEntryAndKeepsTheSurroundingContext() {
        val export = store().exportText(secretBearingEntries(), generatedAt = 1_754_000_003_000L)

        for (secret in listOf("dXNlcjpwYXNzd29yZA==", "sk-proj-ABCDEF1234567890", "hunter2super")) {
            assertFalse("secret leaked into the export: $secret\n$export", export.contains(secret))
        }
        assertEquals(
            "every message must have been scrubbed",
            3,
            Regex(Regex.escape(DiagnosticsRedactor.PLACEHOLDER)).findAll(export).count(),
        )
        for (context in listOf(
            "[WebDavClient] PROPFIND failed",
            "HTTP 401",
            "[AiClient] provider rejected",
            "status=502",
            "[BackupService] upload denied",
        )) {
            assertTrue("diagnostic context was destroyed: $context\n$export", export.contains(context))
        }
        // Non-message fields survive intact.
        assertTrue(export.contains("2025-07-31T22:13:20Z [ERROR] (Sync)"))
        assertTrue(export.contains("[WARN] (AI)"))
        assertTrue(export.contains("[INFO] (Library)"))
    }

    @Test
    fun exportTextRedactsSecretsThatSitOnContinuationLines() {
        val entry = DiagnosticsLogEntry(
            1_754_000_000_000L,
            DiagnosticsLevel.ERROR,
            "Sync",
            "[WebDavClient] backup failed\n  at retry(attempt=2)\n  header Authorization: Bearer sk-live-ABCDEF1234567890",
        )

        val export = store().exportText(listOf(entry), generatedAt = 0L)

        assertFalse(export.contains("sk-live-ABCDEF1234567890"))
        assertTrue(export.contains("[WebDavClient] backup failed"))
        assertTrue(export.contains("at retry(attempt=2)"))
        assertTrue(export.contains(DiagnosticsRedactor.PLACEHOLDER))
    }

    // ================================================================ export: header

    @Test
    fun exportHeaderUsesTheSingularForExactlyOneEntry() {
        val header = store().exportText(listOf(entry()), generatedAt = 0L).lineSequence().first()

        assertTrue(header, header.contains("1 entry "))
        assertFalse(header, header.contains("entries"))
    }

    @Test
    fun exportHeaderUsesThePluralForZeroAndForMany() {
        val zero = store().exportText(emptyList(), generatedAt = 0L).lineSequence().first()
        val many = store().exportText(listOf(entry(), entry()), generatedAt = 0L).lineSequence().first()

        assertTrue(zero, zero.contains("0 entries"))
        assertTrue(many, many.contains("2 entries"))
    }

    @Test
    fun exportHeaderCarriesTheCaptureScopeLabel() {
        val header = store().exportText(listOf(entry()), generatedAt = 0L).lineSequence().first()

        assertTrue(header, header.contains(DiagnosticsLogStore.CAPTURE_SCOPE_LABEL))
    }

    /**
     * The label is the SINGLE source shared with the (WI-5) footer, and its wording is a deliberate
     * Android divergence: logd retains entries by uid ACROSS process launches, so iOS's
     * "this session" would understate the window and the design mock's "last 24 h" would overstate
     * a window we do not control. Pinned here so a change is a deliberate, test-breaking decision.
     */
    @Test
    fun captureScopeLabelIsTheDivergedAndroidWording() {
        assertEquals("recent activity", DiagnosticsLogStore.CAPTURE_SCOPE_LABEL)
    }

    @Test
    fun exportHeaderNamesTheGeneratedInstantInIso8601Utc() {
        val export = store().exportText(emptyList(), generatedAt = 1_754_000_000_000L)

        assertTrue(export, export.contains("generated: 2025-07-31T22:13:20Z"))
    }

    @Test
    fun exportCaptureSourceLineReportsTheFullStackAfterAHealthyLoad() = runTest {
        val subject = store(available(entry()))
        subject.load()

        val export = subject.exportText(emptyList(), generatedAt = 0L)

        assertTrue(export, export.contains("capture source: logcat + breadcrumbs"))
        assertFalse(export, export.contains("unavailable"))
    }

    @Test
    fun exportCaptureSourceLineReportsTheDegradedStackAfterAnUnavailableLoad() = runTest {
        val subject = store(SourceResult.Unavailable("logcat: exec denied; ring: absent"))
        subject.load()

        val export = subject.exportText(emptyList(), generatedAt = 0L)

        assertTrue(export, export.contains("capture source: breadcrumbs only (platform log unavailable)"))
    }

    /**
     * The header is asserted LITERALLY here — three exact lines — rather than through
     * `HEADER_LINE_COUNT`. An implementation that added a fourth header line and moved its own
     * constant would otherwise keep every body-slicing helper in this file green.
     */
    @Test
    fun exportOfAnEmptyListIsHeaderOnlyNeverAnEmptyString() {
        val export = store().exportText(emptyList(), generatedAt = 1_754_000_000_000L)

        assertTrue("header-only must not be empty", export.isNotEmpty())
        assertEquals(
            listOf(
                "vreader diagnostics — 0 entries (recent activity)",
                "generated: 2025-07-31T22:13:20Z",
                "capture source: logcat + breadcrumbs",
            ),
            export.split("\n"),
        )
        assertEquals(
            "the slicing helper must agree with the literal header",
            DiagnosticsLogStore.HEADER_LINE_COUNT,
            export.split("\n").size,
        )
        assertEquals(emptyList<String>(), bodyLines(export))
    }

    // ================================================================ export: entry lines

    @Test
    fun exportEmitsOneLinePerEntryInTheDesignedShape() {
        val entries = listOf(
            DiagnosticsLogEntry(1_754_000_000_000L, DiagnosticsLevel.ERROR, "Reader", "render failed"),
            DiagnosticsLogEntry(1_754_000_000_500L, DiagnosticsLevel.DEBUG, "Library", "import ok"),
        )

        val body = bodyLines(store().exportText(entries, generatedAt = 0L))

        assertEquals(
            listOf(
                "2025-07-31T22:13:20Z [ERROR] (Reader) render failed",
                "2025-07-31T22:13:20.500Z [DEBUG] (Library) import ok",
            ),
            body,
        )
    }

    @Test
    fun exportOmitsTheCategoryParenthesesForATagLessEntry() {
        val entries = listOf(DiagnosticsLogEntry(1_754_000_000_000L, DiagnosticsLevel.INFO, "", "no tag"))

        assertEquals(
            listOf("2025-07-31T22:13:20Z [INFO] no tag"),
            bodyLines(store().exportText(entries, generatedAt = 0L)),
        )
    }

    @Test
    fun exportOfAnEmptyMessageLeavesNoTrailingWhitespace() {
        val entries = listOf(DiagnosticsLogEntry(1_754_000_000_000L, DiagnosticsLevel.INFO, "Reader", ""))

        assertEquals(
            listOf("2025-07-31T22:13:20Z [INFO] (Reader)"),
            bodyLines(store().exportText(entries, generatedAt = 0L)),
        )
    }

    @Test
    fun exportKeepsAMultiLineMessageParseableWithIndentedContinuations() {
        val entries = listOf(
            DiagnosticsLogEntry(
                1_754_000_000_000L,
                DiagnosticsLevel.ERROR,
                "Reader",
                "java.lang.IllegalStateException: boom\n\tat com.vreader.app.Reader.open(Reader.kt:42)\n\tat com.vreader.app.Main.main(Main.kt:7)",
            ),
            DiagnosticsLogEntry(1_754_000_001_000L, DiagnosticsLevel.INFO, "Library", "next entry"),
        )

        val body = bodyLines(store().exportText(entries, generatedAt = 0L))

        // 3 message lines (the first shares the entry line) + the following entry.
        assertEquals("one line per message line", 4, body.size)
        assertEquals(
            "exactly one line per ENTRY starts at column 0",
            2,
            body.count { entryLine.containsMatchIn(it) },
        )
        val continuations = body.filterNot { entryLine.containsMatchIn(it) }
        assertEquals(2, continuations.size)
        continuations.forEach {
            assertTrue("continuation must be indented: '$it'", it.startsWith(DiagnosticsLogStore.CONTINUATION_INDENT))
        }
        assertTrue(body[1].contains("at com.vreader.app.Reader.open(Reader.kt:42)"))
    }

    /**
     * A message whose own text mimics an entry header must not be able to forge a second entry in
     * the exported payload — indenting every continuation line is what guarantees that.
     */
    @Test
    fun anEmbeddedLineThatMimicsAnEntryHeaderCannotForgeAnEntry() {
        val entries = listOf(
            DiagnosticsLogEntry(
                1_754_000_000_000L,
                DiagnosticsLevel.WARN,
                "Reader",
                "user pasted:\n2020-01-01T00:00:00Z [ERROR] (Sync) fabricated",
            ),
        )

        val body = bodyLines(store().exportText(entries, generatedAt = 0L))

        assertEquals(2, body.size)
        assertEquals(1, body.count { entryLine.containsMatchIn(it) })
        assertTrue(body[1].startsWith(DiagnosticsLogStore.CONTINUATION_INDENT))
        assertTrue(body[1].contains("2020-01-01T00:00:00Z [ERROR] (Sync) fabricated"))
    }

    @Test
    fun exportIndentsContinuationsForCrlfAndBareCrLineEndings() {
        val entries = listOf(
            DiagnosticsLogEntry(1_754_000_000_000L, DiagnosticsLevel.WARN, "Reader", "first\r\nsecond\rthird"),
        )

        val body = bodyLines(store().exportText(entries, generatedAt = 0L))

        assertEquals(3, body.size)
        assertEquals(
            listOf(
                "2025-07-31T22:13:20Z [WARN] (Reader) first",
                "${DiagnosticsLogStore.CONTINUATION_INDENT}second",
                "${DiagnosticsLogStore.CONTINUATION_INDENT}third",
            ),
            body,
        )
    }

    @Test
    fun exportPreservesCjkAndEmojiVerbatim() {
        val entries = listOf(
            DiagnosticsLogEntry(1_754_000_000_000L, DiagnosticsLevel.INFO, "阅读器", "打开《红楼梦》失败 📕"),
        )

        val body = bodyLines(store().exportText(entries, generatedAt = 0L))

        assertEquals(listOf("2025-07-31T22:13:20Z [INFO] (阅读器) 打开《红楼梦》失败 📕"), body)
    }

    /** Exact output at the epoch-millis extremes — "does not throw" alone would prove nothing. */
    @Test
    fun exportRendersExtremeTimestampsExactly() {
        val entries = listOf(
            DiagnosticsLogEntry(Long.MIN_VALUE, DiagnosticsLevel.VERBOSE, "Reader", "prehistoric"),
            DiagnosticsLogEntry(-1L, DiagnosticsLevel.VERBOSE, "Reader", "just before the epoch"),
            DiagnosticsLogEntry(0L, DiagnosticsLevel.VERBOSE, "Reader", "epoch"),
            DiagnosticsLogEntry(Long.MAX_VALUE, DiagnosticsLevel.VERBOSE, "Reader", "far future"),
        )

        val export = store().exportText(entries, generatedAt = Long.MAX_VALUE)

        assertEquals(
            listOf(
                "-292275055-05-16T16:47:04.192Z [VERBOSE] (Reader) prehistoric",
                "1969-12-31T23:59:59.999Z [VERBOSE] (Reader) just before the epoch",
                "1970-01-01T00:00:00Z [VERBOSE] (Reader) epoch",
                "+292278994-08-17T07:12:55.807Z [VERBOSE] (Reader) far future",
            ),
            bodyLines(export),
        )
        assertTrue(export, export.contains("generated: +292278994-08-17T07:12:55.807Z"))
    }

    /** RTL text is payload, not layout — it must round-trip byte-for-byte like CJK does. */
    @Test
    fun exportPreservesRtlTextVerbatim() {
        val entries = listOf(
            DiagnosticsLogEntry(1_754_000_000_000L, DiagnosticsLevel.WARN, "قارئ", "فشل فتح الكتاب"),
        )

        assertEquals(
            listOf("2025-07-31T22:13:20Z [WARN] (قارئ) فشل فتح الكتاب"),
            bodyLines(store().exportText(entries, generatedAt = 0L)),
        )
    }

    @Test
    fun exportOfALargeBatchEmitsExactlyOneLinePerEntry() {
        val entries = (1..2_000).map { entry(it.toLong(), "entry $it") }

        val body = bodyLines(store().exportText(entries, generatedAt = 0L))

        assertEquals(2_000, body.size)
        assertTrue(body.all { entryLine.containsMatchIn(it) })
    }
}
