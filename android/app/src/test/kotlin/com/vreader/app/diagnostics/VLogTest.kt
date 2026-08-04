package com.vreader.app.diagnostics

import android.util.Log
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowLog

/**
 * Feature #164 WI-3 — [VLog], the facade that records into the ring AND forwards to
 * `android.util.Log`.
 *
 * Why Robolectric rather than an injectable Log seam: the plan's §10 backward-compat guarantee
 * ("the 6 migrated sites keep emitting to android.util.Log") rests on the REAL platform call
 * happening. A seam recording `(priority, tag, message)` would assert only that VLog called its
 * own indirection — the identical hole the "assert on the log, not the ring" rule exists to
 * close, one layer down. `ShadowLog` observes the genuine `android.util.Log` invocation, and
 * Robolectric 4.13 is already a test dependency of this module.
 *
 * The tag change is DELIBERATE and BREAKING (plan Gate-2 M7): the logcat tag becomes the
 * category ("Reader"), not the old per-class tag, and the class name moves into the message
 * body ("[FoliateBridge] …"). Both halves are asserted so the break is pinned by a test rather
 * than discovered by a developer whose `adb logcat -s FoliateBridge` went quiet.
 */
@RunWith(RobolectricTestRunner::class)
class VLogTest {

    private val fixedTime = 1_785_871_572_114L
    private lateinit var ring: RingBufferDiagnosticsSource

    @Before
    fun setUp() {
        ShadowLog.clear()
        ring = RingBufferDiagnosticsSource(capacity = 64)
        VLog.install(ring, clock = { fixedTime })
    }

    @After
    fun tearDown() {
        VLog.uninstall()
        ShadowLog.clear()
    }

    private fun recorded(): List<DiagnosticsLogEntry> = runBlocking {
        (ring.recentEntries(null, Int.MAX_VALUE) as SourceResult.Available).entries
    }

    private fun logged(): List<ShadowLog.LogItem> = ShadowLog.getLogs()

    // ---------------------------------------------------------------- ring side

    @Test
    fun recordsIntoTheInstalledSinkWithTheCategoryTagAsCategory() {
        VLog.w(DiagnosticsCategory.READER, "FoliateBridge", "console[ERROR]: boom")

        val entry = recorded().single()
        assertEquals(DiagnosticsCategory.READER.tag, entry.category)
        assertEquals("Reader", entry.category)
        assertEquals(DiagnosticsLevel.WARN, entry.level)
        assertEquals("[FoliateBridge] console[ERROR]: boom", entry.message)
        assertEquals(fixedTime, entry.timeMillis)
        assertNotNull(entry.sequenceId)
    }

    @Test
    fun everyLevelEntryPointRecordsItsOwnLevel() {
        VLog.d(DiagnosticsCategory.LIBRARY, "BookShare", "d")
        VLog.i(DiagnosticsCategory.LIBRARY, "BookShare", "i")
        VLog.w(DiagnosticsCategory.LIBRARY, "BookShare", "w")
        VLog.e(DiagnosticsCategory.LIBRARY, "BookShare", "e")

        assertEquals(
            listOf(DiagnosticsLevel.DEBUG, DiagnosticsLevel.INFO, DiagnosticsLevel.WARN, DiagnosticsLevel.ERROR),
            recorded().map { it.level },
        )
    }

    @Test
    fun installReplacesThePreviousSink() {
        val replacement = RingBufferDiagnosticsSource(capacity = 4)
        VLog.install(replacement, clock = { fixedTime })
        VLog.w(DiagnosticsCategory.SYNC, "WebDavClient", "after swap")

        assertTrue(recorded().isEmpty())
        val entry = runBlocking {
            (replacement.recentEntries(null, Int.MAX_VALUE) as SourceResult.Available).entries.single()
        }
        assertEquals("[WebDavClient] after swap", entry.message)
    }

    // ---------------------------------------------------------------- LOG side (the real gate)

    /**
     * Asserted on `ShadowLog`, NOT on the ring: observing the sink proves only that the ring
     * recorded the call. The §10 guarantee is that `android.util.Log` was invoked.
     */
    @Test
    fun forwardsToAndroidLogWithThePriorityCategoryTagAndClassPrefixedBody() {
        VLog.w(DiagnosticsCategory.READER, "FoliateBridge", "console[ERROR]: boom")

        val item = logged().single()
        assertEquals(Log.WARN, item.type)
        assertEquals("Reader", item.tag)
        assertTrue("body must carry the class prefix: ${item.msg}", item.msg.contains("[FoliateBridge] console[ERROR]: boom"))
    }

