// Purpose: feature #131 WI-6 — the CONCURRENCY-DECISIVE prefetch tests for BilingualViewModel:
// per-unit single-flight, stale/superseded discard (superseded FAILURE never errorUnit; stale
// SUCCESS still clears inFlightUnits), a lookahead-turned-current joins + still commits / still
// surfaces its own failure (Gate-4 High), an unexpected throwable surfaces a retryable
// errorUnit, a generation bump (disable / language change) discards stale in-flight,
// dual-cancellation (native + typed Cancelled, never errorUnit), and invalidate → same-unit
// replacement holds single-flight. Shared fakes: BilingualPrefetchFakes.kt.
package com.vreader.app.bilingual

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiProviderSnapshot
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class BilingualViewModelPrefetchConcurrencyTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val dispatcher = StandardTestDispatcher()
    private val bookKey = "txt:abc:100"

    private lateinit var perBookStore: PerBookBilingualStore
    private val cipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }
    private lateinit var aiStore: AiProviderStore
    private lateinit var readiness: BilingualAiReadiness
    private var currentSnapshot = AiProviderSnapshot(listOf(profile("p1", "s3cret")), activeId = "p1")
    private val snapshotProvider: suspend () -> AiProviderSnapshot = { currentSnapshot }
    private lateinit var concretePrefetcher: ChapterTranslationPrefetcher
    private lateinit var provider: FakeTextProvider
    private lateinit var fake: FakePrefetching

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        val ds: DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) {
            java.io.File(context.cacheDir, "vmpc-bilingual-${System.nanoTime()}.preferences_pb")
        }
        perBookStore = PerBookBilingualStore(ds)
        aiStore = AiProviderStore(
            PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) {
                java.io.File(context.cacheDir, "vmpc-ai-${System.nanoTime()}.preferences_pb")
            },
            cipher,
        )
        readiness = BilingualAiReadiness(aiStore)
        provider = FakeTextProvider()
        concretePrefetcher = ChapterTranslationPrefetcher(
            bookKey = bookKey, textProvider = provider, store = aiStore,
            serviceFactory = { throw IllegalStateException("the concrete prefetcher must not run") },
            clientFactory = { _, _ -> throw IllegalStateException("no client") },
        )
        fake = FakePrefetching()
    }

    @After fun tearDown() = Dispatchers.resetMain()

    private fun makeEnabledVM(): BilingualViewModel {
        val vm = BilingualViewModel(
            bookKey = bookKey, store = perBookStore, prefetcher = concretePrefetcher,
            snapshotProvider = snapshotProvider, readiness = readiness, dispatcher = dispatcher,
            prefetching = fake, textProvider = provider,
        )
        vm.setEnabled(on = true)
        return vm
    }

    private fun profile(id: String, key: String) = AiProviderProfile(
        id = id, name = "P", kind = AiProviderKind.openAiCompatible, baseUrl = "https://x/", model = "m",
        encryptedApiKey = cipher.encrypt(key),
    )

    private fun txtUnit(idx: Int) =
        TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, idx.toString())

    // ── rapid re-trigger of the SAME in-flight unit → single-flight job-join (one write) ──
    // Uses retryUnit (no anchor dedupe) so the 2nd/3rd trigger reaches the job-level
    // single-flight guard (`prefetchTasks[unit] active → join`), asserting the registry itself
    // prevents a double dispatch.

    @Test fun rapidSameUnit_singleFlight_noDoubleWrite() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        val gate = CompletableDeferred<Unit>()
        fake.pending[txtUnit(0)] = gate

        vm.retryUnit(txtUnit(0))
        vm.retryUnit(txtUnit(0))
        vm.retryUnit(txtUnit(0))
        advanceUntilIdle()   // unit 0 still gated
        assertEquals("only ONE dispatch reached the seam", 1, fake.prefetchInvocations.count { it == txtUnit(0) })

        gate.complete(Unit); advanceUntilIdle()
        assertEquals("exactly one completed write", 1, fake.completed[txtUnit(0)])
    }

    // ── a lookahead unit that becomes current still commits (Gate-4 High-1 regression) ──
    // Position at unit 0 launches units 0+1 (unit 1 as lookahead); MOVE to unit 1 while its
    // lookahead job is still in flight — the join must NOT discard unit 1's own result, or the
    // now-current unit stays untranslated forever.

    @Test fun lookaheadBecomesCurrent_stillCommits() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1), txtUnit(2)); provider.containing = txtUnit(0)
        // Gate unit 1 (the lookahead) so it is still in flight when we move onto it.
        val gate1 = CompletableDeferred<Unit>()
        fake.pending[txtUnit(1)] = gate1

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()   // launches 0 (done) + 1 (gated)
        assertTrue("unit 1 in flight as lookahead", vm.state.value.inFlightUnits.contains(txtUnit(1)))

        // Move onto unit 1 while it is still running — it becomes the current unit.
        provider.containing = txtUnit(1)
        vm.onPositionChanged(charOffsetUtf16 = 12); advanceUntilIdle()

        gate1.complete(Unit); advanceUntilIdle()
        assertTrue("the now-current unit 1 is translated (its joined job committed)",
            vm.state.value.translationsByUnit.containsKey(txtUnit(1)))
        assertFalse("unit 1 not left in flight", vm.state.value.inFlightUnits.contains(txtUnit(1)))
        assertEquals("single-flight held across the join", 1, fake.completed[txtUnit(1)])
    }

    // ── a lookahead unit that becomes current AND then fails surfaces errorUnit (Gate-4 r2 High) ──
    // Its captured seq is older, but as the STILL-CURRENT unit the failure must not be swallowed.
    @Test fun lookaheadBecomesCurrent_thenFails_surfacesErrorUnit() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1), txtUnit(2)); provider.containing = txtUnit(0)
        val gate1 = CompletableDeferred<Unit>()
        fake.pending[txtUnit(1)] = gate1
        fake.throwTyped[txtUnit(1)] = ChapterTranslationError.ProviderFailed("boom")

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()   // 0 done, 1 gated as lookahead
        provider.containing = txtUnit(1)
        vm.onPositionChanged(charOffsetUtf16 = 12); advanceUntilIdle()   // move onto 1 (still in flight, joins)

        gate1.complete(Unit); advanceUntilIdle()   // unit 1 fails LATE while it is the current unit

        assertEquals("a failure for the now-current unit surfaces errorUnit", txtUnit(1), vm.state.value.errorUnit)
        assertFalse("failed current unit not stuck in flight", vm.state.value.inFlightUnits.contains(txtUnit(1)))
    }

    // ── an unexpected (non-typed) throwable still surfaces a retryable errorUnit (Gate-4 r2 Medium) ──
    @Test fun unexpectedThrowable_surfacesErrorUnit_noStuckSpinner() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        fake.raw[txtUnit(0)] = IllegalStateException("cache blew up")

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()

        assertEquals("an unexpected error maps to a retryable errorUnit", txtUnit(0), vm.state.value.errorUnit)
        assertFalse("no stuck spinner after an unexpected error", vm.state.value.inFlightUnits.contains(txtUnit(0)))
    }

    // ── a superseded stale SUCCESS is committed but never leaves the unit stuck in flight ──
    // (Gate-4 High-2 regression: the stale-discard path must clear inFlightUnits.)

    @Test fun staleSuccess_clearsInFlight_noErrorUnit() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1), txtUnit(2)); provider.containing = txtUnit(0)
        val gate0 = CompletableDeferred<Unit>()
        fake.pending[txtUnit(0)] = gate0

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertTrue("unit 0 launched, still in flight", vm.state.value.inFlightUnits.contains(txtUnit(0)))

        // Supersede: move to unit 2. Unit 0's late success must not leave it stuck in flight.
        provider.containing = txtUnit(2)
        vm.onPositionChanged(charOffsetUtf16 = 20); advanceUntilIdle()
        gate0.complete(Unit); advanceUntilIdle()

        assertFalse("stale success does not leave unit 0 stuck in flight", vm.state.value.inFlightUnits.contains(txtUnit(0)))
        assertNull("a superseded request never surfaces errorUnit", vm.state.value.errorUnit)
        assertTrue("the newer unit 2 is translated", vm.state.value.translationsByUnit.containsKey(txtUnit(2)))
    }

    // ── a superseded stale FAILURE is discarded → no errorUnit ──

    @Test fun cancelMid_staleFailureDiscarded_noErrorUnit() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1), txtUnit(2)); provider.containing = txtUnit(0)
        val gate0 = CompletableDeferred<Unit>()
        fake.pending[txtUnit(0)] = gate0
        fake.throwTyped[txtUnit(0)] = ChapterTranslationError.ProviderFailed("late boom")

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        provider.containing = txtUnit(2)
        vm.onPositionChanged(charOffsetUtf16 = 20); advanceUntilIdle()
        gate0.complete(Unit); advanceUntilIdle()   // unit 0 fails LATE, superseded

        assertNull("a superseded stale FAILURE must NOT surface errorUnit", vm.state.value.errorUnit)
        assertFalse("stale-failed unit not stuck in flight", vm.state.value.inFlightUnits.contains(txtUnit(0)))
    }

    // ── a typed ChapterTranslationError.Cancelled is discarded, not errorUnit ──

    @Test fun typedCancelled_discarded_notErrorUnit() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        fake.throwTyped[txtUnit(0)] = ChapterTranslationError.Cancelled

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertNull("typed Cancelled must NOT surface as errorUnit", vm.state.value.errorUnit)
        assertFalse("Cancelled is not an unavailable outcome", vm.state.value.unavailableUnits.contains(txtUnit(0)))
        assertFalse("Cancelled unit not stuck in flight", vm.state.value.inFlightUnits.contains(txtUnit(0)))
    }

    // ── a generation bump (disable) discards a stale in-flight result ──

    @Test fun disable_generationBump_discardsStaleInFlight() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        val gate = CompletableDeferred<Unit>()
        fake.pending[txtUnit(0)] = gate

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertTrue(vm.state.value.inFlightUnits.contains(txtUnit(0)))

        vm.setEnabled(on = false); advanceUntilIdle()
        gate.complete(Unit); advanceUntilIdle()

        assertTrue("no translations after a disable-discarded stale result", vm.state.value.translationsByUnit.isEmpty())
        assertNull(vm.state.value.errorUnit)
        assertTrue(vm.state.value.inFlightUnits.isEmpty())
    }

    // ── a language change discards a stale in-flight result ──

    @Test fun languageChange_generationBump_discardsStaleInFlight() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        val gate = CompletableDeferred<Unit>()
        fake.pending[txtUnit(0)] = gate

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertTrue(vm.state.value.inFlightUnits.contains(txtUnit(0)))

        vm.setTargetLanguage("Japanese"); advanceUntilIdle()
        gate.complete(Unit); advanceUntilIdle()

        assertTrue("a language change discards the stale in-flight translation", vm.state.value.translationsByUnit.isEmpty())
        assertNull(vm.state.value.errorUnit)
    }

    // ── invalidate (language change) → same-unit replacement → single-flight + correct commit ──
    // After a language change cancels the in-flight original + bumps generation, a replacement
    // dispatch for the same unit runs cleanly under the NEW generation: exactly one completed
    // write, committed, with a second concurrent retry joining the live replacement job.

    @Test fun invalidateThenReplace_singleFlightHolds() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        val gateOriginal = CompletableDeferred<Unit>()
        fake.pending[txtUnit(0)] = gateOriginal

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()   // original unit-0 job gated in flight

        // Language change drains here → invalidate() cancels the original + bumps generation.
        vm.setTargetLanguage("Japanese"); advanceUntilIdle()
        assertTrue("the cancelled original's stale state was cleared", vm.state.value.inFlightUnits.isEmpty())

        val dispatchesBeforeReplacement = fake.prefetchInvocations.count { it == txtUnit(0) }
        // Register a REPLACEMENT for the same unit, gated separately, still in flight.
        val gateReplacement = CompletableDeferred<Unit>()
        fake.pending[txtUnit(0)] = gateReplacement
        vm.retryUnit(txtUnit(0)); advanceUntilIdle()
        // A second retry while the replacement is in flight must JOIN it (single-flight).
        vm.retryUnit(txtUnit(0)); advanceUntilIdle()
        assertEquals("single-flight: the replacement dispatched exactly once (the 2nd retry joined)",
            dispatchesBeforeReplacement + 1, fake.prefetchInvocations.count { it == txtUnit(0) })

        gateReplacement.complete(Unit); advanceUntilIdle()

        assertEquals("exactly one COMPLETED write (the replacement; the cancelled original never completed)",
            1, fake.completed[txtUnit(0)])
        assertTrue("the replacement's translation committed", vm.state.value.translationsByUnit.containsKey(txtUnit(0)))
    }
}
