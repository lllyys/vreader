// Purpose: feature #131 WI-6 — RED-first JVM tests for the BilingualViewModel POSITION-DRIVEN
// PREFETCH behavior: onPositionChanged derives the current TXT/MD unit, dedupes, prefetches
// current+next; Offline → unavailableUnits; a transient failure surfaces a retryable errorUnit
// and clears the anchor so retryUnit / the same position re-fetches; EPUB units are NOT
// dispatched (TXT/MD only); onEpubBlocksEnumerated is inert (owned by WI-7b). The
// concurrency-decisive cases (single-flight, stale/superseded discard, generation-guard
// discard, dual-cancellation) live in BilingualViewModelPrefetchConcurrencyTest. Shared fakes:
// BilingualPrefetchFakes.kt.
//
// Same harness as BilingualViewModelTest: Dispatchers.setMain(StandardTestDispatcher) +
// runTest(dispatcher) + advanceUntilIdle() + assert on state.value (no Turbine).
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
class BilingualViewModelPrefetchTest {
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
            java.io.File(context.cacheDir, "vmp-bilingual-${System.nanoTime()}.preferences_pb")
        }
        perBookStore = PerBookBilingualStore(ds)
        aiStore = AiProviderStore(
            PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) {
                java.io.File(context.cacheDir, "vmp-ai-${System.nanoTime()}.preferences_pb")
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

    // ── current + next prefetched on a unit change ──

    @Test fun positionChange_prefetchesCurrentAndNext() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1), txtUnit(2))
        provider.containing = txtUnit(0)

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()

        assertEquals("current + next both prefetched", setOf(txtUnit(0), txtUnit(1)), fake.completed.keys.toSet())
        assertTrue("current unit translated", vm.state.value.translationsByUnit.containsKey(txtUnit(0)))
        assertTrue("next unit translated", vm.state.value.translationsByUnit.containsKey(txtUnit(1)))
        assertTrue("nothing left in flight", vm.state.value.inFlightUnits.isEmpty())
    }

    // ── same-unit re-trigger is a no-op (dedupe) ──

    @Test fun sameUnitReTrigger_isNoOp() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        val callsAfterFirst = fake.prefetchInvocations.toList()

        vm.onPositionChanged(charOffsetUtf16 = 7); advanceUntilIdle()
        assertEquals("same-unit re-trigger dispatches nothing new", callsAfterFirst, fake.prefetchInvocations.toList())
    }

    // ── Offline → the unit goes to unavailableUnits ──

    @Test fun offline_marksUnavailable() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        fake.throwTyped[txtUnit(0)] = ChapterTranslationError.Offline

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()

        assertTrue("offline unit is unavailable", vm.state.value.unavailableUnits.contains(txtUnit(0)))
        assertNull("offline is not a retryable errorUnit", vm.state.value.errorUnit)
        assertFalse("offline unit is not stuck in flight", vm.state.value.inFlightUnits.contains(txtUnit(0)))
    }

    // ── a transient failure leaves the unit unfetched, clears the anchor → retryUnit re-fetches ──

    @Test fun transientFailure_thenRetry_reFetches() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        fake.throwTyped[txtUnit(0)] = ChapterTranslationError.ProviderFailed("boom")

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertEquals("failure surfaces the errorUnit", txtUnit(0), vm.state.value.errorUnit)
        assertFalse("a failed unit is not translated", vm.state.value.translationsByUnit.containsKey(txtUnit(0)))
        assertFalse("a failed unit is not stuck in flight", vm.state.value.inFlightUnits.contains(txtUnit(0)))

        fake.throwTyped.remove(txtUnit(0))
        vm.retryUnit(txtUnit(0)); advanceUntilIdle()
        assertTrue("retry re-fetches the unit", vm.state.value.translationsByUnit.containsKey(txtUnit(0)))
        assertNull("errorUnit cleared after a successful retry", vm.state.value.errorUnit)
    }

    // ── the SAME position re-triggers after a transient failure cleared the anchor ──

    @Test fun failure_clearsAnchor_soSamePositionReTriggers() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)
        fake.throwTyped[txtUnit(0)] = ChapterTranslationError.ProviderFailed("boom")

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        val callsAfterFail = fake.prefetchInvocations.count { it == txtUnit(0) }
        assertTrue("unit 0 was attempted", callsAfterFail >= 1)

        fake.throwTyped.remove(txtUnit(0))
        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertTrue("a failed anchor is retried on the same position",
            fake.prefetchInvocations.count { it == txtUnit(0) } > callsAfterFail)
        assertTrue("re-trigger now translates the unit", vm.state.value.translationsByUnit.containsKey(txtUnit(0)))
    }

    // ── an EPUB unit is NOT dispatched by the position-driven path (TXT/MD only) ──

    @Test fun epubUnit_notDispatchedByPositionPath() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        val epub = TranslationUnitId(TranslationUnitId.Kind.epubHref, "ch1.xhtml")
        provider.units = listOf(epub); provider.containing = epub

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertTrue("the position path never prefetches an EPUB unit", fake.prefetchInvocations.isEmpty())
        assertTrue(vm.state.value.translationsByUnit.isEmpty())
    }

    // ── position past EOF (unitAfter → null) does not crash; only the current unit is prefetched ──

    @Test fun positionAtEof_noNext_noCrash() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = listOf(txtUnit(0)); provider.containing = txtUnit(0)

        vm.onPositionChanged(charOffsetUtf16 = 999); advanceUntilIdle()
        assertEquals("only the current (last) unit is prefetched", setOf(txtUnit(0)), fake.completed.keys.toSet())
        assertTrue(vm.state.value.translationsByUnit.containsKey(txtUnit(0)))
    }

    // ── no resolvable current unit (empty document) → no dispatch, no crash ──

    @Test fun noResolvableUnit_noDispatch() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        provider.units = emptyList(); provider.containing = null

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertTrue(fake.prefetchInvocations.isEmpty())
    }

    // ── position path is inert while bilingual is disabled ──

    @Test fun disabledMode_positionChangeIsInert() = runTest(dispatcher) {
        val vm = BilingualViewModel(
            bookKey = bookKey, store = perBookStore, prefetcher = concretePrefetcher,
            snapshotProvider = snapshotProvider, readiness = readiness, dispatcher = dispatcher,
            prefetching = fake, textProvider = provider,
        )
        advanceUntilIdle()
        provider.units = listOf(txtUnit(0), txtUnit(1)); provider.containing = txtUnit(0)

        vm.onPositionChanged(charOffsetUtf16 = 5); advanceUntilIdle()
        assertTrue("no prefetch while disabled", fake.prefetchInvocations.isEmpty())
    }

    // ── onEpubBlocksEnumerated feeds VM render state (WI-9) without triggering a VM prefetch ──

    /** WI-9: when ENABLED, the controller's onEpubBlocksEnumerated writes the EPUB unit into the VM's
     *  translationsByUnit (single-writer render state) WITHOUT the VM ever running a prefetch for it
     *  (EPUB prefetch stays controller-owned — Medium-1). */
    @Test fun onEpubBlocksEnumerated_populatesTranslations_noPrefetch() = runTest(dispatcher) {
        val vm = makeEnabledVM(); advanceUntilIdle()
        val unit = TranslationUnitId(TranslationUnitId.Kind.epubHref, "ch1")
        vm.onEpubBlocksEnumerated(unit, listOf("译文a", "译文b"))
        advanceUntilIdle()
        // the VM's own prefetch is NEVER invoked for an EPUB unit (still controller-owned).
        assertTrue("EPUB enumerate never drives the VM prefetch", fake.prefetchInvocations.isEmpty())
        // but the render state now reflects the committed EPUB translation (finding a).
        assertEquals(listOf("译文a", "译文b"), vm.state.value.translationsByUnit[unit])
    }

    /** WI-9: a controller commit that lands while bilingual is DISABLED (a stale post-clear callback) is
     *  IGNORED — it must not re-seed a translation the user turned off. */
    @Test fun onEpubBlocksEnumerated_whileDisabled_ignored() = runTest(dispatcher) {
        val vm = BilingualViewModel(
            bookKey = bookKey, store = perBookStore, prefetcher = concretePrefetcher,
            snapshotProvider = snapshotProvider, readiness = readiness, dispatcher = dispatcher,
            prefetching = fake, textProvider = provider,
        )
        advanceUntilIdle() // disabled by default
        vm.onEpubBlocksEnumerated(TranslationUnitId(TranslationUnitId.Kind.epubHref, "ch1"), listOf("a", "b"))
        advanceUntilIdle()
        assertTrue("a disabled-state commit is ignored", vm.state.value.translationsByUnit.isEmpty())
    }
}