    @Test
    fun theOldPerClassTagIsGoneFromTheLogItIsNowTheCategory() {
        VLog.w(DiagnosticsCategory.READER, "FoliateBridge", "boom")

        assertTrue(logged().none { it.tag == "FoliateBridge" })
        assertEquals(listOf("Reader"), logged().map { it.tag })
    }

    @Test
    fun everyLevelEntryPointForwardsWithTheMatchingAndroidPriority() {
        VLog.d(DiagnosticsCategory.AI, "AnthropicProvider", "d")
        VLog.i(DiagnosticsCategory.AI, "AnthropicProvider", "i")
        VLog.w(DiagnosticsCategory.AI, "AnthropicProvider", "w")
        VLog.e(DiagnosticsCategory.AI, "AnthropicProvider", "e")

        assertEquals(listOf(Log.DEBUG, Log.INFO, Log.WARN, Log.ERROR), logged().map { it.type })
        assertEquals(List(4) { "AI" }, logged().map { it.tag })
    }

    // ---------------------------------------------------------------- throwable

    @Test
    fun aThrowableAppendsItsStackTraceToBothRepresentations() {
        val boom = IllegalStateException("kaboom")
        VLog.w(DiagnosticsCategory.LIBRARY, "SearchIndexCoordinator", "write failed", boom)

        val message = recorded().single().message
        assertTrue(message.startsWith("[SearchIndexCoordinator] write failed"))
        assertTrue(message.contains("java.lang.IllegalStateException: kaboom"))
        assertTrue("stack frames must survive: $message", message.contains("\tat "))
        // The forwarded payload carries the same trace — the two representations must agree,
        // otherwise dedupe would surface two different-looking copies of one event.
        assertTrue(logged().single().msg.contains("java.lang.IllegalStateException: kaboom"))
    }

    @Test
    fun aNullThrowableAddsNothing() {
        VLog.e(DiagnosticsCategory.SYNC, "WebDavClient", "PROPFIND 401", null)
        assertEquals("[WebDavClient] PROPFIND 401", recorded().single().message)
    }

    // ---------------------------------------------------------------- sequence id + marker

    @Test
    fun sequenceIdsAreMonotonicAcrossCalls() {
        repeat(5) { VLog.i(DiagnosticsCategory.LIBRARY, "BookImporter", "m$it") }

        val ids = recorded().map { it.sequenceId }
        assertTrue("no null ids expected: $ids", ids.all { it != null })
        val values = ids.filterNotNull()
        assertEquals(5, values.size)
        assertEquals(values.sorted(), values)
        assertEquals(values.distinct(), values)
        values.zipWithNext { a, b -> assertTrue("ids must strictly increase: $values", b > a) }
    }

    @Test
    fun theForwardedMessageCarriesTheSequenceIdAsALeadingMarker() {
        VLog.w(DiagnosticsCategory.READER, "PdfDocument", "corrupt")

        val entry = recorded().single()
        val marker = VLogMarker.encode(entry.sequenceId!!)
        val payload = logged().single().msg
        assertTrue("marker must LEAD (logd truncates the tail): $payload", payload.startsWith(marker))
        assertEquals(marker + entry.message, payload)
    }

    /**
     * The cross-WI contract, end to end: what VLog writes to the log must parse back through
     * WI-1's [LogcatLineParser] into an entry that identity-matches the ring's copy AND has the
     * marker stripped. Without this, the composite's dedupe key is only asserted on each side
     * separately and a format drift between them would go unnoticed.
     */
    @Test
    fun theMarkerRoundTripsThroughTheLogcatParserAndIsStripped() {
        VLog.w(DiagnosticsCategory.READER, "FoliateBridge", "console[ERROR]: boom @x:1")

        val ringEntry = recorded().single()
        val payload = logged().single().msg
        val line = "2026-08-04 19:26:12.114 +0000  10209  3312  3312 W Reader: $payload"

        val parsed = LogcatLineParser.parse(sequenceOf(line), ownUid = 10209).single()
        assertEquals(ringEntry.sequenceId, parsed.sequenceId)
        assertEquals(ringEntry.message, parsed.message)
        assertEquals(ringEntry.category, parsed.category)
        assertEquals(ringEntry.level, parsed.level)
        assertFalse("marker must never reach the store: ${parsed.message}", parsed.message.contains(VLogMarker.OPEN))
    }

    /**
     * Gate-4 High regression. logd keeps entries across process launches; the ring does not. With a
     * bare per-launch counter, launch #2's first ids would be launch #1's first ids, and the
     * composite (ring wins a collision) would drop the prior-launch entries — precisely the
     * pre-crash trail the platform log exists to provide.
     *
     * The name says DISTINCT nonces, not "never": production draws the nonce at random, so the
     * guarantee is probabilistic (~1 in 2^21 per launch pair), and overclaiming it in a test name
     * would misrepresent what is actually asserted.
     */
    @Test
    fun idsFromTwoLaunchesWithDistinctNoncesDoNotCollide() {
        val firstLaunch = RingBufferDiagnosticsSource(capacity = 16)
        VLog.install(firstLaunch, { fixedTime }, launchNonce = 1L)
        repeat(3) { VLog.i(DiagnosticsCategory.READER, "ReaderActivity", "launch-1 #$it") }
        val firstIds = runBlocking {
            (firstLaunch.recentEntries(null, 10) as SourceResult.Available).entries.mapNotNull { it.sequenceId }
        }

        val secondLaunch = RingBufferDiagnosticsSource(capacity = 16)
        VLog.install(secondLaunch, { fixedTime }, launchNonce = 2L)
        repeat(3) { VLog.i(DiagnosticsCategory.READER, "ReaderActivity", "launch-2 #$it") }
        val secondIds = runBlocking {
            (secondLaunch.recentEntries(null, 10) as SourceResult.Available).entries.mapNotNull { it.sequenceId }
        }

        assertEquals(3, firstIds.size)
        assertEquals(3, secondIds.size)
        assertEquals(emptySet<Long>(), firstIds.toSet() intersect secondIds.toSet())
        // Still monotonic WITHIN each launch — the nonce is fixed, only the counter moves.
        assertEquals(firstIds.sorted(), firstIds)
        assertEquals(secondIds.sorted(), secondIds)
    }

    /**
     * The same defect at the composite boundary, end to end: a prior launch's entry read back from
     * logcat must SURVIVE alongside the current launch's ring entry, even though both are "the
     * first entry of their process".
     */
    @Test
    fun aPriorLaunchLogcatEntryIsNotDroppedByTheCurrentLaunchsRing() = runBlocking {
        val priorRing = RingBufferDiagnosticsSource(capacity = 4)
        VLog.install(priorRing, { fixedTime }, launchNonce = 11L)
        VLog.w(DiagnosticsCategory.READER, "ReaderActivity", "died here")
        val priorPayload = logged().single().msg
        val priorLine = "2026-08-04 19:26:12.114 +0000  10209  3312  3312 W Reader: $priorPayload"
        val priorFromLogcat = LogcatLineParser.parse(sequenceOf(priorLine), ownUid = 10209)

        ShadowLog.clear()
        val currentRing = RingBufferDiagnosticsSource(capacity = 4)
        VLog.install(currentRing, { fixedTime + 1 }, launchNonce = 12L)
        VLog.w(DiagnosticsCategory.READER, "ReaderActivity", "fresh start")

        val logcat = object : DiagnosticsLogSource {
            override suspend fun recentEntries(sinceMillis: Long?, limit: Int) =
                SourceResult.Available(priorFromLogcat)
        }
        val merged = CompositeDiagnosticsSource(logcat, currentRing).recentEntries(null, 50)

        assertEquals(
            listOf("[ReaderActivity] died here", "[ReaderActivity] fresh start"),
            (merged as SourceResult.Available).entries.map { it.message },
        )
    }

    // ---------------------------------------------------------------- uninstalled

    @Test
    fun callingBeforeInstallDoesNotThrowAndDoesNotRecord() {
        VLog.uninstall()
        val orphan = RingBufferDiagnosticsSource(capacity = 4)

        VLog.w(DiagnosticsCategory.READER, "ReaderActivity", "no sink installed")

        assertTrue(recorded().isEmpty())
        assertTrue(runBlocking { (orphan.recentEntries(null, 10) as SourceResult.Available).entries }.isEmpty())
    }

    /**
     * Deliberate: the §10 guarantee ("the migrated sites keep emitting to android.util.Log") is
     * UNCONDITIONAL. An entry logged in the window before `VReaderApp.onCreate` installs the sink
     * would otherwise vanish from logcat too — a silent regression against today's behavior.
     */
    @Test
    fun callingBeforeInstallStillForwardsToAndroidLog() {
        VLog.uninstall()

        VLog.w(DiagnosticsCategory.READER, "ReaderActivity", "early")

        val item = logged().single()
        assertEquals(Log.WARN, item.type)
        assertEquals("Reader", item.tag)
        assertTrue(item.msg.contains("[ReaderActivity] early"))
    }

    // ---------------------------------------------------------------- content edge cases

    @Test
    fun emptyCjkAndLongMessagesSurviveBothRepresentations() {
        VLog.i(DiagnosticsCategory.LIBRARY, "BookImporter", "")
        VLog.i(DiagnosticsCategory.LIBRARY, "BookImporter", "导入失败：第 3 本书")
        val long = "y".repeat(50_000)
        VLog.i(DiagnosticsCategory.LIBRARY, "BookImporter", long)

        val messages = recorded().map { it.message }
        assertEquals("[BookImporter] ", messages[0])
        assertEquals("[BookImporter] 导入失败：第 3 本书", messages[1])
        assertEquals("[BookImporter] $long", messages[2])
        assertEquals(3, logged().size)
        assertTrue(logged()[1].msg.endsWith("导入失败：第 3 本书"))
    }

    @Test
    fun anEmptyOriginStillProducesAWellFormedPrefix() {
        VLog.w(DiagnosticsCategory.READER, "", "no origin")
        assertEquals("[] no origin", recorded().single().message)
    }
}

/**
 * Feature #164 WI-3 — [DiagnosticsCategoryBounding].
 *
 * Lives in this file because WI-3's write-set allots exactly three test files while owning
 * `DiagnosticsCategoryBounding.kt` (its acceptance bullet sits in WI-4, which cannot write this
 * file). Shipping the source untested was the worse option. Pure JVM — no Robolectric needed.
 */
class DiagnosticsCategoryBoundingTest {

    private var clock = 0L
    private fun entry(category: String) =
        DiagnosticsLogEntry(clock++, DiagnosticsLevel.INFO, category, "m")

    private fun chipsOf(vararg categories: String) =
        DiagnosticsCategoryBounding.chips(categories.map { entry(it) })

    @Test
    fun emptyEntriesYieldOnlyTheAllChip() {
        assertEquals(listOf("All"), DiagnosticsCategoryBounding.chips(emptyList()))
    }

    @Test
    fun designedCategoryTagsAreKeptVerbatim() {
        val chips = chipsOf("Reader", "Library", "Sync")
        assertEquals("All", chips.first())
        assertEquals(setOf("Reader", "Library", "Sync"), chips.drop(1).toSet())
    }

    @Test
    fun knownLibraryTagsMapOntoTheNearestDesignedCategory() {
        assertTrue(chipsOf("SQLiteLog").contains(DiagnosticsCategory.PERSISTENCE.tag))
        assertTrue(chipsOf("chromium").contains(DiagnosticsCategory.READER.tag))
        assertTrue(chipsOf("cr_MediaCodecBridge").contains(DiagnosticsCategory.READER.tag))
        assertTrue(chipsOf("OkHttp").contains(DiagnosticsCategory.SYNC.tag))
    }

    @Test
    fun unknownTagsCollapseIntoTheSingleBucket() {
        val chips = chipsOf("ActivityManager", "ziparchive", "libEGL")
        assertEquals(listOf("All", DiagnosticsCategoryBounding.COLLAPSED_BUCKET), chips)
    }

    /**
     * A tagless logcat line parses to `category == ""`. It must be FILTERABLE (via the bucket), not
     * silently reachable only under `All`.
     */
    @Test
    fun aBlankCategoryIsBucketedNotDropped() {
        assertEquals(listOf("All", DiagnosticsCategoryBounding.COLLAPSED_BUCKET), chipsOf("", "  "))
        assertEquals(DiagnosticsCategoryBounding.COLLAPSED_BUCKET, DiagnosticsCategoryBounding.chipFor(""))
    }

    @Test
    fun theChipRowIsHardCappedEvenWithFortyDistinctRawTags() {
        val many = (1..40).map { entry("RandomFrameworkTag$it") } +
            DiagnosticsCategory.entries.map { entry(it.tag) }
        val chips = DiagnosticsCategoryBounding.chips(many)

        assertEquals("All", chips.first())
        assertTrue("at most the designed 7 category chips, got ${chips.size - 1}", chips.size - 1 <= 7)
        assertEquals(chips.distinct(), chips)
    }

    @Test
    fun chipsAreRankedByEntryCountDescending() {
        val entries = List(5) { entry("Sync") } + List(3) { entry("Reader") } + List(1) { entry("AI") }
        assertEquals(listOf("All", "Sync", "Reader", "AI"), DiagnosticsCategoryBounding.chips(entries))
    }

    @Test
    fun aCollapsedTagIsStillReachableByFilteringOnTheBucket() {
        val entries = listOf(entry("ziparchive"), entry("Reader"))
        assertTrue(DiagnosticsCategoryBounding.chips(entries).contains(DiagnosticsCategoryBounding.COLLAPSED_BUCKET))
        assertEquals(
            listOf("ziparchive"),
            entries.filter { DiagnosticsCategoryBounding.chipFor(it.category) == DiagnosticsCategoryBounding.COLLAPSED_BUCKET }
                .map { it.category },
        )
    }
}
